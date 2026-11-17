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
}

/// Exact normalized title/originalTitle and +-1 year matcher for TMDB verification.
class TmdbMatcher {
  const TmdbMatcher._();

  static final RegExp _punctuation = RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _cyrillic = RegExp(r'[а-яА-ЯёЁіїєґІЇЄҐ]');

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

  /// Converts Cyrillic phonetic/loanword queries (e.g. "стрит файтер") into Latin ("street fighter").
  static String phoneticLatinQuery(String raw) {
    final trimmed = raw.trim().replaceAll(_spaces, ' ');
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

  static bool titlesMatch(String query, String candidate) {
    final a = normalizeTitle(query);
    final b = normalizeTitle(candidate);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
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

  static bool yearsCompatible(int? expectedYear, int? candidateYear) {
    if (expectedYear == null || expectedYear <= 0) return true;
    if (candidateYear == null || candidateYear <= 0) return false;
    return (expectedYear - candidateYear).abs() <= 1;
  }

  static TmdbSearchCandidate? pickBestMatch({
    required String title,
    String originalTitle = '',
    int? year,
    MediaType? preferredType,
    required List<TmdbSearchCandidate> results,
  }) {
    TmdbSearchCandidate? best;
    var bestScore = -1.0;

    for (final item in results) {
      if (item.tmdbId <= 0) continue;
      if (!yearsCompatible(year, item.year)) continue;

      final exactMain = normalizeTitle(title) == normalizeTitle(item.title) ||
          normalizeTitle(title) == normalizeTitle(item.originalTitle);
      final exactOrig = originalTitle.isNotEmpty &&
          (normalizeTitle(originalTitle) == normalizeTitle(item.title) ||
              normalizeTitle(originalTitle) == normalizeTitle(item.originalTitle));
      final looseMatch = titlesMatch(title, item.title) ||
          titlesMatch(title, item.originalTitle) ||
          (originalTitle.isNotEmpty &&
              (titlesMatch(originalTitle, item.title) ||
                  titlesMatch(originalTitle, item.originalTitle)));

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
}
