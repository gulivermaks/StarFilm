import 'dart:async';
import 'dart:convert';

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
}

class GeminiClient {
  GeminiClient(this._http, {DiagnosticsLog? log}) : _log = log;

  final StarFilmHttpClient _http;
  final DiagnosticsLog? _log;

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

  static const Duration _cooldownDuration = Duration(seconds: 90);
  static const Duration _discoveryCacheTtl = Duration(minutes: 30);

  final Map<String, Set<String>> _notFoundModelsByKey = {};
  final Map<String, Map<String, DateTime>> _cooldownUntilByKey = {};
  final Map<String, _DiscoveredModelCache> _discoveredModelsByKey = {};
  final Map<String, String> _lastWorkingModelByKey = {};

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

  Future<List<GeminiCandidate>?> _tryGeminiKey({
    required String key,
    required String preferredModel,
    required double temperature,
    required String systemPrompt,
    required void Function(int status, String reason) onStatus,
    void Function(String provider, String model)? onModelUsed,
  }) async {
    final now = DateTime.now();
    final notFound = _notFoundModelsByKey[key] ?? <String>{};
    final cooldowns = _cooldownUntilByKey[key] ?? <String, DateTime>{};
    cooldowns.removeWhere((_, until) => !until.isAfter(now));

    final normalizedPreferred = normalizeModel(preferredModel);
    final lastWorking = _lastWorkingModelByKey[key];

    final ordered = <String>[];
    final delayedCooldown = <String>[];
    final seenModels = <String>{};

    void addCandidate(String m) {
      if (m.isEmpty || notFound.contains(m) || !seenModels.add(m)) return;
      final until = cooldowns[m];
      if (until != null && until.isAfter(now)) {
        delayedCooldown.add(m);
      } else {
        ordered.add(m);
      }
    }

    final preferredUnavailable = notFound.contains(normalizedPreferred) ||
        (cooldowns[normalizedPreferred]?.isAfter(now) ?? false);
    if (!preferredUnavailable) {
      addCandidate(normalizedPreferred);
    }
    if (lastWorking != null && lastWorking.isNotEmpty) {
      addCandidate(lastWorking);
    }
    addCandidate(normalizedPreferred);
    for (final m in defaultModels) {
      addCandidate(m);
    }
    ordered.addAll(delayedCooldown);

    var abortedKey = false;
    final attempted = <String>{};

    Future<({List<GeminiCandidate>? candidates, _AttemptOutcome outcome})>
        attemptModel(String candidateModel) async {
      attempted.add(candidateModel);
      final isGemma = candidateModel.toLowerCase().startsWith('gemma');
      var res = await _safePostGemini(
        key: key,
        model: candidateModel,
        temperature: temperature,
        systemPrompt: systemPrompt,
        simplified: isGemma,
        onTimeoutOrNetwork: (reason) => onStatus(0, reason),
      );
      if (res == null) {
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
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
          _log?.warn('Gemini $candidateModel HTTP 400, retrying simplified config');
          res = await _safePostGemini(
            key: key,
            model: candidateModel,
            temperature: temperature,
            systemPrompt: systemPrompt,
            simplified: true,
            onTimeoutOrNetwork: (reason) => onStatus(0, reason),
          );
          if (res == null) {
            return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
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
          (_notFoundModelsByKey[key] ??= <String>{}).add(candidateModel);
        } else if (res.statusCode == 429) {
          (_cooldownUntilByKey[key] ??= <String, DateTime>{})[candidateModel] =
              DateTime.now().add(_cooldownDuration);
        }
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }

      final parsed = _parseGeminiResponse(res.body);
      if (parsed.isEmpty) {
        onStatus(200, 'empty');
        _log?.warn('Gemini $candidateModel returned empty or unparseable JSON');
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }

      _lastWorkingModelByKey[key] = candidateModel;
      onModelUsed?.call('gemini', candidateModel);
      return (candidates: parsed, outcome: _AttemptOutcome.succeeded);
    }

    for (final candidateModel in ordered) {
      final res = await attemptModel(candidateModel);
      if (res.outcome == _AttemptOutcome.succeeded) return res.candidates;
      if (res.outcome == _AttemptOutcome.abortKey) {
        abortedKey = true;
        break;
      }
    }

    if (!abortedKey) {
      final discovered = await _discoverGeminiModels(key);
      var extraTries = 0;
      for (final candidateModel in discovered) {
        if (extraTries >= 4) break;
        if (attempted.contains(candidateModel) ||
            notFound.contains(candidateModel)) {
          continue;
        }
        extraTries++;
        final res = await attemptModel(candidateModel);
        if (res.outcome == _AttemptOutcome.succeeded) return res.candidates;
        if (res.outcome == _AttemptOutcome.abortKey) break;
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
    required void Function(String reason) onTimeoutOrNetwork,
  }) async {
    try {
      return await _postGenerate(
        key: key,
        model: model,
        temperature: temperature,
        systemPrompt: systemPrompt,
        simplified: simplified,
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

  Future<List<String>> _discoverGeminiModels(String key) async {
    final now = DateTime.now();
    final cached = _discoveredModelsByKey[key];
    if (cached != null && now.difference(cached.fetchedAt) < _discoveryCacheTtl) {
      return cached.models;
    }

    try {
      final uri = Uri.https(host, '/v1beta/models', {'pageSize': '100', 'key': key});
      final res = await _http.get(uri, timeout: const Duration(seconds: 10));
      if (!res.isOk) {
        _log?.warn('Gemini models.list HTTP ${res.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final rawModels = decoded['models'] as List<dynamic>? ?? const [];
      final usable = <String>[];
      const blockedSubstrings = [
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
      ];
      for (final item in rawModels) {
        if (item is! Map<String, dynamic>) continue;
        final methods = (item['supportedGenerationMethods'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        if (!methods.contains('generateContent')) continue;
        var name = (item['name'] ?? '').toString().trim();
        if (name.startsWith('models/')) {
          name = name.substring(7);
        }
        final low = name.toLowerCase();
        if (!(low.contains('gemini') || low.contains('gemma'))) continue;
        if (blockedSubstrings.any(low.contains)) continue;
        usable.add(name);
      }

      usable.sort((a, b) {
        int rank(String m) {
          final l = m.toLowerCase();
          if (l.contains('flash-lite')) return 0;
          if (l.contains('flash')) return 1;
          if (l.startsWith('gemini-')) return 2;
          return 3;
        }

        return rank(a).compareTo(rank(b));
      });

      _discoveredModelsByKey[key] = _DiscoveredModelCache(
        models: usable,
        fetchedAt: now,
      );
      return usable;
    } catch (e) {
      _log?.warn('Gemini models.list failed: $e');
      return const [];
    }
  }

  Future<List<GeminiCandidate>?> _tryGroqKey({
    required String key,
    required double temperature,
    required String systemPrompt,
    required void Function(int status, String reason) onStatus,
    void Function(String provider, String model)? onModelUsed,
  }) async {
    final attempted = <String>{};
    var abortedKey = false;

    Future<({List<GeminiCandidate>? candidates, _AttemptOutcome outcome})>
        attemptGroqModel(String model) async {
      attempted.add(model);
      var res = await _safePostOpenAiCompatible(
        hostName: groqHost,
        path: '/openai/v1/chat/completions',
        key: key,
        model: model,
        temperature: temperature,
        systemPrompt: systemPrompt,
        useJsonFormat: true,
        onTimeoutOrNetwork: (reason) => onStatus(0, reason),
      );
      if (res == null) {
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }
      if (!res.isOk && res.statusCode == 400) {
        res = await _safePostOpenAiCompatible(
          hostName: groqHost,
          path: '/openai/v1/chat/completions',
          key: key,
          model: model,
          temperature: temperature,
          systemPrompt: systemPrompt,
          useJsonFormat: false,
          onTimeoutOrNetwork: (reason) => onStatus(0, reason),
        );
        if (res == null) {
          return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
        }
      }
      if (!res.isOk) {
        onStatus(res.statusCode, 'HTTP ${res.statusCode}');
        _log?.warn('Groq $model HTTP ${res.statusCode}');
        if (res.statusCode == 401) {
          return (candidates: null, outcome: _AttemptOutcome.abortKey);
        }
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }

      final parsed = _parseOpenAiCompatibleResponse(res.body);
      if (parsed.isEmpty) {
        onStatus(200, 'empty');
        _log?.warn('Groq $model returned empty or unparseable JSON');
        return (candidates: null, outcome: _AttemptOutcome.tryNextModel);
      }
      onModelUsed?.call('groq', model);
      return (candidates: parsed, outcome: _AttemptOutcome.succeeded);
    }

    for (final m in groqFreeModels) {
      final res = await attemptGroqModel(m);
      if (res.outcome == _AttemptOutcome.succeeded) return res.candidates;
      if (res.outcome == _AttemptOutcome.abortKey) {
        abortedKey = true;
        break;
      }
    }

    if (!abortedKey) {
      final discovered = await _discoverGroqModels(key);
      var extraTries = 0;
      for (final m in discovered) {
        if (extraTries >= 4) break;
        if (attempted.contains(m)) continue;
        extraTries++;
        final res = await attemptGroqModel(m);
        if (res.outcome == _AttemptOutcome.succeeded) return res.candidates;
        if (res.outcome == _AttemptOutcome.abortKey) break;
      }
    }
    return null;
  }

  Future<List<String>> _discoverGroqModels(String key) async {
    try {
      final res = await _http.get(
        Uri.https(groqHost, '/openai/v1/models'),
        headers: {'Authorization': 'Bearer $key'},
        timeout: const Duration(seconds: 10),
      );
      if (!res.isOk) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final list = decoded['data'] as List<dynamic>? ?? const [];
      const blocked = ['whisper', 'guard', 'tts', 'safeguard'];
      final out = <String>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final id = (item['id'] ?? '').toString().trim();
        final low = id.toLowerCase();
        if (id.isEmpty || blocked.any(low.contains)) continue;
        out.add(id);
      }
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

    for (final model in openRouterFreeModels) {
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
        onTimeoutOrNetwork: (reason) => onStatus(0, reason),
      );
      if (res == null) continue;

      if (!res.isOk && res.statusCode == 400 && !isGemma) {
        res = await _safePostOpenAiCompatible(
          hostName: openRouterHost,
          path: '/api/v1/chat/completions',
          key: key,
          model: model,
          temperature: temperature,
          systemPrompt: systemPrompt,
          useJsonFormat: false,
          extraHeaders: extraHeaders,
          onTimeoutOrNetwork: (reason) => onStatus(0, reason),
        );
        if (res == null) continue;
      }

      if (!res.isOk) {
        onStatus(res.statusCode, 'HTTP ${res.statusCode}');
        _log?.warn('OpenRouter $model HTTP ${res.statusCode}');
        if (res.statusCode == 401) break;
        continue;
      }

      final parsed = _parseOpenAiCompatibleResponse(res.body);
      if (parsed.isEmpty) {
        onStatus(200, 'empty');
        _log?.warn('OpenRouter $model returned empty or unparseable JSON');
        continue;
      }
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
        timeout: const Duration(seconds: 25),
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
    return _http.postJson(uri, body, timeout: const Duration(seconds: 25));
  }
}
