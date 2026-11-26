import 'dart:math' as math;

import '../../core/models/media_key.dart';

class TmdbSearchCandidate {
  const TmdbSearchCandidate({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.posterPath,
    required this.genreIds,
    required this.voteAverage,
    required this.popularity,
    this.voteCount = 0,
    this.matchedAliases = const [],
  });

  final int tmdbId;
  final MediaType mediaType;
  final String title;
  final String originalTitle;
  final int? year;
  final String posterPath;
  final List<int> genreIds;
  final double voteAverage;
  final double popularity;
  final int voteCount;
  final List<String> matchedAliases;

  TmdbSearchCandidate copyWith({
    int? tmdbId,
    MediaType? mediaType,
    String? title,
    String? originalTitle,
    int? year,
    String? posterPath,
    List<int>? genreIds,
    double? voteAverage,
    double? popularity,
    int? voteCount,
    List<String>? matchedAliases,
  }) {
    return TmdbSearchCandidate(
      tmdbId: tmdbId ?? this.tmdbId,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      year: year ?? this.year,
      posterPath: posterPath ?? this.posterPath,
      genreIds: genreIds ?? this.genreIds,
      voteAverage: voteAverage ?? this.voteAverage,
      popularity: popularity ?? this.popularity,
      voteCount: voteCount ?? this.voteCount,
      matchedAliases: matchedAliases ?? this.matchedAliases,
    );
  }
}

/// Exact normalized title/originalTitle, ranking, and +-1 year matcher for TMDB search & AI verification.
class TmdbMatcher {
  const TmdbMatcher._();

  static final RegExp _punctuation = RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _cyrillic = RegExp(r'[а-яА-ЯёЁіїєґІЇЄҐ]');
  static final RegExp _ukrainianSpecific = RegExp(r'[іїєґІЇЄҐ]');
  static final RegExp _russianSpecific = RegExp(r'[ыэъёЫЭЪЁ]');

  static const Map<String, String> _phoneticWords = {
    'стрит': 'street',
    'стріт': 'street',
    'файтер': 'fighter',
    'мортал': 'mortal',
    'комбат': 'kombat',
    'бэтмен': 'batman',
    'бетмен': 'batman',
    'спайдермен': 'spider-man',
    'спайдер': 'spider',
    'айрон': 'iron',
    'мен': 'man',
    'мэн': 'man',
    'супермен': 'superman',
    'дедпул': 'deadpool',
    'дэдпул': 'deadpool',
    'джон': 'john',
    'уик': 'wick',
    'вік': 'wick',
    'стар': 'star',
    'ворс': 'wars',
    'варс': 'wars',
    'трек': 'trek',
    'блейд': 'blade',
    'раннер': 'runner',
    'ранер': 'runner',
    'интерстеллар': 'interstellar',
    'інтерстеллар': 'interstellar',
    'инсепшн': 'inception',
    'інсепшн': 'inception',
    'терминатор': 'terminator',
    'термінатор': 'terminator',
    'трансформеры': 'transformers',
    'трансформери': 'transformers',
    'авенджерс': 'avengers',
    'гарри': 'harry',
    'гаррі': 'harry',
    'поттер': 'potter',
    'матрица': 'matrix',
    'матриця': 'matrix',
    'дюна': 'dune',
    'аватар': 'avatar',
    'гладиатор': 'gladiator',
    'гладіатор': 'gladiator',
    'робокоп': 'robocop',
    'хищник': 'predator',
    'хижак': 'predator',
    'чужой': 'alien',
    'чужий': 'alien',
    'джокер': 'joker',
    'веном': 'venom',
    'фоллаут': 'fallout',
    'фолаут': 'fallout',
    'драйв': 'drive',
    'титаник': 'titanic',
    'титанік': 'titanic',
    'оппенгеймер': 'oppenheimer',
    'оппенгаймер': 'oppenheimer',
    'барби': 'barbie',
    'барбі': 'barbie',
    'соник': 'sonic',
    'сонік': 'sonic',
    'годзилла': 'godzilla',
    'годзілла': 'godzilla',
    'конг': 'kong',
    'шерлок': 'sherlock',
    'ведьмак': 'witcher',
    'відьмак': 'witcher',
    'флеш': 'flash',
    'флэш': 'flash',
    'аквамен': 'aquaman',
    'логан': 'logan',
    'бонд': 'bond',
    'пила': 'saw',
    'крик': 'scream',
    'оно': 'it',
    'марио': 'mario',
    'маріо': 'mario',
    'форсаж': 'fast',
    'рокки': 'rocky',
    'роккі': 'rocky',
    'рэмбо': 'rambo',
    'рембо': 'rambo',
    'шрек': 'shrek',
  };

  static const Map<String, String> _cyrillicTranslit = {
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'ґ': 'g',
    'д': 'd',
    'е': 'e',
    'є': 'ye',
    'ё': 'e',
    'ж': 'zh',
    'з': 'z',
    'и': 'i',
    'і': 'i',
    'ї': 'yi',
    'й': 'y',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ф': 'f',
    'х': 'kh',
    'ц': 'ts',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'shch',
    'ъ': '',
    'ы': 'y',
    'ь': '',
    'э': 'e',
    'ю': 'yu',
    'я': 'ya',
  };

  /// Strips outer quotes and normalizes spaces in a user search query.
  static String cleanSearchQuery(String raw) {
    var out = raw.trim().replaceAll(_spaces, ' ');
    const pairs = [
      ('«', '»'),
      ('"', '"'),
      ("'", "'"),
      ('„', '“'),
      ('“', '”'),
    ];
    var changed = true;
    while (changed && out.length >= 2) {
      changed = false;
      for (final (open, close) in pairs) {
        if (out.startsWith(open) && out.endsWith(close)) {
          out = out.substring(open.length, out.length - close.length).trim();
          changed = true;
        }
      }
    }
    return out;
  }

  /// Detects query script (`uk`, `ru`, `cyrillic`, or `latin`) for cross-locale TMDB lookups.
  static String detectQueryScript(String raw) {
    if (_ukrainianSpecific.hasMatch(raw)) return 'uk';
    if (_russianSpecific.hasMatch(raw)) return 'ru';
    if (_cyrillic.hasMatch(raw)) return 'cyrillic';
    return 'latin';
  }

  /// Converts Cyrillic phonetic/loanword queries (e.g. "стрит файтер") into Latin ("street fighter").
  static String phoneticLatinQuery(String raw) {
    final trimmed = cleanSearchQuery(raw);
    if (trimmed.isEmpty || !_cyrillic.hasMatch(trimmed)) {
      return trimmed;
    }
    final words = trimmed.split(' ');
    final out = <String>[];
    for (final word in words) {
      final low = word.toLowerCase();
      final mapped = _phoneticWords[low];
      if (mapped != null) {
        out.add(mapped);
        continue;
      }
      if (!_cyrillic.hasMatch(low)) {
        out.add(word);
        continue;
      }
      final buf = StringBuffer();
      for (var i = 0; i < low.length; i++) {
        final ch = low[i];
        buf.write(_cyrillicTranslit[ch] ?? ch);
      }
      final converted = buf.toString().trim();
      if (converted.isNotEmpty) {
        out.add(converted);
      }
    }
    return out.join(' ').trim();
  }

  static String normalizeTitle(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('і', 'i')
        .replaceAll('ї', 'i')
        .replaceAll('є', 'е')
        .replaceAll('ґ', 'г')
        .replaceAll(_punctuation, ' ')
        .replaceAll(_spaces, ' ')
        .trim();
  }

  static String stripLeadingArticle(String normalized) {
    for (final art in const ['the ', 'a ', 'an ']) {
      if (normalized.startsWith(art) && normalized.length > art.length) {
        return normalized.substring(art.length).trim();
      }
    }
    return normalized;
  }

  static String collapseSpaces(String normalized) =>
      normalized.replaceAll(' ', '');

  static bool isExactTitleMatch({
    required String query,
    required TmdbSearchCandidate item,
    String? phoneticQuery,
  }) {
    final nq = normalizeTitle(cleanSearchQuery(query));
    if (nq.isEmpty) return false;
    final nqNoArt = stripLeadingArticle(nq);
    final nqCollapsed = collapseSpaces(nq);

    final np = (phoneticQuery != null && phoneticQuery.trim().isNotEmpty)
        ? normalizeTitle(phoneticQuery)
        : '';
    final npNoArt = np.isNotEmpty ? stripLeadingArticle(np) : '';
    final npCollapsed = np.isNotEmpty ? collapseSpaces(np) : '';

    final titles = <String>[
      item.title,
      item.originalTitle,
      ...item.matchedAliases,
    ];
    for (final t in titles) {
      final nt = normalizeTitle(t);
      if (nt.isEmpty) continue;
      final ntNoArt = stripLeadingArticle(nt);
      final ntCollapsed = collapseSpaces(nt);

      if (nt == nq ||
          (nqNoArt.isNotEmpty && ntNoArt == nqNoArt) ||
          (nqCollapsed.isNotEmpty && ntCollapsed == nqCollapsed)) {
        return true;
      }
      if (np.isNotEmpty &&
          (nt == np ||
              (npNoArt.isNotEmpty && ntNoArt == npNoArt) ||
              (npCollapsed.isNotEmpty && ntCollapsed == npCollapsed))) {
        return true;
      }
    }
    return false;
  }

  static double scoreSearchCandidate({
    required String query,
    String? phoneticQuery,
    int? yearHint,
    MediaType? preferredType,
    required TmdbSearchCandidate item,
  }) {
    final nq = normalizeTitle(cleanSearchQuery(query));
    final nqNoArt = stripLeadingArticle(nq);
    final nqCollapsed = collapseSpaces(nq);

    final np = (phoneticQuery != null && phoneticQuery.trim().isNotEmpty)
        ? normalizeTitle(phoneticQuery)
        : '';
    final npNoArt = np.isNotEmpty ? stripLeadingArticle(np) : '';
    final npCollapsed = np.isNotEmpty ? collapseSpaces(np) : '';

    final queryTokens = nq
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();

    var bestTitleScore = 0.0;
    final titles = <String>[
      item.title,
      item.originalTitle,
      ...item.matchedAliases,
    ];

    for (final rawTitle in titles) {
      final nt = normalizeTitle(rawTitle);
      if (nt.isEmpty) continue;
      final ntNoArt = stripLeadingArticle(nt);
      final ntCollapsed = collapseSpaces(nt);

      var s = 0.0;
      if (nq.isNotEmpty && nt == nq) {
        s = 1000;
      } else if ((nqNoArt.isNotEmpty && ntNoArt == nqNoArt) ||
          (nqCollapsed.isNotEmpty && ntCollapsed == nqCollapsed)) {
        s = 850;
      } else if (np.isNotEmpty &&
          (nt == np ||
              (npNoArt.isNotEmpty && ntNoArt == npNoArt) ||
              (npCollapsed.isNotEmpty && ntCollapsed == npCollapsed))) {
        s = 800;
      } else if ((nq.isNotEmpty && nt.startsWith('$nq ')) ||
          (nqNoArt.isNotEmpty && ntNoArt.startsWith('$nqNoArt ')) ||
          (np.isNotEmpty && nt.startsWith('$np '))) {
        s = 420;
      } else if ((nq.isNotEmpty && ' $nt '.contains(' $nq ')) ||
          (nqNoArt.isNotEmpty && ' $ntNoArt '.contains(' $nqNoArt ')) ||
          (np.isNotEmpty && ' $nt '.contains(' $np '))) {
        s = 260;
      } else if (queryTokens.isNotEmpty) {
        final meaningful = queryTokens.where((w) => w.length >= 2).toList();
        final tokens = meaningful.isNotEmpty ? meaningful : queryTokens;
        final titleWords = nt.split(' ').where((w) => w.isNotEmpty).toList();
        final allPresent = tokens.every(
          (tok) => titleWords.any((tw) => tw == tok || tw.startsWith(tok)),
        );
        if (allPresent) {
          s = 180;
        }
      }

      if (s > bestTitleScore) {
        bestTitleScore = s;
      }
    }

    var score = bestTitleScore;

    if (yearHint != null && yearHint > 0) {
      if (item.year == yearHint) {
        score += 400;
      } else if (item.year != null && (item.year! - yearHint).abs() <= 1) {
        score += 180;
      } else if (item.year != null) {
        score -= 300;
      }
    }

    if (preferredType != null && item.mediaType == preferredType) {
      score += 40;
    }

    final voteBoost = math.min(math.log(item.voteCount + 1) * 14.0, 130.0);
    final popBoost = math.min(item.popularity, 100.0) * 0.35;
    final ratingBoost = item.voteAverage > 0 ? item.voteAverage * 2.0 : 0.0;
    score += voteBoost + popBoost + ratingBoost;

    if (item.voteCount == 0 && item.posterPath.isEmpty) {
      score -= 50;
    }
    return score;
  }

  static List<TmdbSearchCandidate> rankSearchResults({
    required String query,
    String? phoneticQuery,
    int? yearHint,
    MediaType? preferredType,
    required List<TmdbSearchCandidate> results,
  }) {
    if (results.length <= 1) return List<TmdbSearchCandidate>.from(results);
    final scored = results
        .map(
          (item) => (
            item: item,
            score: scoreSearchCandidate(
              query: query,
              phoneticQuery: phoneticQuery,
              yearHint: yearHint,
              preferredType: preferredType,
              item: item,
            ),
          ),
        )
        .toList();

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byVotes = b.item.voteCount.compareTo(a.item.voteCount);
      if (byVotes != 0) return byVotes;
      return b.item.popularity.compareTo(a.item.popularity);
    });
    return scored.map((e) => e.item).toList();
  }

  static bool titlesMatch(String query, String candidate) {
    final a = normalizeTitle(query);
    final b = normalizeTitle(candidate);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final aNoArt = stripLeadingArticle(a);
    final bNoArt = stripLeadingArticle(b);
    if (aNoArt.isNotEmpty && bNoArt.isNotEmpty && aNoArt == bNoArt) {
      return true;
    }
    final aCol = collapseSpaces(a);
    final bCol = collapseSpaces(b);
    if (aCol.isNotEmpty && bCol.isNotEmpty && aCol == bCol) {
      return true;
    }
    // Allow whole-word prefix/substring matches when query/candidate has >= 4 chars.
    if (a.length >= 4 &&
        (b.startsWith('$a ') || b.endsWith(' $a') || b.contains(' $a '))) {
      return true;
    }
    if (b.length >= 4 &&
        (a.startsWith('$b ') || a.endsWith(' $b') || a.contains(' $b '))) {
      return true;
    }
    return false;
  }

  static bool yearsCompatible(
    int? expectedYear,
    int? candidateYear, {
    int tolerance = 1,
  }) {
    if (expectedYear == null || expectedYear <= 0) return true;
    if (candidateYear == null || candidateYear <= 0) return false;
    return (expectedYear - candidateYear).abs() <= tolerance;
  }

  static TmdbSearchCandidate? pickBestMatch({
    required String title,
    String originalTitle = '',
    int? year,
    MediaType? preferredType,
    required List<TmdbSearchCandidate> results,
  }) {
    TmdbSearchCandidate? matchWithTolerance({
      required int tolerance,
      required bool exactOnly,
    }) {
      TmdbSearchCandidate? best;
      var bestScore = -1.0;

      for (final item in results) {
        if (item.tmdbId <= 0) continue;
        if (!yearsCompatible(year, item.year, tolerance: tolerance)) continue;

        final exactMain = isExactTitleMatch(query: title, item: item);
        final exactOrig = originalTitle.isNotEmpty &&
            isExactTitleMatch(query: originalTitle, item: item);
        final looseMatch = !exactOnly &&
            (titlesMatch(title, item.title) ||
                titlesMatch(title, item.originalTitle) ||
                (originalTitle.isNotEmpty &&
                    (titlesMatch(originalTitle, item.title) ||
                        titlesMatch(originalTitle, item.originalTitle))));

        if (!exactMain && !exactOrig && !looseMatch) continue;

        var score = 0.0;
        if (exactOrig || exactMain) score += 100;
        if (looseMatch) score += 20;
        if (year != null && item.year == year) score += 30;
        if (preferredType != null && item.mediaType == preferredType) score += 25;
        score += (item.popularity.clamp(0, 100)) * 0.1;

        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
      }
      return best;
    }

    final strict = matchWithTolerance(tolerance: 1, exactOnly: false);
    if (strict != null || year == null) return strict;
    return matchWithTolerance(tolerance: 2, exactOnly: true);
  }
}
