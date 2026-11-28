import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../../core/network/starfilm_http_client.dart';
import '../../core/security/log_sanitizer.dart';
import 'discovery_models.dart';

enum AiKeyProvider {
  gemini,
  groq,
  openRouter;

  String get displayLabel {
    switch (this) {
      case AiKeyProvider.gemini:
        return 'Gemini';
      case AiKeyProvider.groq:
        return 'Groq';
      case AiKeyProvider.openRouter:
        return 'OpenRouter';
    }
  }
}

class GeminiQuotaException implements Exception {
  GeminiQuotaException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'GeminiQuotaException($statusCode): $message';
}

class _DiscoveredModelCache {
  _DiscoveredModelCache({required this.models, required this.fetchedAt});
  final List<String> models;
  final DateTime fetchedAt;
}

enum _AttemptOutcome {
  succeeded,
  tryNextModel,
  abortKey,
  stopCascade,
}

class GeminiClient {
  GeminiClient(this._http, {DiagnosticsLog? log, this.onCacheUpdated})
      : _log = log;

  final StarFilmHttpClient _http;
  final DiagnosticsLog? _log;
  void Function(String cacheJson)? onCacheUpdated;

  static const String host = 'generativelanguage.googleapis.com';
  static const String groqHost = 'api.groq.com';
  static const String openRouterHost = 'openrouter.ai';

  static const String fallbackModel = 'gemini-3.5-flash-lite';
  static const List<String> defaultModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-3.6-flash',
    'gemini-3.8-flash',
    'gemini-4-hydrogen',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-flash-lite-latest',
    'gemini-flash-latest',
    'gemma-3-27b-it',
  ];

  static const List<String> groqFreeModels = [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'qwen/qwen3.8-27b',
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
  ];

  static const List<String> openRouterFreeModels = [
    'openrouter/free',
    'google/gemma-3-27b-it:free',
    'meta-llama/llama-3.3-70b-instruct:free',
  ];

  static const Set<String> _retiredOrInvalidModels = {
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-2.0-flash-exp',
    'gemini-3.5-pro',
  };

  static const List<String> _blockedGeminiSubstrings = [
    'tts',
    'image',
    'live',
    'transcribe',
    'embedding',
    'robotics',
    'nano-banana',
    'imagen',
    'veo',
    'aqa',
    'vision',
    'audio',
    'computer-use',
    'deep-research',
    'omni',
    'genie',
    'bisheng',
    'learnlm',
  ];

  static final RegExp _geminiVersionRe = RegExp(r'^gemini-(\d+)(?:\.(\d+))?');
  static final RegExp _gemmaSizeRe = RegExp(r'(\d+)b\b');
  static final RegExp _snapshotSuffixRe = RegExp(r'(?:-\d{3}|-\d{2}-\d{4}|-\d{4})$');
  static final RegExp _validModelIdRe = RegExp(r'^[A-Za-z0-9._-]{3,100}$');

  static const Duration _notFoundTtl = Duration(hours: 6);
  static const Duration _cooldownDuration = Duration(seconds: 90);
  static const Duration _discoveryCacheTtl = Duration(hours: 6);
  static const Duration _attemptTimeout = Duration(seconds: 12);
  static const Duration _totalRequestBudget = Duration(seconds: 32);
  static const int _maxStallErrorsPerKey = 2;

  final Map<String, Map<String, DateTime>> _notFoundUntilByKey = {};
  final Map<String, Map<String, DateTime>> _cooldownUntilByKey = {};
  final Map<String, Map<String, DateTime>> _providerCooldownUntil = {};
  final Map<String, _DiscoveredModelCache> _discoveredModelsByKey = {};
  final Map<String, String> _lastWorkingModelByKey = {};
  String _lastWorkingModel = '';
  String _lastWorkingProvider = '';
  String _activeKeyHash = '';

  String get lastWorkingModel => _lastWorkingModel;
  String get lastWorkingProvider => _lastWorkingProvider;
  String get lastWorkingLabel => _lastWorkingModel.isEmpty
      ? ''
      : (_lastWorkingProvider.isEmpty
          ? _lastWorkingModel
          : '$_lastWorkingProvider/$_lastWorkingModel');

  List<String> get discoveredModels {
    final cached = _discoveredModelsByKey[_activeKeyHash];
    if (cached != null) return List.unmodifiable(cached.models);
    for (final entry in _discoveredModelsByKey.values) {
      if (entry.models.isNotEmpty) return List.unmodifiable(entry.models);
    }
    return const [];
  }

  /// Returns a non-reversible SHA-256 fingerprint prefix for keying model health state.
  static String keyFingerprint(String rawKey) {
    final clean = rawKey.trim();
    if (clean.isEmpty) return 'empty';
    final hex = sha256.convert(utf8.encode(clean)).toString();
    return hex.length > 16 ? hex.substring(0, 16) : hex;
  }

  static String normalizeDiscoveredId(String raw) {
    var t = raw.trim();
    if (t.startsWith('models/')) {
      t = t.substring(7).trim();
    }
    return t;
  }

  static bool isUsableGeminiTextModelId(String rawName) {
    final id = normalizeDiscoveredId(rawName);
    if (!_validModelIdRe.hasMatch(id)) return false;
    final low = id.toLowerCase();
    if (!(low.startsWith('gemini-') || low.startsWith('gemma-'))) return false;
    return !_blockedGeminiSubstrings.any(low.contains);
  }

  static List<String> rankDiscoveredModels(Iterable<String> rawModels) {
    final unique = <String>{};
    for (final raw in rawModels) {
      final id = normalizeDiscoveredId(raw);
      if (isUsableGeminiTextModelId(id)) {
        unique.add(id);
      }
    }
    return unique.toList()..sort(compareGeminiModels);
  }

  static int _modelTier(String low) {
    final isLatest = low.endsWith('-latest');
    if (low.startsWith('gemini-')) {
      if (isLatest) {
        if (low == 'gemini-flash-lite-latest' || low == 'gemini-flash-latest') {
          return 2;
        }
        return 4;
      }
      if (low.contains('flash-lite')) return 0;
      if (low.contains('flash')) return 1;
      return 3;
    }
    return 5;
  }

  static (int, int) _parseGeminiVersion(String low) {
    final m = _geminiVersionRe.firstMatch(low);
    if (m == null) return (0, 0);
    final maj = int.tryParse(m.group(1) ?? '') ?? 0;
    final min = int.tryParse(m.group(2) ?? '') ?? 0;
    return (maj, min);
  }

  static int _parseParamSizeB(String low) {
    var best = 0;
    for (final m in _gemmaSizeRe.allMatches(low)) {
      final v = int.tryParse(m.group(1) ?? '') ?? 0;
      if (v > best) best = v;
    }
    return best;
  }

  static int compareGeminiModels(String a, String b) {
    final la = a.toLowerCase();
    final lb = b.toLowerCase();
    final ta = _modelTier(la);
    final tb = _modelTier(lb);
    if (ta != tb) return ta.compareTo(tb);
    if (ta == 2) {
      final sa = la.contains('flash-lite') ? 0 : 1;
      final sb = lb.contains('flash-lite') ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
    }
    if (ta < 5) {
      final (majA, minA) = _parseGeminiVersion(la);
      final (majB, minB) = _parseGeminiVersion(lb);
      if (majA != majB) return majB.compareTo(majA);
      if (minA != minB) return minB.compareTo(minA);
    } else {
      final sa = _parseParamSizeB(la);
      final sb = _parseParamSizeB(lb);
      if (sa != sb) return sb.compareTo(sa);
    }
    final pa = la.contains('-preview') ||
        la.contains('-exp') ||
        la.contains('experimental');
    final pb = lb.contains('-preview') ||
        lb.contains('-exp') ||
        lb.contains('experimental');
    if (pa != pb) return pa ? 1 : -1;
    final sna = _snapshotSuffixRe.hasMatch(la);
    final snb = _snapshotSuffixRe.hasMatch(lb);
    if (sna != snb) return sna ? 1 : -1;
    return la.compareTo(lb);
  }

  String exportCacheJson() {
    final keysMap = <String, dynamic>{};
    final hashes = <String>{
      ..._discoveredModelsByKey.keys,
      ..._lastWorkingModelByKey.keys,
    };
    for (final h in hashes) {
      if (h.isEmpty || h == 'empty') continue;
      final disc = _discoveredModelsByKey[h];
      final last = _lastWorkingModelByKey[h] ?? '';
      keysMap[h] = {
        'fetchedAt': disc?.fetchedAt.millisecondsSinceEpoch ?? 0,
        'lastWorking': last,
        'discovered': disc?.models ?? const <String>[],
      };
    }
    return jsonEncode({
      'schema': 1,
      'keys': keysMap,
    });
  }

  void importCacheJson(String raw, {DateTime? now}) {
    if (raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      if ((decoded['schema'] as num?)?.toInt() != 1) return;
      final keysObj = decoded['keys'];
      if (keysObj is! Map<String, dynamic>) return;
      final refNow = now ?? DateTime.now();
      for (final entry in keysObj.entries) {
        final h = entry.key.trim();
        if (h.isEmpty ||
            h == 'empty' ||
            entry.value is! Map<String, dynamic>) {
          continue;
        }
        final data = entry.value as Map<String, dynamic>;
        final last = (data['lastWorking'] ?? '').toString().trim();
        if (last.isNotEmpty) {
          _lastWorkingModelByKey[h] = last;
          if (_lastWorkingModel.isEmpty) {
            _lastWorkingModel = last;
            _lastWorkingProvider = 'gemini';
          }
        }
        final rawList = data['discovered'];
        if (rawList is List) {
          final models = rawList
              .map((e) => normalizeDiscoveredId(e.toString()))
              .where((m) => m.isNotEmpty)
              .toList();
          final fetchedMs = (data['fetchedAt'] as num?)?.toInt() ?? 0;
          final fetchedAt = (fetchedMs > 0 &&
                  fetchedMs <= refNow.millisecondsSinceEpoch + 60000)
              ? DateTime.fromMillisecondsSinceEpoch(fetchedMs)
              : DateTime.fromMillisecondsSinceEpoch(0);
          if (models.isNotEmpty) {
            _discoveredModelsByKey[h] = _DiscoveredModelCache(
              models: models,
              fetchedAt: fetchedAt,
            );
          }
        }
      }
    } catch (_) {}
  }

  /// Detects AI provider by API key prefix (`gsk_` -> Groq, `sk-or-` -> OpenRouter, else Gemini).
  static AiKeyProvider detectProvider(String rawKey) {
    final k = rawKey.trim();
    if (k.startsWith('gsk_')) return AiKeyProvider.groq;
    if (k.startsWith('sk-or-')) return AiKeyProvider.openRouter;
    return AiKeyProvider.gemini;
  }

  /// Splits one or multiple backup API keys separated by newlines, commas, or semicolons.
  static List<String> parseKeyList(String raw) {
    final parts = raw.split(RegExp(r'[\r\n,;]+'));
    final seen = <String>{};
    final out = <String>[];
    for (final part in parts) {
      final k = part.trim();
      if (k.isNotEmpty && seen.add(k)) {
        out.add(k);
      }
    }
    return out;
  }

  /// Maps retired or unavailable legacy model IDs to the active default model.
  static String normalizeModel(String? raw) {
    var trimmed = raw?.trim() ?? '';
    if (trimmed.startsWith('models/')) {
      trimmed = trimmed.substring(7).trim();
    }
    if (trimmed.isEmpty || _retiredOrInvalidModels.contains(trimmed)) {
      return fallbackModel;
    }
    return trimmed;
  }

  Future<bool> verifyKey(String apiKey, {String model = fallbackModel}) async {
    final key = apiKey.trim();
    if (key.isEmpty) return false;
    if (detectProvider(key) != AiKeyProvider.gemini) {
      return verifyBackupKey(key);
    }
    final resolvedModel = normalizeModel(model);
    final uri = Uri.https(host, '/v1beta/models/$resolvedModel', {'key': key});
    final res = await _http.get(uri);
    if (res.isOk) return true;
    if (res.statusCode == 404) {
      final listUri = Uri.https(host, '/v1beta/models', {'pageSize': '1', 'key': key});
      final listRes = await _http.get(listUri);
      return listRes.isOk;
    }
    return false;
  }

  /// Verifies one or more backup keys across Gemini, Groq, and OpenRouter.
  Future<bool> verifyBackupKey(String rawKey) async {
    final keys = parseKeyList(rawKey);
    if (keys.isEmpty) return false;
    for (final key in keys) {
      final provider = detectProvider(key);
      switch (provider) {
        case AiKeyProvider.gemini:
          if (await verifyKey(key)) return true;
        case AiKeyProvider.groq:
          final res = await _http.get(
            Uri.https(groqHost, '/openai/v1/models'),
            headers: {'Authorization': 'Bearer $key'},
          );
          if (res.isOk) return true;
        case AiKeyProvider.openRouter:
          final authRes = await _http.get(
            Uri.https(openRouterHost, '/api/v1/auth/key'),
            headers: {'Authorization': 'Bearer $key'},
          );
          if (authRes.isOk) return true;
          if (authRes.statusCode == 404) {
            final modelsRes = await _http.get(
              Uri.https(openRouterHost, '/api/v1/models'),
              headers: {'Authorization': 'Bearer $key'},
            );
            if (modelsRes.isOk) return true;
          }
      }
    }
    return false;
  }

  /// Executes AI recommendations with automatic model cascade, dynamic discovery,
  /// and optional backup keys (Gemini #2 / Groq / OpenRouter).
  Future<List<GeminiCandidate>> generateCandidates({
    required String apiKey,
    String backupApiKey = '',
    required String model,
    required DiscoveryRequest request,
    required UserProfile profile,
    required List<LibraryEntry> library,
    required List<String> recentShownLabels,
    void Function(String provider, String model)? onModelUsed,
  }) async {
    final keyEntries = <({AiKeyProvider provider, String key})>[];
    final seenKeys = <String>{};
    for (final raw in [apiKey, ...parseKeyList(backupApiKey)]) {
      final clean = raw.trim();
      if (clean.isEmpty || !seenKeys.add(clean)) continue;
      keyEntries.add((provider: detectProvider(clean), key: clean));
    }

    if (keyEntries.isEmpty) {
      throw GeminiQuotaException(0, 'Missing Gemini API key');
    }

    final promptPayload = buildCompactPromptPayload(
      request: request,
      profile: profile,
      library: library,
      recentShownLabels: recentShownLabels,
    );

    final systemPrompt = _buildPromptText(
      contentLanguage: profile.preferences.contentLanguage,
      request: request,
      compactPayload: promptPayload,
    );
    final temperature = request.different ? 0.95 : 0.7;

    var lastStatus = 0;
    var lastReason = '';

    for (final entry in keyEntries) {
      final result = switch (entry.provider) {
        AiKeyProvider.gemini => await _tryGeminiKey(
            key: entry.key,
            preferredModel: model,
            temperature: temperature,
            systemPrompt: systemPrompt,
            onStatus: (status, reason) {
              lastStatus = status;
              lastReason = reason;
            },
            onModelUsed: onModelUsed,
          ),
        AiKeyProvider.groq => await _tryGroqKey(
            key: entry.key,
            temperature: temperature,
            systemPrompt: systemPrompt,
            onStatus: (status, reason) {
              lastStatus = status;
              lastReason = reason;
            },
            onModelUsed: onModelUsed,
          ),
        AiKeyProvider.openRouter => await _tryOpenRouterKey(
            key: entry.key,
            temperature: temperature,
            systemPrompt: systemPrompt,
            onStatus: (status, reason) {
              lastStatus = status;
              lastReason = reason;
            },
            onModelUsed: onModelUsed,
          ),
      };

      if (result != null && result.isNotEmpty) {
        return result;
      }
    }

    throw GeminiQuotaException(
      lastStatus,
      lastReason.isEmpty ? 'HTTP $lastStatus' : lastReason,
    );
  }

  bool _isDiscoveryStale(String keyHash) {
    final cached = _discoveredModelsByKey[keyHash];
    if (cached == null || cached.models.isEmpty) return true;
    return DateTime.now().difference(cached.fetchedAt) >= _discoveryCacheTtl;
  }

  Future<List<GeminiCandidate>?> _tryGeminiKey({
    required String key,
    required String preferredModel,
    required double temperature,
    required String systemPrompt,
    required void Function(int status, String reason) onStatus,
    void Function(String provider, String model)? onModelUsed,
  }) async {
    final now = DateTime.now();
    final keyHash = keyFingerprint(key);
    _activeKeyHash = keyHash;
    final notFound = _notFoundUntilByKey[keyHash] ?? <String, DateTime>{};
    notFound.removeWhere((_, until) => !until.isAfter(now));
    final cooldowns = _cooldownUntilByKey[keyHash] ?? <String, DateTime>{};
    cooldowns.removeWhere((_, until) => !until.isAfter(now));

    final normalizedPreferred = normalizeModel(preferredModel);
    final lastWorking = _lastWorkingModelByKey[keyHash];
    final cachedDiscovered = _discoveredModelsByKey[keyHash];

    final ordered = <String>[];
    final delayedCooldown = <String>[];
    final seenModels = <String>{};

    void addCandidate(String m) {
      if (m.isEmpty || !seenModels.add(m)) return;
      final nfUntil = notFound[m];
      if (nfUntil != null && nfUntil.isAfter(now)) return;
      final until = cooldowns[m];
      if (until != null && until.isAfter(now)) {
        delayedCooldown.add(m);
      } else {
        ordered.add(m);
      }
    }

    final preferredUnavailable = (notFound[normalizedPreferred]?.isAfter(now) ?? false) ||
        (cooldowns[normalizedPreferred]?.isAfter(now) ?? false);
    if (!preferredUnavailable) {
      addCandidate(normalizedPreferred);
    }
    if (lastWorking != null && lastWorking.isNotEmpty) {
      addCandidate(lastWorking);
    }
    if (cachedDiscovered != null) {
      for (final m in cachedDiscovered.models) {
        addCandidate(m);
      }
    }
    addCandidate(normalizedPreferred);
    for (final m in defaultModels) {
      addCandidate(m);
    }
    ordered.addAll(delayedCooldown);

    final deadline = DateTime.now().add(_totalRequestBudget);
    var abortedKey = false;
    var stoppedCascade = false;
    var stallCount = 0;
    final attempted = <String>{};

    Future<({List<GeminiCandidate>? candidates, _AttemptOutcome outcome})>
        attemptModel(String candidateModel) async {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= const Duration(seconds: 2)) {
        return (candidates: null, outcome: _AttemptOutcome.stopCascade);
      }
      final reqTimeout = remaining < _attemptTimeout ? remaining : _attemptTimeout;
      attempted.add(candidateModel);
      final isGemma = candidateModel.toLowerCase().startsWith('gemma');
      var res = await _safePostGemini(
        key: key,
        model: candidateModel,
        temperature: temperature,
        systemPrompt: systemPrompt,
        simplified: isGemma,
        timeout: reqTimeout,
        onTimeoutOrNetwork: (reason) => onStatus(0, reason),
      );
      if (res == null) {
        (_cooldownUntilByKey[keyHash] ??= <String, DateTime>{})[candidateModel] =
            DateTime.now().add(_cooldownDuration);
        stallCount++;
        return (
          candidates: null,
          outcome: stallCount >= _maxStallErrorsPerKey
              ? _AttemptOutcome.stopCascade
              : _AttemptOutcome.tryNextModel,
        );
      }

      if (!res.isOk) {
        if (res.statusCode == 401 ||
            ((res.statusCode == 400 || res.statusCode == 403) &&
                _looksLikeInvalidApiKey(res.body))) {
          onStatus(res.statusCode, 'HTTP ${res.statusCode}');
          _log?.warn('Gemini $candidateModel rejected key (HTTP ${res.statusCode})');
          return (candidates: null, outcome: _AttemptOutcome.abortKey);
        }

        if (res.statusCode == 400 && !isGemma) {
          final retryRem = deadline.difference(DateTime.now());
          if (retryRem > const Duration(seconds: 2)) {
            _log?.warn('Gemini $candidateModel HTTP 400, retrying simplified config');
            res = await _safePostGemini(
              key: key,
              model: candidateModel,
              temperature: temperature,
              systemPrompt: systemPrompt,
              simplified: true,
              timeout: retryRem < _attemptTimeout ? retryRem : _attemptTimeout,
              onTimeoutOrNetwork: (reason) => onStatus(0, reason),
            );
            if (res == null) {
              (_cooldownUntilByKey[keyHash] ??= <String, DateTime>{})[candidateModel] =
                  DateTime.now().add(_cooldownDuration);
              stallCount++;
              return (
                candidates: null,
                outcome: stallCount >= _maxStallErrorsPerKey
                    ? _AttemptOutcome.stopCascade
                    : _AttemptOutcome.tryNextModel,
              );
            }
          }
        }
      }

      if (!res.isOk) {
        onStatus(res.statusCode, 'HTTP ${res.statusCode}');
        _log?.warn('Gemini $candidateModel HTTP ${res.statusCode}');
        if (res.statusCode == 401 ||
            ((res.statusCode == 400 || res.statusCode == 403) &&
                _looksLikeInvalidApiKey(res.body))) {
          return (candidates: null, outcome: _AttemptOutcome.abortKey);
        }
        if (res.statusCode == 404) {
          (_notFoundUntilByKey[keyHash] ??= <String, DateTime>{})[candidateModel] =
              DateTime.now().add(_notFoundTtl);
          if (_lastWorkingModelByKey[keyHash] == candidateModel) {
            _lastWorkingModelByKey.remove(keyHash);
          }
        } else if (res.statusCode == 429 || res.statusCode >= 500) {
          (_cooldownUntilByKey[keyHash] ??= <String, DateTime>{})[candidateModel] =
              DateTime.now().add(_cooldownDuration);
        }
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }

      final parsed = _parseGeminiResponse(res.body);
      if (parsed.isEmpty) {
        onStatus(200, 'empty');
        _log?.warn('Gemini $candidateModel returned empty or unparseable JSON');
        (_cooldownUntilByKey[keyHash] ??= <String, DateTime>{})[candidateModel] =
            DateTime.now().add(_cooldownDuration);
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }

      _lastWorkingModelByKey[keyHash] = candidateModel;
      _lastWorkingModel = candidateModel;
      _lastWorkingProvider = 'gemini';
      onModelUsed?.call('gemini', candidateModel);
      onCacheUpdated?.call(exportCacheJson());
      if (onCacheUpdated != null && _isDiscoveryStale(keyHash)) {
        unawaited(_discoverGeminiModels(key, keyHash: keyHash).then((models) {
          if (models.isNotEmpty) onCacheUpdated?.call(exportCacheJson());
        }));
      }
      return (candidates: parsed, outcome: _AttemptOutcome.succeeded);
    }

    for (final candidateModel in ordered) {
      final res = await attemptModel(candidateModel);
      if (res.outcome == _AttemptOutcome.succeeded) return res.candidates;
      if (res.outcome == _AttemptOutcome.abortKey) {
        abortedKey = true;
        break;
      }
      if (res.outcome == _AttemptOutcome.stopCascade) {
        stoppedCascade = true;
        break;
      }
    }

    if (!abortedKey && !stoppedCascade && DateTime.now().isBefore(deadline)) {
      final discovered = await _discoverGeminiModels(key, keyHash: keyHash);
      var extraTries = 0;
      for (final candidateModel in discovered) {
        if (extraTries >= 4 || !DateTime.now().isBefore(deadline)) break;
        final nfUntil = notFound[candidateModel];
        if (attempted.contains(candidateModel) ||
            (nfUntil != null && nfUntil.isAfter(now))) {
          continue;
        }
        extraTries++;
        final res = await attemptModel(candidateModel);
        if (res.outcome == _AttemptOutcome.succeeded) return res.candidates;
        if (res.outcome == _AttemptOutcome.abortKey ||
            res.outcome == _AttemptOutcome.stopCascade) {
          break;
        }
      }
    }

    return null;
  }

  Future<HttpResult?> _safePostGemini({
    required String key,
    required String model,
    required double temperature,
    required String systemPrompt,
    required bool simplified,
    required Duration timeout,
    required void Function(String reason) onTimeoutOrNetwork,
  }) async {
    try {
      return await _postGenerate(
        key: key,
        model: model,
        temperature: temperature,
        systemPrompt: systemPrompt,
        simplified: simplified,
        timeout: timeout,
      );
    } on TimeoutException {
      onTimeoutOrNetwork('timeout');
      _log?.warn('Gemini $model timed out');
      return null;
    } catch (e) {
      onTimeoutOrNetwork('network');
      _log?.warn('Gemini $model failed: $e');
      return null;
    }
  }

  Future<List<String>> _discoverGeminiModels(String key, {String? keyHash}) async {
    final now = DateTime.now();
    final kh = keyHash ?? keyFingerprint(key);
    final cached = _discoveredModelsByKey[kh];
    if (cached != null && now.difference(cached.fetchedAt) < _discoveryCacheTtl) {
      return cached.models;
    }

    try {
      final uri = Uri.https(host, '/v1beta/models', {'pageSize': '100', 'key': key});
      final res = await _http.get(uri, timeout: const Duration(seconds: 6));
      if (!res.isOk) {
        _log?.warn('Gemini models.list HTTP ${res.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final rawModels = decoded['models'] as List<dynamic>? ?? const [];
      final rawNames = <String>[];
      for (final item in rawModels) {
        if (item is! Map<String, dynamic>) continue;
        final methods = (item['supportedGenerationMethods'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        if (!methods.contains('generateContent')) continue;
        final name = (item['name'] ?? '').toString().trim();
        if (name.isNotEmpty) rawNames.add(name);
      }

      final usable = rankDiscoveredModels(rawNames);
      _discoveredModelsByKey[kh] = _DiscoveredModelCache(
        models: usable,
        fetchedAt: now,
      );
      final nfMap = _notFoundUntilByKey[kh];
      if (nfMap != null) {
        for (final m in usable) {
          nfMap.remove(m);
        }
      }
      if (usable.isNotEmpty) {
        onCacheUpdated?.call(exportCacheJson());
      }
      return usable;
    } catch (e) {
      _log?.warn('Gemini models.list failed: $e');
      return const [];
    }
  }

  List<String> _orderWithCooldown(String providerKey, List<String> candidates) {
    final now = DateTime.now();
    final map = _providerCooldownUntil[providerKey];
    map?.removeWhere((_, until) => !until.isAfter(now));
    final primary = <String>[];
    final delayed = <String>[];
    final seen = <String>{};
    for (final m in candidates) {
      if (m.isEmpty || !seen.add(m)) continue;
      final until = map?[m];
      if (until != null && until.isAfter(now)) {
        delayed.add(m);
      } else {
        primary.add(m);
      }
    }
    return [...primary, ...delayed];
  }

  Future<List<GeminiCandidate>?> _tryGroqKey({
    required String key,
    required double temperature,
    required String systemPrompt,
    required void Function(int status, String reason) onStatus,
    void Function(String provider, String model)? onModelUsed,
  }) async {
    final providerKey = 'groq:${keyFingerprint(key)}';
    final deadline = DateTime.now().add(_totalRequestBudget);
    final attempted = <String>{};
    var abortedKey = false;
    var stoppedCascade = false;
    var stallCount = 0;

    Future<({List<GeminiCandidate>? candidates, _AttemptOutcome outcome})>
        attemptGroqModel(String model) async {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= const Duration(seconds: 2)) {
        return (candidates: null, outcome: _AttemptOutcome.stopCascade);
      }
      final reqTimeout = remaining < _attemptTimeout ? remaining : _attemptTimeout;
      attempted.add(model);
      var res = await _safePostOpenAiCompatible(
        hostName: groqHost,
        path: '/openai/v1/chat/completions',
        key: key,
        model: model,
        temperature: temperature,
        systemPrompt: systemPrompt,
        useJsonFormat: true,
        timeout: reqTimeout,
        onTimeoutOrNetwork: (reason) => onStatus(0, reason),
      );
      if (res == null) {
        (_providerCooldownUntil[providerKey] ??= {})[model] =
            DateTime.now().add(_cooldownDuration);
        stallCount++;
        return (
          candidates: null,
          outcome: stallCount >= _maxStallErrorsPerKey
              ? _AttemptOutcome.stopCascade
              : _AttemptOutcome.tryNextModel,
        );
      }
      if (!res.isOk && res.statusCode == 400) {
        final retryRem = deadline.difference(DateTime.now());
        if (retryRem > const Duration(seconds: 2)) {
          res = await _safePostOpenAiCompatible(
            hostName: groqHost,
            path: '/openai/v1/chat/completions',
            key: key,
            model: model,
            temperature: temperature,
            systemPrompt: systemPrompt,
            useJsonFormat: false,
            timeout: retryRem < _attemptTimeout ? retryRem : _attemptTimeout,
            onTimeoutOrNetwork: (reason) => onStatus(0, reason),
          );
          if (res == null) {
            (_providerCooldownUntil[providerKey] ??= {})[model] =
                DateTime.now().add(_cooldownDuration);
            stallCount++;
            return (
              candidates: null,
              outcome: stallCount >= _maxStallErrorsPerKey
                  ? _AttemptOutcome.stopCascade
                  : _AttemptOutcome.tryNextModel,
            );
          }
        }
      }
      if (!res.isOk) {
        onStatus(res.statusCode, 'HTTP ${res.statusCode}');
        _log?.warn('Groq $model HTTP ${res.statusCode}');
        if (res.statusCode == 401) {
          return (candidates: null, outcome: _AttemptOutcome.abortKey);
        }
        if (res.statusCode == 429 || res.statusCode >= 500) {
          (_providerCooldownUntil[providerKey] ??= {})[model] =
              DateTime.now().add(_cooldownDuration);
        }
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }

      final parsed = _parseOpenAiCompatibleResponse(res.body);
      if (parsed.isEmpty) {
        onStatus(200, 'empty');
        _log?.warn('Groq $model returned empty or unparseable JSON');
        (_providerCooldownUntil[providerKey] ??= {})[model] =
            DateTime.now().add(_cooldownDuration);
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }
      _lastWorkingModel = model;
      _lastWorkingProvider = 'groq';
      onModelUsed?.call('groq', model);
      return (candidates: parsed, outcome: _AttemptOutcome.succeeded);
    }

    for (final m in _orderWithCooldown(providerKey, groqFreeModels)) {
      final res = await attemptGroqModel(m);
      if (res.outcome == _AttemptOutcome.succeeded) return res.candidates;
      if (res.outcome == _AttemptOutcome.abortKey) {
        abortedKey = true;
        break;
      }
      if (res.outcome == _AttemptOutcome.stopCascade) {
        stoppedCascade = true;
        break;
      }
    }

    if (!abortedKey && !stoppedCascade && DateTime.now().isBefore(deadline)) {
      final discovered = await _discoverGroqModels(key);
      var extraTries = 0;
      for (final m in _orderWithCooldown(providerKey, discovered)) {
        if (extraTries >= 4 || !DateTime.now().isBefore(deadline)) break;
        if (attempted.contains(m)) continue;
        extraTries++;
        final res = await attemptGroqModel(m);
        if (res.outcome == _AttemptOutcome.succeeded) return res.candidates;
        if (res.outcome == _AttemptOutcome.abortKey ||
            res.outcome == _AttemptOutcome.stopCascade) {
          break;
        }
      }
    }
    return null;
  }

  Future<List<String>> _discoverGroqModels(String key) async {
    try {
      final res = await _http.get(
        Uri.https(groqHost, '/openai/v1/models'),
        headers: {'Authorization': 'Bearer $key'},
        timeout: const Duration(seconds: 6),
      );
      if (!res.isOk) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final list = decoded['data'] as List<dynamic>? ?? const [];
      const blocked = ['whisper', 'guard', 'tts', 'safeguard', 'vision'];
      final out = <String>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final id = (item['id'] ?? '').toString().trim();
        final low = id.toLowerCase();
        if (id.isEmpty || blocked.any(low.contains)) continue;
        out.add(id);
      }
      out.sort((a, b) {
        final sa = _parseParamSizeB(a.toLowerCase());
        final sb = _parseParamSizeB(b.toLowerCase());
        if (sa != sb) return sb.compareTo(sa);
        return a.compareTo(b);
      });
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<GeminiCandidate>?> _tryOpenRouterKey({
    required String key,
    required double temperature,
    required String systemPrompt,
    required void Function(int status, String reason) onStatus,
    void Function(String provider, String model)? onModelUsed,
  }) async {
    const extraHeaders = {
      'HTTP-Referer': 'https://github.com/gulivermaks/StarFilm',
      'X-Title': 'StarFilm',
    };
    final providerKey = 'openrouter:${keyFingerprint(key)}';
    final deadline = DateTime.now().add(_totalRequestBudget);
    var stallCount = 0;

    for (final model in _orderWithCooldown(providerKey, openRouterFreeModels)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= const Duration(seconds: 2)) break;
      final reqTimeout = remaining < _attemptTimeout ? remaining : _attemptTimeout;
      final isGemma = model.toLowerCase().contains('gemma');
      var res = await _safePostOpenAiCompatible(
        hostName: openRouterHost,
        path: '/api/v1/chat/completions',
        key: key,
        model: model,
        temperature: temperature,
        systemPrompt: systemPrompt,
        useJsonFormat: !isGemma,
        extraHeaders: extraHeaders,
        timeout: reqTimeout,
        onTimeoutOrNetwork: (reason) => onStatus(0, reason),
      );
      if (res == null) {
        (_providerCooldownUntil[providerKey] ??= {})[model] =
            DateTime.now().add(_cooldownDuration);
        stallCount++;
        if (stallCount >= _maxStallErrorsPerKey) break;
        continue;
      }

      if (!res.isOk && res.statusCode == 400 && !isGemma) {
        final retryRem = deadline.difference(DateTime.now());
        if (retryRem > const Duration(seconds: 2)) {
          res = await _safePostOpenAiCompatible(
            hostName: openRouterHost,
            path: '/api/v1/chat/completions',
            key: key,
            model: model,
            temperature: temperature,
            systemPrompt: systemPrompt,
            useJsonFormat: false,
            extraHeaders: extraHeaders,
            timeout: retryRem < _attemptTimeout ? retryRem : _attemptTimeout,
            onTimeoutOrNetwork: (reason) => onStatus(0, reason),
          );
          if (res == null) {
            (_providerCooldownUntil[providerKey] ??= {})[model] =
                DateTime.now().add(_cooldownDuration);
            stallCount++;
            if (stallCount >= _maxStallErrorsPerKey) break;
            continue;
          }
        }
      }

      if (!res.isOk) {
        onStatus(res.statusCode, 'HTTP ${res.statusCode}');
        _log?.warn('OpenRouter $model HTTP ${res.statusCode}');
        if (res.statusCode == 401) break;
        if (res.statusCode == 429 || res.statusCode >= 500) {
          (_providerCooldownUntil[providerKey] ??= {})[model] =
              DateTime.now().add(_cooldownDuration);
        }
        continue;
      }

      final parsed = _parseOpenAiCompatibleResponse(res.body);
      if (parsed.isEmpty) {
        onStatus(200, 'empty');
        _log?.warn('OpenRouter $model returned empty or unparseable JSON');
        (_providerCooldownUntil[providerKey] ??= {})[model] =
            DateTime.now().add(_cooldownDuration);
        continue;
      }
      _lastWorkingModel = model;
      _lastWorkingProvider = 'openrouter';
      onModelUsed?.call('openrouter', model);
      return parsed;
    }
    return null;
  }

  Future<HttpResult?> _safePostOpenAiCompatible({
    required String hostName,
    required String path,
    required String key,
    required String model,
    required double temperature,
    required String systemPrompt,
    required bool useJsonFormat,
    Map<String, String> extraHeaders = const {},
    Duration timeout = _attemptTimeout,
    required void Function(String reason) onTimeoutOrNetwork,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content':
              'Respond strictly with a valid JSON object matching the requested schema. No extra prose.',
        },
        {'role': 'user', 'content': systemPrompt},
      ],
      'temperature': temperature,
      if (useJsonFormat) 'response_format': {'type': 'json_object'},
    };
    try {
      return await _http.postJson(
        Uri.https(hostName, path),
        body,
        headers: {
          'Authorization': 'Bearer $key',
          ...extraHeaders,
        },
        timeout: timeout,
      );
    } on TimeoutException {
      onTimeoutOrNetwork('timeout');
      _log?.warn('$hostName $model timed out');
      return null;
    } catch (e) {
      onTimeoutOrNetwork('network');
      _log?.warn('$hostName $model failed: $e');
      return null;
    }
  }

  static bool _looksLikeInvalidApiKey(String body) {
    final low = body.toLowerCase();
    return low.contains('api_key_invalid') ||
        low.contains('api key not valid') ||
        low.contains('invalid api key');
  }

  List<GeminiCandidate> _parseGeminiResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const [];
      final candidates = decoded['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) return const [];
      final content =
          (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? const [];
      final text = _extractResponseText(parts);
      return _decodeCandidatesFromText(text);
    } catch (_) {
      return const [];
    }
  }

  List<GeminiCandidate> _parseOpenAiCompatibleResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const [];
      final choices = decoded['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) return const [];
      final first = choices.first;
      if (first is! Map<String, dynamic>) return const [];
      final message = first['message'] as Map<String, dynamic>?;
      final content = message?['content'];
      final text = content is String ? content : '';
      return _decodeCandidatesFromText(text);
    } catch (_) {
      return const [];
    }
  }

  List<GeminiCandidate> _decodeCandidatesFromText(String text) {
    if (text.trim().isEmpty) return const [];
    final jsonText = _extractJsonFromText(text);
    if (jsonText.isEmpty) return const [];
    final parsed = jsonDecode(jsonText);
    final rawList = parsed is Map<String, dynamic>
        ? (parsed['recommendations'] as List<dynamic>? ?? const [])
        : (parsed is List<dynamic> ? parsed : const []);

    return rawList
        .whereType<Map<String, dynamic>>()
        .map(GeminiCandidate.fromJson)
        .where((c) => c.title.isNotEmpty)
        .toList();
  }

  static String _extractResponseText(List<dynamic> parts) {
    String? fallbackText;
    for (var i = parts.length - 1; i >= 0; i--) {
      final part = parts[i];
      if (part is! Map<String, dynamic>) continue;
      final text = part['text']?.toString() ?? '';
      if (text.trim().isEmpty) continue;
      fallbackText ??= text;
      if (part['thought'] != true) {
        return text;
      }
    }
    return fallbackText ?? '';
  }

  static String _extractJsonFromText(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('```')) {
      trimmed = trimmed.replaceFirst(RegExp(r'^```[A-Za-z0-9_-]*\s*'), '');
      trimmed = trimmed.replaceFirst(RegExp(r'\s*```$'), '').trim();
    }
    try {
      jsonDecode(trimmed);
      return trimmed;
    } catch (_) {}

    // Extract the first balanced JSON object {...} or array [...] inside surrounding prose.
    final startObj = trimmed.indexOf('{');
    final startArr = trimmed.indexOf('[');
    int start = -1;
    if (startObj >= 0 && startArr >= 0) {
      start = startObj < startArr ? startObj : startArr;
    } else {
      start = startObj >= 0 ? startObj : startArr;
    }
    if (start < 0) return '';

    final openChar = trimmed[start];
    final closeChar = openChar == '{' ? '}' : ']';
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < trimmed.length; i++) {
      final ch = trimmed[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\' && inString) {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == openChar) {
        depth++;
      } else if (ch == closeChar) {
        depth--;
        if (depth == 0) {
          final slice = trimmed.substring(start, i + 1);
          try {
            jsonDecode(slice);
            return slice;
          } catch (_) {
            return '';
          }
        }
      }
    }
    return '';
  }

  static Map<String, dynamic> buildCompactPromptPayload({
    required DiscoveryRequest request,
    required UserProfile profile,
    required List<LibraryEntry> library,
    required List<String> recentShownLabels,
  }) {
    final excludedGenreNames = profile.preferences.excludedGenres
        .map((id) => kStandardGenres.where((g) => g.id == id).firstOrNull?.en)
        .whereType<String>()
        .toList();

    final doNotRecommend = <String>[];
    for (final entry in library) {
      if (!entry.isExcludedFromRecommendations) continue;
      final label = entry.originalTitle.isNotEmpty ? entry.originalTitle : entry.title;
      doNotRecommend.add(entry.year != null ? '$label (${entry.year})' : label);
      if (doNotRecommend.length >= 80) break;
    }

    final tasteSample = <Map<String, dynamic>>[];
    if (!request.guestMode && profile.preferences.personalized) {
      final rated = library.where((e) => !e.isDeleted && (e.userRating ?? 0) > 0).toList()
        ..sort((a, b) => (b.userRating ?? 0).compareTo(a.userRating ?? 0));
      final selected = <LibraryEntry>[];
      final seenKeys = <String>{};

      for (final e in rated.take(25)) {
        if (seenKeys.add(e.keyString)) selected.add(e);
      }
      for (final e in rated.reversed) {
        if (selected.length >= 40) break;
        if (seenKeys.add(e.keyString)) selected.add(e);
      }
      for (final e in library) {
        if (selected.length >= 45) break;
        if (!e.isDeleted && e.sentiment != Sentiment.neutral && seenKeys.add(e.keyString)) {
          selected.add(e);
        }
      }

      for (final e in selected) {
        tasteSample.add({
          'title': e.originalTitle.isNotEmpty ? e.originalTitle : e.title,
          'year': e.year,
          'mediaType': e.mediaType.wireValue,
          'ratingOutOf10': e.userRating ?? 0,
          'liked': e.sentiment == Sentiment.liked,
          'disliked': e.sentiment == Sentiment.disliked,
        });
      }
    }

    final effectiveMaxMinutes = request.maxMinutes ??
        (request.preset == EveningPreset.under90 ? 90 : 0);

    return {
      'userQuery': request.prompt.trim(),
      'preset': request.preset?.id ?? '',
      'mediaType': request.mediaTypeFilter?.wireValue ?? 'all',
      'maxMinutes': effectiveMaxMinutes,
      'guestMode': request.guestMode,
      'different': request.different,
      'excludedGenres': excludedGenreNames,
      if (tasteSample.isNotEmpty) 'preferences': tasteSample,
      if (doNotRecommend.isNotEmpty) 'doNotRecommend': doNotRecommend,
      if (recentShownLabels.isNotEmpty)
        'recentShown': recentShownLabels.take(36).toList(),
    };
  }

  String _buildPromptText({
    required String contentLanguage,
    required DiscoveryRequest request,
    required Map<String, dynamic> compactPayload,
  }) {
    final langName = switch (contentLanguage) {
      'ru' => 'Russian',
      'en' => 'English',
      _ => 'Ukrainian',
    };
    final maxMinutes = (compactPayload['maxMinutes'] as num?)?.toInt() ?? 0;
    final runtimeRule = maxMinutes > 0
        ? '\n- Strictly recommend ONLY titles with runtime <= $maxMinutes minutes (exclude 2-hour+ films).'
        : '';
    return '''
Recommend 12 real, existing movies or TV series matching the JSON context below.
Rules:
- Never invent fictional titles. Provide accurate original_title and release year.
- If userQuery names a specific movie, series, franchise, or phonetic/transliterated title (e.g. "стрит файтер" -> "Street Fighter"), put the exact matching titles from that franchise FIRST, followed by similar titles.
- Never include anything from doNotRecommend, recentShown, or excludedGenres.$runtimeRule
- Write title, genre, and a short spoiler-free reason (max 140 chars) in $langName.
- If guestMode is true, ignore narrow personal preferences and focus on broad crowd-pleasing picks matching the request/preset.
- Return ONLY JSON: {"recommendations":[{"title":"...","original_title":"...","year":2020,"media_type":"movie","genre":"...","reason":"..."}]}.
Context JSON:
${jsonEncode(compactPayload)}
''';
  }

  static const Map<String, dynamic> _responseSchema = {
    'type': 'OBJECT',
    'properties': {
      'recommendations': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'title': {'type': 'STRING'},
            'original_title': {'type': 'STRING'},
            'year': {'type': 'INTEGER'},
            'media_type': {
              'type': 'STRING',
              'enum': ['movie', 'tv'],
            },
            'genre': {'type': 'STRING'},
            'reason': {'type': 'STRING'},
          },
          'required': ['title', 'original_title', 'year', 'media_type', 'genre', 'reason'],
        },
      },
    },
    'required': ['recommendations'],
  };

  static Map<String, dynamic>? _thinkingConfigForModel(String model) {
    final low = model.toLowerCase();
    if (low.endsWith('-latest') || low.startsWith('gemma')) {
      return null;
    }
    if (low.startsWith('gemini-3.5-flash-lite') ||
        low.startsWith('gemini-3.1-flash-lite') ||
        low.startsWith('gemini-3.6-flash') ||
        low.startsWith('gemini-3-flash')) {
      return const {'thinkingLevel': 'minimal'};
    }
    if (low.startsWith('gemini-4-') ||
        low.startsWith('gemini-3.8') ||
        low.startsWith('gemini-3.1-pro')) {
      return const {'thinkingLevel': 'low'};
    }
    if (low.contains('2.5') && low.contains('flash')) {
      return const {'thinkingBudget': 0};
    }
    return null;
  }

  Future<HttpResult> _postGenerate({
    required String key,
    required String model,
    required double temperature,
    required String systemPrompt,
    bool simplified = false,
    Duration timeout = _attemptTimeout,
  }) {
    final thinkingConfig = simplified ? null : _thinkingConfigForModel(model);
    final generationConfig = <String, dynamic>{
      'temperature': temperature,
      if (!simplified) 'responseMimeType': 'application/json',
      if (!simplified) 'responseSchema': _responseSchema,
      'thinkingConfig': ?thinkingConfig,
    };

    final body = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': systemPrompt},
          ],
        },
      ],
      'generationConfig': generationConfig,
    };
    final uri = Uri.https(host, '/v1beta/models/$model:generateContent', {'key': key});
    return _http.postJson(uri, body, timeout: timeout);
  }
}
