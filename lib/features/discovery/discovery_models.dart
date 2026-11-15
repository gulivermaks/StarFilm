import '../../core/models/media_key.dart';

enum EveningPreset {
  friends('friends'),
  family('family'),
  under90('under_90'),
  tense('tense'),
  trueStory('true_story');

  const EveningPreset(this.id);
  final String id;
}

class DiscoveryRequest {
  const DiscoveryRequest({
    this.prompt = '',
    this.preset,
    this.mediaTypeFilter,
    this.maxMinutes,
    this.guestMode = false,
    this.different = false,
  });

  final String prompt;
  final EveningPreset? preset;
  final MediaType? mediaTypeFilter; // null means All (movies + series)
  final int? maxMinutes;
  final bool guestMode;
  final bool different;
}

class GeminiCandidate {
  const GeminiCandidate({
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.mediaType,
    required this.genre,
    required this.reason,
  });

  final String title;
  final String originalTitle;
  final int? year;
  final MediaType mediaType;
  final String genre;
  final String reason;

  factory GeminiCandidate.fromJson(Map<String, dynamic> json) {
    final rawYear = json['year'];
    final year = rawYear is num ? rawYear.toInt() : int.tryParse('${rawYear ?? ''}');
    final rawType = (json['media_type'] ?? json['type'] ?? 'movie').toString().toLowerCase();
    return GeminiCandidate(
      title: (json['title'] ?? '').toString().trim(),
      originalTitle: (json['original_title'] ?? json['originalTitle'] ?? '').toString().trim(),
      year: year,
      mediaType: rawType == 'tv' || rawType == 'series' ? MediaType.tv : MediaType.movie,
      genre: (json['genre'] ?? '').toString().trim(),
      reason: (json['reason'] ?? '').toString().trim(),
    );
  }
}

class RecommendationCard {
  const RecommendationCard({
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.posterPath,
    required this.genreIds,
    required this.tmdbRating,
    required this.reason,
    this.runtimeMinutes,
    this.fromFallback = false,
  });

  final MediaType mediaType;
  final int tmdbId;
  final String title;
  final String originalTitle;
  final int? year;
  final String posterPath;
  final List<int> genreIds;
  final double? tmdbRating;
  final String reason;
  final int? runtimeMinutes;
  final bool fromFallback;

  MediaKey get mediaKey => MediaKey(mediaType, tmdbId);
}
