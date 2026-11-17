import 'dart:convert';

import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../../core/network/starfilm_http_client.dart';
import 'discovery_models.dart';

class GeminiQuotaException implements Exception {
  GeminiQuotaException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'GeminiQuotaException($statusCode): $message';
}

class GeminiClient {
  GeminiClient(this._http);

  final StarFilmHttpClient _http;

  static const String host = 'generativelanguage.googleapis.com';
  static const String fallbackModel = 'gemini-2.5-flash-lite';
  static const List<String> defaultModels = [
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-flash-lite-latest',
    'gemini-2.5-pro',
  ];
  static const Set<String> _retiredOrInvalidModels = {
    'gemini-3.5-flash-lite',
    'gemini-3.6-flash',
    'gemini-3.8-flash',
    'gemini-3.5-pro',
  };

  /// Maps retired or unavailable 3.x placeholder IDs to the active default model.
  static String normalizeModel(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty || _retiredOrInvalidModels.contains(trimmed)) {
      return fallbackModel;
    }
    return trimmed;
  }

  Future<bool> verifyKey(String apiKey, {String model = fallbackModel}) async {
    final key = apiKey.trim();
    if (key.isEmpty) return false;
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

  /// Executes Gemini request with fallback across stable models on 404 / 429 / 5xx.
  Future<List<GeminiCandidate>> generateCandidates({
    required String apiKey,
    required String model,
    required DiscoveryRequest request,
    required UserProfile profile,
    required List<LibraryEntry> library,
    required List<String> recentShownLabels,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
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

    final modelsToTry = <String>{
      normalizeModel(model),
      'gemini-2.5-flash-lite',
      'gemini-2.5-flash',
      'gemini-flash-lite-latest',
    }.toList();

    HttpResult? okResult;
    var lastStatus = 0;
    for (final candidateModel in modelsToTry) {
      final res = await _postGenerate(
        key: key,
        model: candidateModel,
        temperature: request.different ? 0.95 : 0.7,
        systemPrompt: systemPrompt,
      );
      if (res.isOk) {
        okResult = res;
        break;
      }
      lastStatus = res.statusCode;
      if (res.statusCode == 404 || res.statusCode == 429 || res.statusCode >= 500) {
        continue;
      }
      throw GeminiQuotaException(res.statusCode, 'HTTP ${res.statusCode}');
    }

    if (okResult == null) {
      throw GeminiQuotaException(lastStatus, 'HTTP $lastStatus');
    }

    final decoded = jsonDecode(okResult.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final candidates = decoded['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) return const [];
    final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? const [];
    final text = _extractResponseText(parts);
    if (text.trim().isEmpty) return const [];

    final cleanedText = _stripMarkdownCodeFence(text);
    final parsed = jsonDecode(cleanedText);
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

  static String _stripMarkdownCodeFence(String raw) {
    var trimmed = raw.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    trimmed = trimmed.replaceFirst(RegExp(r'^```[A-Za-z0-9_-]*\s*'), '');
    trimmed = trimmed.replaceFirst(RegExp(r'\s*```$'), '');
    return trimmed.trim();
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

  Future<HttpResult> _postGenerate({
    required String key,
    required String model,
    required double temperature,
    required String systemPrompt,
  }) {
    final body = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': systemPrompt},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': _responseSchema,
        'temperature': temperature,
        if (model.contains('gemini-3'))
          'thinkingConfig': {'thinkingLevel': 'MINIMAL'}
        else if (model.contains('2.5') && model.contains('flash'))
          'thinkingConfig': {'thinkingBudget': 0},
      },
    };
    final uri = Uri.https(host, '/v1beta/models/$model:generateContent', {'key': key});
    return _http.postJson(uri, body, timeout: const Duration(seconds: 25));
  }
}
