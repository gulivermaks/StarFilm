import 'dart:convert';

import '../../core/network/starfilm_http_client.dart';
import '../../core/security/log_sanitizer.dart';
import '../search/tmdb_matcher.dart';

class ExternalRatings {
  const ExternalRatings({
    this.kinopoiskRating,
    this.imdbRating,
  });

  final double? kinopoiskRating;
  final double? imdbRating;

  bool get hasAny =>
      (kinopoiskRating != null && kinopoiskRating! > 0) ||
      (imdbRating != null && imdbRating! > 0);
}

/// Fetches Kinopoisk and IMDb ratings via kinopoiskapiunofficial.tech using the
/// user's personal Kinopoisk API key, matching StarTV's AiRecommender behavior.
class KinopoiskClient {
  KinopoiskClient(this._http, {DiagnosticsLog? log}) : _log = log;

  final StarFilmHttpClient _http;
  final DiagnosticsLog? _log;
  final Map<String, ExternalRatings> _cache = <String, ExternalRatings>{};

  static final RegExp _keyFormat = RegExp(r'^[A-Za-z0-9._-]{8,128}$');

  static bool isValidKeyFormat(String rawKey) =>
      _keyFormat.hasMatch(rawKey.trim());

  Future<bool> verifyKey(String rawKey) async {
    final clean = rawKey.trim();
    if (!isValidKeyFormat(clean)) return false;
    final res = await _http.get(
      Uri.https('kinopoiskapiunofficial.tech', '/api/v2.2/films/301'),
      headers: {'X-API-KEY': clean},
      timeout: const Duration(seconds: 6),
    );
    // 200 OK or 402 daily quota reached both confirm the API key itself is valid.
    return res.statusCode == 200 || res.statusCode == 402;
  }

  Future<ExternalRatings?> fetchRatings({
    required String apiKey,
    String? imdbId,
    required String title,
    int? year,
  }) async {
    final cleanKey = apiKey.trim();
    if (!isValidKeyFormat(cleanKey)) return null;

    final cleanImdb = imdbId?.trim() ?? '';
    final cleanTitle = title.trim();
    final cacheKey = cleanImdb.isNotEmpty
        ? cleanImdb
        : '${cleanTitle.toLowerCase()}:${year ?? ''}';
    if (cacheKey.isEmpty || cacheKey == ':') return null;

    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final headers = {'X-API-KEY': cleanKey};

    try {
      if (cleanImdb.isNotEmpty) {
        final uri = Uri.https(
          'kinopoiskapiunofficial.tech',
          '/api/v2.2/films',
          {'imdbId': cleanImdb},
        );
        final res = await _http.get(uri, headers: headers, timeout: const Duration(seconds: 6));
        if (res.isOk) {
          final parsed = _parseImdbLookup(res.body);
          if (parsed != null && parsed.hasAny) {
            _cache[cacheKey] = parsed;
            return parsed;
          }
        }
      }

      if (cleanTitle.isNotEmpty) {
        final uri = Uri.https(
          'kinopoiskapiunofficial.tech',
          '/api/v2.1/films/search-by-keyword',
          {'keyword': cleanTitle},
        );
        final res = await _http.get(uri, headers: headers, timeout: const Duration(seconds: 6));
        if (res.isOk) {
          final parsed = _parseKeywordSearch(res.body, year: year);
          if (parsed != null && parsed.hasAny) {
            _cache[cacheKey] = parsed;
            return parsed;
          }
        }
      }
    } catch (e) {
      _log?.warn('Kinopoisk lookup failed: $e');
    }
    return null;
  }

  ExternalRatings? _parseImdbLookup(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final items = decoded['items'];
    if (items is! List || items.isEmpty) return null;
    final first = items.first;
    if (first is! Map<String, dynamic>) return null;

    final kp = _validRating(first['ratingKinopoisk']);
    final imdb = _validRating(first['ratingImdb']);
    if (kp == null && imdb == null) return null;
    return ExternalRatings(kinopoiskRating: kp, imdbRating: imdb);
  }

  ExternalRatings? _parseKeywordSearch(String body, {int? year}) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final films = decoded['films'];
    if (films is! List || films.isEmpty) return null;

    for (final raw in films.take(5)) {
      if (raw is! Map<String, dynamic>) continue;
      final candidateYear = int.tryParse((raw['year'] ?? '').toString());
      if (!TmdbMatcher.yearsCompatible(year, candidateYear)) continue;
      final kp = _validRating(raw['rating']);
      if (kp != null) {
        return ExternalRatings(kinopoiskRating: kp);
      }
    }
    return null;
  }

  double? _validRating(Object? raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty || str.toLowerCase() == 'null' || str.endsWith('%')) {
      return null;
    }
    final numVal = raw is num ? raw.toDouble() : double.tryParse(str);
    if (numVal == null || numVal <= 0 || numVal > 10) return null;
    return numVal;
  }
}
