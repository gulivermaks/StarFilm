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
    // Allow subtitle prefix match when query has >= 4 chars and covers whole words.
    if (a.length >= 4 && b.startsWith('$a ')) return true;
    if (b.length >= 4 && a.startsWith('$b ')) return true;
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
