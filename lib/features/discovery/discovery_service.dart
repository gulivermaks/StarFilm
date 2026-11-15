import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../../core/security/log_sanitizer.dart';
import '../search/tmdb_client.dart';
import '../search/tmdb_matcher.dart';
import 'discovery_models.dart';
import 'gemini_client.dart';

class DiscoveryResult {
  const DiscoveryResult({
    required this.cards,
    required this.usedFallback,
    this.fallbackReason,
  });

  final List<RecommendationCard> cards;
  final bool usedFallback;
  final String? fallbackReason;
}

/// Single-step Gemini + parallel TMDB verification + strict local filter + TMDB /discover fallback.
class DiscoveryService {
  DiscoveryService({
    required GeminiClient gemini,
    required TmdbClient tmdb,
    DiagnosticsLog? log,
  })  : _gemini = gemini,
        _tmdb = tmdb,
        _log = log;

  final GeminiClient _gemini;
  final TmdbClient _tmdb;
  final DiagnosticsLog? _log;

  Future<DiscoveryResult> recommend({
    required String tmdbApiKey,
    required String geminiApiKey,
    required String geminiModel,
    required DiscoveryRequest request,
    required UserProfile profile,
    required List<LibraryEntry> library,
    required Set<String> recentShownIds,
    required List<String> recentShownLabels,
  }) async {
    final excludedMediaKeys = <String>{
      for (final e in library)
        if (e.isExcludedFromRecommendations) e.keyString,
      ...recentShownIds,
    };
    final excludedGenres = profile.preferences.excludedGenres.toSet();
    final contentLang = profile.preferences.contentLanguage;

    final verified = <RecommendationCard>[];
    final addedKeys = <String>{};
    var usedFallback = false;
    String? fallbackReason;

    // Step 1: Single Gemini call if key is available.
    if (geminiApiKey.trim().isNotEmpty) {
      try {
        final candidates = await _gemini.generateCandidates(
          apiKey: geminiApiKey,
          model: geminiModel,
          request: request,
          profile: profile,
          library: library,
          recentShownLabels: recentShownLabels,
        );

        // Step 2: Parallel TMDB verification and enrichment.
        final verifiedList = await Future.wait(
          candidates.take(12).map((cand) async {
            final searchQuery = cand.originalTitle.isNotEmpty ? cand.originalTitle : cand.title;
            final results = await _tmdb.searchTyped(
              apiKey: tmdbApiKey,
              mediaType: cand.mediaType,
              query: searchQuery,
              contentLanguage: contentLang,
              year: cand.year,
            );
            final matched = TmdbMatcher.pickBestMatch(
              title: cand.title,
              originalTitle: cand.originalTitle,
              year: cand.year,
              preferredType: cand.mediaType,
              results: results,
            );
            if (matched == null) return null;
            return (cand, matched);
          }),
        );

        for (final pair in verifiedList) {
          if (pair == null) continue;
          final (cand, matched) = pair;
          final key = MediaKey(matched.mediaType, matched.tmdbId).value;
          if (excludedMediaKeys.contains(key) || addedKeys.contains(key)) continue;
          if (matched.genreIds.any(excludedGenres.contains)) continue;
          if (request.mediaTypeFilter != null && matched.mediaType != request.mediaTypeFilter) {
            continue;
          }
          addedKeys.add(key);
          verified.add(RecommendationCard(
            mediaType: matched.mediaType,
            tmdbId: matched.tmdbId,
            title: matched.title,
            originalTitle: matched.originalTitle,
            year: matched.year,
            posterPath: matched.posterPath,
            genreIds: matched.genreIds,
            tmdbRating: matched.voteAverage > 0 ? matched.voteAverage : null,
            reason: cand.reason,
          ));
        }
      } on GeminiQuotaException catch (e) {
        usedFallback = true;
        fallbackReason = e.message;
        _log?.warn('Gemini fallback triggered: ${e.message}');
      } catch (e) {
        usedFallback = true;
        fallbackReason = e.toString();
        _log?.warn('Gemini error, falling back to TMDB discover: $e');
      }
    } else {
      usedFallback = true;
      fallbackReason = 'No Gemini key';
    }

    // Step 3: Free TMDB /discover backfill if < 4 cards verified.
    if (verified.length < 4 && tmdbApiKey.trim().isNotEmpty) {
      usedFallback = true;
      final targetTypes = request.mediaTypeFilter != null
          ? [request.mediaTypeFilter!]
          : [MediaType.movie, MediaType.tv];
      final presetGenres = _presetGenres(request.preset);
      final maxRuntime = request.maxMinutes ??
          (request.preset == EveningPreset.under90 ? 90 : null);

      for (final type in targetTypes) {
        if (verified.length >= 8) break;
        final List<TmdbSearchCandidate> discovered;
        try {
          discovered = await _tmdb.discoverFallback(
            apiKey: tmdbApiKey,
            mediaType: type,
            contentLanguage: contentLang,
            withGenres: presetGenres,
            withoutGenres: excludedGenres.toList(),
            maxRuntimeMinutes: maxRuntime,
            minRating: 6.5,
            page: request.different ? 2 : 1,
          );
        } catch (e) {
          if (verified.isNotEmpty) {
            _log?.warn('TMDB discover backfill failed: $e');
            break;
          }
          rethrow;
        }
        for (final item in discovered) {
          if (verified.length >= 8) break;
          final key = MediaKey(item.mediaType, item.tmdbId).value;
          if (excludedMediaKeys.contains(key) || addedKeys.contains(key)) continue;
          if (item.genreIds.any(excludedGenres.contains)) continue;
          addedKeys.add(key);
          verified.add(RecommendationCard(
            mediaType: item.mediaType,
            tmdbId: item.tmdbId,
            title: item.title,
            originalTitle: item.originalTitle,
            year: item.year,
            posterPath: item.posterPath,
            genreIds: item.genreIds,
            tmdbRating: item.voteAverage > 0 ? item.voteAverage : null,
            reason: 'TMDB',
            fromFallback: true,
          ));
        }
      }
    }

    return DiscoveryResult(
      cards: verified,
      usedFallback: usedFallback,
      fallbackReason: fallbackReason,
    );
  }

  List<int> _presetGenres(EveningPreset? preset) {
    switch (preset) {
      case EveningPreset.friends:
        return [35, 28]; // Comedy / Action
      case EveningPreset.family:
        return [10751, 12]; // Family / Adventure
      case EveningPreset.tense:
        return [53, 80]; // Thriller / Crime
      case EveningPreset.trueStory:
        return [36, 18]; // History / Drama
      case EveningPreset.under90:
      case null:
        return const [];
    }
  }
}
