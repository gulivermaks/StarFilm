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
  static const String fallbackModel = 'gemini-3.5-flash-lite';
  static const List<String> defaultModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
  ];

  Future<bool> verifyKey(String apiKey, {String model = fallbackModel}) async {
    final key = apiKey.trim();
    if (key.isEmpty) return false;
    final uri = Uri.https(host, '/v1beta/models/$model', {'key': key});
    final res = await _http.get(uri);
    if (res.isOk) return true;
    if (res.statusCode == 404) {
      final listUri = Uri.https(host, '/v1beta/models', {'pageSize': '1', 'key': key});
      final listRes = await _http.get(listUri);
      return listRes.isOk;
    }
    return false;
  }

  /// Executes at most ONE Gemini call per user request (with single fallback to current default model
  /// only on 404/model unavailability, never cascading double recommendations).
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

    var res = await _postGenerate(
      key: key,
      model: model,
      temperature: request.different ? 0.95 : 0.7,
      systemPrompt: systemPrompt,
    );
    if (res.statusCode == 404 && model != fallbackModel) {
      res = await _postGenerate(
        key: key,
        model: fallbackModel,
        temperature: request.different ? 0.95 : 0.7,
        systemPrompt: systemPrompt,
      );
    }
    if (res.statusCode == 429 || !res.isOk) {
      throw GeminiQuotaException(res.statusCode, 'HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final candidates = decoded['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) return const [];
    final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? const [];
    if (parts.isEmpty) return const [];
    final text = (parts.first as Map<String, dynamic>)['text']?.toString() ?? '';
    if (text.trim().isEmpty) return const [];

    final parsed = jsonDecode(text);
    final rawList = parsed is Map<String, dynamic>
        ? (parsed['recommendations'] as List<dynamic>? ?? const [])
        : (parsed is List<dynamic> ? parsed : const []);

    return rawList
        .whereType<Map<String, dynamic>>()
        .map(GeminiCandidate.fromJson)
        .where((c) => c.title.isNotEmpty)
        .toList();
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

    return {
      'userQuery': request.prompt.trim(),
      'preset': request.preset?.id ?? '',
      'mediaType': request.mediaTypeFilter?.wireValue ?? 'all',
      'maxMinutes': request.maxMinutes ?? 0,
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
    return '''
Recommend 12 real, existing movies or TV series matching the JSON context below.
Rules:
- Never invent fictional titles. Provide accurate original_title and release year.
- Never include anything from doNotRecommend, recentShown, or excludedGenres.
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
