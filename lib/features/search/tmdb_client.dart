import 'dart:convert';

import '../../core/models/media_key.dart';
import '../../core/network/starfilm_http_client.dart';
import '../../core/security/log_sanitizer.dart';
import '../ratings/kinopoisk_client.dart';
import 'tmdb_matcher.dart';

class TmdbHttpException implements Exception {
  TmdbHttpException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'TmdbHttpException($statusCode): $message';
}

class MediaDetails {
  const MediaDetails({
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.genreIds,
    required this.genres,
    required this.countries,
    required this.directorsOrCreators,
    required this.cast,
    required this.tmdbRating,
    this.runtimeMinutes,
    this.numberOfSeasons,
    this.imdbId,
    this.youtubeTrailerKey,
  });

  final MediaType mediaType;
  final int tmdbId;
  final String title;
  final String originalTitle;
  final int? year;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final List<int> genreIds;
  final List<String> genres;
  final List<String> countries;
  final List<String> directorsOrCreators;
  final List<String> cast;
  final double? tmdbRating;
  final int? runtimeMinutes;
  final int? numberOfSeasons; // Reference info from TMDB only; no episode tracking
  final String? imdbId;
  final String? youtubeTrailerKey;
}

class TmdbClient {
  TmdbClient(this._http, {DiagnosticsLog? log}) : _log = log;

  final StarFilmHttpClient _http;
  final DiagnosticsLog? _log;

  static const String apiHost = 'api.tmdb.org';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/';

  static String _normalizeToken(String raw) {
    var t = raw.trim();
    if (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }
    return t;
  }

  static bool _isBearerToken(String raw) {
    final k = _normalizeToken(raw);
    return k.startsWith('eyJ') || k.length > 48;
  }

  Future<HttpResult> _get(
    String rawKey,
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final token = _normalizeToken(rawKey);
    final useBearer = _isBearerToken(token);
    final params = <String, String>{
      if (!useBearer) 'api_key': token,
      ...query,
    };
    final headers = useBearer
        ? <String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          }
        : null;
    final uri = Uri.https(apiHost, path, params);
    final res = await _http.get(uri, headers: headers);
    if (!res.isOk) {
      _log?.warn('TMDB $path HTTP ${res.statusCode}');
    }
    return res;
  }

  static String posterUrl(String path, {String size = 'w342'}) {
    if (path.isEmpty) return '';
    return '$imageBaseUrl$size$path';
  }

  static String toTmdbLocale(String contentLang) {
    switch (contentLang.toLowerCase()) {
      case 'ru':
        return 'ru-RU';
      case 'en':
        return 'en-US';
      default:
        return 'uk-UA';
    }
  }

  Future<bool> verifyKey(String apiKey) async {
    final trimmed = _normalizeToken(apiKey);
    if (trimmed.isEmpty) return false;
    final res = await _get(trimmed, '/3/configuration');
    return res.isOk;
  }

  Future<List<TmdbSearchCandidate>> searchMulti({
    required String apiKey,
    required String query,
    String contentLanguage = 'uk',
    int? yearHint,
  }) async {
    final q = TmdbMatcher.cleanSearchQuery(query);
    if (q.isEmpty || _normalizeToken(apiKey).isEmpty) return const [];
    final locale = toTmdbLocale(contentLanguage);
    final merged = <String, TmdbSearchCandidate>{};

    final primary = await _runSearchMulti(
      apiKey: apiKey,
      query: q,
      locale: locale,
      yearHint: yearHint,
    );
    _mergeCandidates(merged, primary, preservePrimaryTitle: true);

    final phonetic = TmdbMatcher.phoneticLatinQuery(q);
    final hasPhonetic =
        phonetic.isNotEmpty && phonetic.toLowerCase() != q.toLowerCase();
    final hasExact = merged.values.any(
      (c) => TmdbMatcher.isExactTitleMatch(
        query: q,
        item: c,
        phoneticQuery: hasPhonetic ? phonetic : null,
      ),
    );
    if (!hasExact && hasPhonetic) {
      final phoneticHits = await _runSearchMulti(
        apiKey: apiKey,
        query: phonetic,
        locale: locale,
        yearHint: yearHint,
      );
      _mergeCandidates(merged, phoneticHits, preservePrimaryTitle: false);
    }

    return TmdbMatcher.rankSearchResults(
      query: q,
      phoneticQuery: hasPhonetic ? phonetic : null,
      yearHint: yearHint,
      results: merged.values.toList(),
    );
  }

  /// Thorough catalog search combining `/search/movie`, `/search/tv`, cross-locale,
  /// phonetic transliteration, page 2 fallback, optional Kinopoisk title hints,
  /// and exact-first local ranking.
  Future<List<TmdbSearchCandidate>> searchCatalog({
    required String apiKey,
    required String query,
    String contentLanguage = 'uk',
    MediaType? mediaTypeFilter,
    int? yearHint,
    KinopoiskClient? kinopoisk,
    String kinopoiskApiKey = '',
  }) async {
    final q = TmdbMatcher.cleanSearchQuery(query);
    if (q.isEmpty || _normalizeToken(apiKey).isEmpty) return const [];

    final primaryLocale = toTmdbLocale(contentLanguage);
    final phonetic = TmdbMatcher.phoneticLatinQuery(q);
    final hasPhonetic =
        phonetic.isNotEmpty && phonetic.toLowerCase() != q.toLowerCase();
    final types = mediaTypeFilter != null
        ? [mediaTypeFilter]
        : const [MediaType.movie, MediaType.tv];

    final merged = <String, TmdbSearchCandidate>{};
    var maxTotalPages = 1;
    Object? firstError;
    var anySuccess = false;

    final primaryPages = await Future.wait(
      types.map((type) async {
        try {
          final page = await _runSearchTypedPage(
            apiKey: apiKey,
            mediaType: type,
            query: q,
            locale: primaryLocale,
            throwOnError: true,
          );
          anySuccess = true;
          return page;
        } catch (e) {
          firstError ??= e;
          return const _SearchPageResult(items: [], totalPages: 1);
        }
      }),
    );

    final isOnly404 =
        firstError is TmdbHttpException && (firstError as TmdbHttpException).statusCode == 404;
    if (!anySuccess && firstError != null && !isOnly404) {
      throw firstError!;
    }

    for (final page in primaryPages) {
      if (page.totalPages > maxTotalPages) maxTotalPages = page.totalPages;
      _mergeCandidates(merged, page.items, preservePrimaryTitle: true);
    }

    // Compatibility fallback if only /3/search/multi responded (e.g. mocks).
    if (merged.isEmpty) {
      try {
        final multiHits = await _runSearchMulti(
          apiKey: apiKey,
          query: q,
          locale: primaryLocale,
        );
        final filteredMulti = mediaTypeFilter != null
            ? multiHits.where((e) => e.mediaType == mediaTypeFilter).toList()
            : multiHits;
        _mergeCandidates(merged, filteredMulti, preservePrimaryTitle: true);
      } catch (e) {
        if (!anySuccess && firstError != null) {
          throw firstError!;
        }
        if (!anySuccess) rethrow;
      }
    }

    bool hasExactMatch() => merged.values.any(
          (c) => TmdbMatcher.isExactTitleMatch(
            query: q,
            item: c,
            phoneticQuery: hasPhonetic ? phonetic : null,
          ),
        );

    Future<void> searchAndMerge({
      required String qText,
      required String locale,
      int page = 1,
      String? extraAlias,
    }) async {
      final hits = await Future.wait(
        types.map(
          (t) => _runSearchTypedPage(
            apiKey: apiKey,
            mediaType: t,
            query: qText,
            locale: locale,
            page: page,
          ),
        ),
      );
      var addedAny = false;
      for (final h in hits) {
        if (h.items.isNotEmpty) {
          addedAny = true;
          final prepared = extraAlias != null && extraAlias.isNotEmpty
              ? h.items
                  .map(
                    (c) => c.copyWith(
                      matchedAliases: [...c.matchedAliases, extraAlias],
                    ),
                  )
                  .toList()
              : h.items;
          _mergeCandidates(
            merged,
            prepared,
            preservePrimaryTitle: true,
          );
        }
      }
      if (!addedAny && page == 1) {
        try {
          final multi = await _runSearchMulti(
            apiKey: apiKey,
            query: qText,
            locale: locale,
          );
          final filtered = mediaTypeFilter != null
              ? multi.where((e) => e.mediaType == mediaTypeFilter).toList()
              : multi;
          final prepared = extraAlias != null && extraAlias.isNotEmpty
              ? filtered
                  .map(
                    (c) => c.copyWith(
                      matchedAliases: [...c.matchedAliases, extraAlias],
                    ),
                  )
                  .toList()
              : filtered;
          _mergeCandidates(
            merged,
            prepared,
            preservePrimaryTitle: true,
          );
        } catch (_) {}
      }
    }

    final script = TmdbMatcher.detectQueryScript(q);
    if (!hasExactMatch()) {
      final extraLocales = <String>[];
      if ((script == 'ru' || script == 'cyrillic') && contentLanguage != 'ru') {
        extraLocales.add('ru-RU');
      }
      if (script == 'uk' && contentLanguage != 'uk') {
        extraLocales.add('uk-UA');
      }
      if (script == 'latin' && contentLanguage != 'en') {
        extraLocales.add('en-US');
      }

      for (final loc in extraLocales) {
        if (hasExactMatch()) break;
        await searchAndMerge(qText: q, locale: loc);
      }
    }

    if (!hasExactMatch() && hasPhonetic) {
      await searchAndMerge(qText: phonetic, locale: primaryLocale);
      if (!hasExactMatch() && contentLanguage != 'en') {
        await searchAndMerge(
          qText: phonetic,
          locale: 'en-US',
        );
      }
    }

    if (!hasExactMatch() && maxTotalPages > 1) {
      await searchAndMerge(qText: q, locale: primaryLocale, page: 2);
    }

    if (!hasExactMatch() &&
        kinopoisk != null &&
        kinopoiskApiKey.trim().isNotEmpty &&
        script != 'latin') {
      final hints = await kinopoisk.searchTitleHints(
        apiKey: kinopoiskApiKey,
        keyword: q,
      );
      final normalizedQ = TmdbMatcher.normalizeTitle(q);
      final exactHint = hints.where((h) {
        final ruMatch = TmdbMatcher.normalizeTitle(h.nameRu) == normalizedQ;
        return ruMatch && h.nameEn.isNotEmpty;
      }).firstOrNull ??
          hints.where((h) => h.nameEn.isNotEmpty).firstOrNull;
      if (exactHint != null) {
        await searchAndMerge(
          qText: exactHint.nameEn,
          locale: primaryLocale,
          extraAlias: exactHint.nameRu,
        );
        if (!hasExactMatch() && contentLanguage != 'en') {
          await searchAndMerge(
            qText: exactHint.nameEn,
            locale: 'en-US',
            extraAlias: exactHint.nameRu,
          );
        }
      }
    }

    var results = merged.values.toList();
    if (yearHint != null) {
      final yearMatched =
          results.where((c) => TmdbMatcher.yearsCompatible(yearHint, c.year)).toList();
      if (yearMatched.isNotEmpty) {
        results = yearMatched;
      }
    }

    return TmdbMatcher.rankSearchResults(
      query: q,
      phoneticQuery: hasPhonetic ? phonetic : null,
      yearHint: yearHint,
      preferredType: mediaTypeFilter,
      results: results,
    );
  }

  /// Fetches similar / recommended TMDB items for a resolved title.
  Future<List<TmdbSearchCandidate>> fetchRecommendations({
    required String apiKey,
    required MediaType mediaType,
    required int tmdbId,
    String contentLanguage = 'uk',
  }) async {
    final key = _normalizeToken(apiKey);
    if (key.isEmpty || tmdbId <= 0) return const [];
    try {
      final res = await _get(
        key,
        '/3/${mediaType.wireValue}/$tmdbId/recommendations',
        {'language': toTmdbLocale(contentLanguage), 'page': '1'},
      );
      if (!res.isOk) return const [];
      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return const [];
      final list = data['results'] as List<dynamic>? ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => _parseCandidate(m, mediaType))
          .whereType<TmdbSearchCandidate>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _mergeCandidates(
    Map<String, TmdbSearchCandidate> target,
    List<TmdbSearchCandidate> incoming, {
    required bool preservePrimaryTitle,
  }) {
    for (final item in incoming) {
      final key = '${item.mediaType.wireValue}:${item.tmdbId}';
      final existing = target[key];
      if (existing == null) {
        target[key] = item;
        continue;
      }
      final aliases = <String>{
        ...existing.matchedAliases,
        if (existing.title.isNotEmpty) existing.title,
        if (existing.originalTitle.isNotEmpty) existing.originalTitle,
        if (item.title.isNotEmpty) item.title,
        if (item.originalTitle.isNotEmpty) item.originalTitle,
        ...item.matchedAliases,
      }.where((s) => s.trim().isNotEmpty).toList();

      target[key] = existing.copyWith(
        title: preservePrimaryTitle && existing.title.isNotEmpty
            ? existing.title
            : (item.title.isNotEmpty ? item.title : existing.title),
        originalTitle: existing.originalTitle.isNotEmpty
            ? existing.originalTitle
            : item.originalTitle,
        posterPath: existing.posterPath.isNotEmpty
            ? existing.posterPath
            : item.posterPath,
        genreIds:
            existing.genreIds.isNotEmpty ? existing.genreIds : item.genreIds,
        voteCount: existing.voteCount >= item.voteCount
            ? existing.voteCount
            : item.voteCount,
        popularity: existing.popularity >= item.popularity
            ? existing.popularity
            : item.popularity,
        voteAverage: existing.voteAverage > 0
            ? existing.voteAverage
            : item.voteAverage,
        matchedAliases: aliases,
      );
    }
  }

  Future<List<TmdbSearchCandidate>> _runSearchMulti({
    required String apiKey,
    required String query,
    required String locale,
    int? yearHint,
  }) async {
    final res = await _get(apiKey, '/3/search/multi', {
      'query': query,
      'language': locale,
      'include_adult': 'false',
    });
    if (!res.isOk) {
      throw TmdbHttpException(res.statusCode, 'HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) return const [];
    final list = data['results'] as List<dynamic>? ?? const [];
    final out = <TmdbSearchCandidate>[];
    for (final raw in list) {
      if (raw is! Map<String, dynamic>) continue;
      final typeStr = (raw['media_type'] ?? '').toString();
      if (typeStr != 'movie' && typeStr != 'tv') continue;
      final item = _parseCandidate(raw, MediaType.fromWire(typeStr));
      if (item != null && TmdbMatcher.yearsCompatible(yearHint, item.year)) {
        out.add(item);
      }
    }
    return out;
  }

  Future<List<TmdbSearchCandidate>> searchTyped({
    required String apiKey,
    required MediaType mediaType,
    required String query,
    String contentLanguage = 'uk',
    int? year,
  }) async {
    final q = query.trim();
    if (q.isEmpty || _normalizeToken(apiKey).isEmpty) return const [];
    final locale = toTmdbLocale(contentLanguage);
    var out = await _runSearchTyped(
      apiKey: apiKey,
      mediaType: mediaType,
      query: q,
      locale: locale,
      year: year,
    );
    if (out.isEmpty) {
      final phonetic = TmdbMatcher.phoneticLatinQuery(q);
      if (phonetic.isNotEmpty && phonetic.toLowerCase() != q.toLowerCase()) {
        out = await _runSearchTyped(
          apiKey: apiKey,
          mediaType: mediaType,
          query: phonetic,
          locale: locale,
          year: year,
        );
      }
    }
    return out;
  }

  Future<List<TmdbSearchCandidate>> _runSearchTyped({
    required String apiKey,
    required MediaType mediaType,
    required String query,
    required String locale,
    int? year,
  }) async {
    final page = await _runSearchTypedPage(
      apiKey: apiKey,
      mediaType: mediaType,
      query: query,
      locale: locale,
      year: year,
    );
    return page.items;
  }

  Future<_SearchPageResult> _runSearchTypedPage({
    required String apiKey,
    required MediaType mediaType,
    required String query,
    required String locale,
    int? year,
    int page = 1,
    bool throwOnError = false,
  }) async {
    final params = <String, String>{
      'query': query,
      'language': locale,
      'include_adult': 'false',
      if (page > 1) 'page': '$page',
    };
    if (year != null && year > 1880) {
      params[mediaType == MediaType.movie ? 'year' : 'first_air_date_year'] = '$year';
    }
    final res = await _get(apiKey, '/3/search/${mediaType.wireValue}', params);
    if (!res.isOk) {
      if (throwOnError) {
        throw TmdbHttpException(res.statusCode, 'HTTP ${res.statusCode}');
      }
      return const _SearchPageResult(items: [], totalPages: 1);
    }
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) {
      return const _SearchPageResult(items: [], totalPages: 1);
    }
    final list = data['results'] as List<dynamic>? ?? const [];
    final totalPages = (data['total_pages'] is num)
        ? (data['total_pages'] as num).toInt()
        : 1;
    final items = list
        .whereType<Map<String, dynamic>>()
        .map((m) => _parseCandidate(m, mediaType))
        .whereType<TmdbSearchCandidate>()
        .toList();
    return _SearchPageResult(items: items, totalPages: totalPages);
  }

  Future<MediaDetails?> fetchDetails({
    required String apiKey,
    required MediaType mediaType,
    required int tmdbId,
    String contentLanguage = 'uk',
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty || tmdbId <= 0) return null;

    final primaryLocale = toTmdbLocale(contentLanguage);
    final primaryData = await _getDetailsJson(
      apiKey: key,
      mediaType: mediaType,
      tmdbId: tmdbId,
      locale: primaryLocale,
      appendAll: true,
    );
    if (primaryData == null) return null;

    var overview = (primaryData['overview'] ?? '').toString().trim();
    var trailerKey = _pickYoutubeTrailerKey(primaryData['videos']);

    // Auto-fallback uk-UA -> ru-RU -> en-US for missing overview or trailer
    final fallbackLocales = ['uk-UA', 'ru-RU', 'en-US']
        .where((l) => l != primaryLocale)
        .toList();
    for (final loc in fallbackLocales) {
      if (overview.isNotEmpty && trailerKey != null) break;
      final fb = await _getDetailsJson(
        apiKey: key,
        mediaType: mediaType,
        tmdbId: tmdbId,
        locale: loc,
        appendAll: false,
      );
      if (fb == null) continue;
      if (overview.isEmpty) {
        final fbOverview = (fb['overview'] ?? '').toString().trim();
        if (fbOverview.isNotEmpty) overview = fbOverview;
      }
      trailerKey ??= _pickYoutubeTrailerKey(fb['videos']);
    }

    final title = (primaryData['title'] ?? primaryData['name'] ?? '').toString().trim();
    final originalTitle =
        (primaryData['original_title'] ?? primaryData['original_name'] ?? '').toString().trim();
    final dateStr = (primaryData['release_date'] ?? primaryData['first_air_date'] ?? '').toString();
    final year = dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) : null;

    final rawGenres = primaryData['genres'] as List<dynamic>? ?? const [];
    final genreIds = <int>[];
    final genres = <String>[];
    for (final g in rawGenres) {
      if (g is! Map<String, dynamic>) continue;
      final gid = (g['id'] is num) ? (g['id'] as num).toInt() : null;
      final gname = (g['name'] ?? '').toString().trim();
      if (gid != null) genreIds.add(gid);
      if (gname.isNotEmpty) genres.add(gname);
    }

    final countries = _localizeCountries(
      primaryData['production_countries'] as List<dynamic>? ?? const [],
      contentLanguage,
    );

    final directors = <String>[];
    if (mediaType == MediaType.tv) {
      for (final c in (primaryData['created_by'] as List<dynamic>? ?? const [])) {
        if (c is Map<String, dynamic>) {
          final n = (c['name'] ?? '').toString().trim();
          if (n.isNotEmpty) directors.add(n);
        }
      }
    }
    final credits = primaryData['credits'] as Map<String, dynamic>?;
    if (directors.isEmpty && credits != null) {
      for (final crew in (credits['crew'] as List<dynamic>? ?? const [])) {
        if (crew is Map<String, dynamic> && crew['job'] == 'Director') {
          final n = (crew['name'] ?? '').toString().trim();
          if (n.isNotEmpty) directors.add(n);
        }
      }
    }

    final cast = <String>[];
    if (credits != null) {
      for (final actor in (credits['cast'] as List<dynamic>? ?? const []).take(6)) {
        if (actor is Map<String, dynamic>) {
          final n = (actor['name'] ?? '').toString().trim();
          if (n.isNotEmpty) cast.add(n);
        }
      }
    }

    final ext = primaryData['external_ids'] as Map<String, dynamic>?;
    final imdbId = (ext?['imdb_id'] ?? primaryData['imdb_id'])?.toString().trim();

    int? runtime;
    if (primaryData['runtime'] is num) {
      runtime = (primaryData['runtime'] as num).toInt();
    } else if (primaryData['episode_run_time'] is List &&
        (primaryData['episode_run_time'] as List).isNotEmpty) {
      final first = (primaryData['episode_run_time'] as List).first;
      if (first is num) runtime = first.toInt();
    }

    final seasons = primaryData['number_of_seasons'] is num
        ? (primaryData['number_of_seasons'] as num).toInt()
        : null;

    return MediaDetails(
      mediaType: mediaType,
      tmdbId: tmdbId,
      title: title,
      originalTitle: originalTitle,
      year: year,
      overview: overview,
      posterPath: (primaryData['poster_path'] ?? '').toString(),
      backdropPath: (primaryData['backdrop_path'] ?? '').toString(),
      genreIds: genreIds,
      genres: genres,
      countries: countries,
      directorsOrCreators: directors.take(3).toList(),
      cast: cast,
      tmdbRating: (primaryData['vote_average'] is num)
          ? (primaryData['vote_average'] as num).toDouble()
          : null,
      runtimeMinutes: (runtime != null && runtime > 0) ? runtime : null,
      numberOfSeasons: seasons,
      imdbId: (imdbId != null && imdbId.isNotEmpty) ? imdbId : null,
      youtubeTrailerKey: trailerKey,
    );
  }

  Future<int?> fetchMovieRuntimeMinutes({
    required String apiKey,
    required int tmdbId,
  }) async {
    final key = _normalizeToken(apiKey);
    if (key.isEmpty || tmdbId <= 0) return null;
    try {
      final res = await _get(key, '/3/movie/$tmdbId');
      if (!res.isOk) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final runtime = decoded['runtime'];
      if (runtime is num && runtime > 0) return runtime.toInt();
    } catch (_) {}
    return null;
  }

  static List<String> _localizeCountries(
    List<dynamic> rawCountries,
    String contentLanguage,
  ) {
    final lang = contentLanguage.toLowerCase();
    final map = lang == 'ru'
        ? _countryNamesRu
        : (lang == 'uk' ? _countryNamesUk : const <String, String>{});
    return rawCountries
        .whereType<Map<String, dynamic>>()
        .map((c) {
          final iso = (c['iso_3166_1'] ?? '').toString().trim().toUpperCase();
          final localized = map[iso];
          if (localized != null && localized.isNotEmpty) return localized;
          return (c['name'] ?? iso).toString().trim();
        })
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
  }

  static const Map<String, String> _countryNamesRu = {
    'US': 'США',
    'GB': 'Великобритания',
    'UA': 'Украина',
    'RU': 'Россия',
    'FR': 'Франция',
    'DE': 'Германия',
    'JP': 'Япония',
    'KR': 'Южная Корея',
    'CA': 'Канада',
    'IT': 'Италия',
    'ES': 'Испания',
    'PL': 'Польша',
    'AU': 'Австралия',
    'CN': 'Китай',
    'HK': 'Гонконг',
    'TW': 'Тайвань',
    'IN': 'Индия',
    'SE': 'Швеция',
    'DK': 'Дания',
    'NO': 'Норвегия',
    'FI': 'Финляндия',
    'NL': 'Нидерланды',
    'BE': 'Бельгия',
    'CH': 'Швейцария',
    'AT': 'Австрия',
    'CZ': 'Чехия',
    'HU': 'Венгрия',
    'BR': 'Бразилия',
    'MX': 'Мексика',
    'AR': 'Аргентина',
    'NZ': 'Новая Зеландия',
    'IE': 'Ирландия',
    'IL': 'Израиль',
    'TR': 'Турция',
    'TH': 'Таиланд',
    'ID': 'Индонезия',
  };

  static const Map<String, String> _countryNamesUk = {
    'US': 'США',
    'GB': 'Велика Британія',
    'UA': 'Україна',
    'RU': 'Росія',
    'FR': 'Франція',
    'DE': 'Німеччина',
    'JP': 'Японія',
    'KR': 'Південна Корея',
    'CA': 'Канада',
    'IT': 'Італія',
    'ES': 'Іспанія',
    'PL': 'Польща',
    'AU': 'Австралія',
    'CN': 'Китай',
    'HK': 'Гонконг',
    'TW': 'Тайвань',
    'IN': 'Індія',
    'SE': 'Швеція',
    'DK': 'Данія',
    'NO': 'Норвегія',
    'FI': 'Фінляндія',
    'NL': 'Нідерланди',
    'BE': 'Бельгія',
    'CH': 'Швейцарія',
    'AT': 'Австрія',
    'CZ': 'Чехія',
    'HU': 'Угорщина',
    'BR': 'Бразилія',
    'MX': 'Мексика',
    'AR': 'Аргентина',
    'NZ': 'Нова Зеландія',
    'IE': 'Ірландія',
    'IL': 'Ізраїль',
    'TR': 'Туреччина',
    'TH': 'Таїланд',
    'ID': 'Індонезія',
  };

  /// Queries TMDB `/3/movie/{id}/release_dates` for a movie's digital release
  /// date (`type == 4`). Strictly for movies only; series have no movie digital release.
  Future<DateTime?> fetchMovieDigitalReleaseDate({
    required String apiKey,
    required int tmdbId,
  }) async {
    final key = _normalizeToken(apiKey);
    if (key.isEmpty || tmdbId <= 0) return null;

    final res = await _get(key, '/3/movie/$tmdbId/release_dates');
    if (!res.isOk) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;

    final results = decoded['results'];
    if (results is! List) return null;

    const priorityRegions = ['UA', 'US', 'GB', 'RU'];
    DateTime? preferredDate;
    int preferredRank = 999;
    DateTime? earliestAny;

    for (final countryEntry in results.whereType<Map<String, dynamic>>()) {
      final iso = (countryEntry['iso_3166_1'] ?? '').toString().toUpperCase();
      final releases = countryEntry['release_dates'];
      if (releases is! List) continue;
      for (final rel in releases.whereType<Map<String, dynamic>>()) {
        final type = rel['type'] is num ? (rel['type'] as num).toInt() : 0;
        if (type != 4) continue; // 4 = Digital
        final rawDate = (rel['release_date'] ?? '').toString().trim();
        final parsed = DateTime.tryParse(rawDate);
        if (parsed == null) continue;

        final utcDate = DateTime.utc(parsed.year, parsed.month, parsed.day);
        if (earliestAny == null || utcDate.isBefore(earliestAny)) {
          earliestAny = utcDate;
        }
        final rank = priorityRegions.indexOf(iso);
        if (rank >= 0 && rank < preferredRank) {
          preferredRank = rank;
          preferredDate = utcDate;
        }
      }
    }
    return preferredDate ?? earliestAny;
  }

  Future<List<TmdbSearchCandidate>> discoverFallback({
    required String apiKey,
    required MediaType mediaType,
    String contentLanguage = 'uk',
    List<int> withGenres = const [],
    List<int> withoutGenres = const [],
    int? maxRuntimeMinutes,
    int? minYear,
    double? minRating,
    int page = 1,
  }) async {
    final key = _normalizeToken(apiKey);
    if (key.isEmpty) return const [];
    final params = <String, String>{
      'language': toTmdbLocale(contentLanguage),
      'include_adult': 'false',
      'sort_by': 'popularity.desc',
      'vote_count.gte': '80',
      'page': '$page',
    };
    if (withGenres.isNotEmpty) {
      params['with_genres'] = withGenres.join(',');
    }
    if (withoutGenres.isNotEmpty) {
      params['without_genres'] = withoutGenres.join(',');
    }
    if (maxRuntimeMinutes != null && maxRuntimeMinutes > 0 && mediaType == MediaType.movie) {
      params['with_runtime.lte'] = '$maxRuntimeMinutes';
    }
    if (minYear != null && minYear > 1900) {
      params[mediaType == MediaType.movie ? 'primary_release_date.gte' : 'first_air_date.gte'] =
          '$minYear-01-01';
    }
    if (minRating != null && minRating > 0) {
      params['vote_average.gte'] = minRating.toStringAsFixed(1);
    }

    final res = await _get(apiKey, '/3/discover/${mediaType.wireValue}', params);
    if (!res.isOk) {
      throw TmdbHttpException(res.statusCode, 'HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) return const [];
    final list = data['results'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => _parseCandidate(m, mediaType))
        .whereType<TmdbSearchCandidate>()
        .toList();
  }

  Future<Map<String, dynamic>?> _getDetailsJson({
    required String apiKey,
    required MediaType mediaType,
    required int tmdbId,
    required String locale,
    required bool appendAll,
  }) async {
    final res = await _get(apiKey, '/3/${mediaType.wireValue}/$tmdbId', {
      'language': locale,
      'append_to_response': appendAll ? 'videos,external_ids,credits' : 'videos',
    });
    if (!res.isOk) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  String? _pickYoutubeTrailerKey(Object? rawVideos) {
    if (rawVideos is! Map<String, dynamic>) return null;
    final results = rawVideos['results'] as List<dynamic>? ?? const [];
    String? teaser;
    for (final v in results) {
      if (v is! Map<String, dynamic>) continue;
      if (v['site'] != 'YouTube') continue;
      final key = (v['key'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final type = (v['type'] ?? '').toString();
      if (type == 'Trailer') return key;
      teaser ??= key;
    }
    return teaser;
  }

  TmdbSearchCandidate? _parseCandidate(Map<String, dynamic> m, MediaType mediaType) {
    final id = (m['id'] is num) ? (m['id'] as num).toInt() : 0;
    if (id <= 0) return null;
    final title = (m['title'] ?? m['name'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    final originalTitle = (m['original_title'] ?? m['original_name'] ?? '').toString().trim();
    final dateStr = (m['release_date'] ?? m['first_air_date'] ?? '').toString();
    final year = dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) : null;
    final genres = (m['genre_ids'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    return TmdbSearchCandidate(
      tmdbId: id,
      mediaType: mediaType,
      title: title,
      originalTitle: originalTitle,
      year: year,
      posterPath: (m['poster_path'] ?? '').toString(),
      genreIds: genres,
      voteAverage: (m['vote_average'] is num) ? (m['vote_average'] as num).toDouble() : 0.0,
      popularity: (m['popularity'] is num) ? (m['popularity'] as num).toDouble() : 0.0,
      voteCount: (m['vote_count'] is num) ? (m['vote_count'] as num).toInt() : 0,
    );
  }
}

class _SearchPageResult {
  const _SearchPageResult({
    required this.items,
    required this.totalPages,
  });

  final List<TmdbSearchCandidate> items;
  final int totalPages;
}
