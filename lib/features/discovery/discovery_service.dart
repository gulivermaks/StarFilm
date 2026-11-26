import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../../core/security/log_sanitizer.dart';
import '../ratings/kinopoisk_client.dart';
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

/// AI recommendation cascade + exact TMDB prompt matching + TMDB recommendations/discover fallback.
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
    String backupAiKey = '',
    required String geminiModel,
    required DiscoveryRequest request,
    required UserProfile profile,
    required List<LibraryEntry> library,
    required Set<String> recentShownIds,
    required List<String> recentShownLabels,
    KinopoiskClient? kinopoisk,
    String kinopoiskApiKey = '',
    int discoverPage = 1,
  }) async {
    final excludedMediaKeys = <String>{
      for (final e in library)
        if (e.isExcludedFromRecommendations) e.keyString,
      ...recentShownIds,
    };
    final excludedGenres = profile.preferences.excludedGenres.toSet();
    final contentLang = profile.preferences.contentLanguage;
    final maxRuntime = request.maxMinutes ??
        (request.preset == EveningPreset.under90 ? 90 : null);
    final promptText = TmdbMatcher.cleanSearchQuery(request.prompt);
    final phoneticPrompt = TmdbMatcher.phoneticLatinQuery(promptText);
    final hasPhoneticPrompt = phoneticPrompt.isNotEmpty &&
        phoneticPrompt.toLowerCase() != promptText.toLowerCase();

    final hasAnyAiKey = geminiApiKey.trim().isNotEmpty ||
        GeminiClient.parseKeyList(backupAiKey).isNotEmpty;

    final shouldSearchPromptDirect = promptText.isNotEmpty &&
        promptText.length <= 80 &&
        !request.different &&
        tmdbApiKey.trim().isNotEmpty;

    // Launch direct catalog lookup in parallel with AI when user entered a query/title.
    final Future<List<TmdbSearchCandidate>> directSearchFuture =
        shouldSearchPromptDirect
            ? _tmdb
                .searchCatalog(
                  apiKey: tmdbApiKey,
                  query: promptText,
                  contentLanguage: contentLang,
                  mediaTypeFilter: request.mediaTypeFilter,
                  kinopoisk: kinopoisk,
                  kinopoiskApiKey: kinopoiskApiKey,
                )
                .catchError((Object e) {
                _log?.warn('TMDB direct prompt search skipped: $e');
                return const <TmdbSearchCandidate>[];
              })
            : Future.value(const <TmdbSearchCandidate>[]);

    var geminiFailed = !hasAnyAiKey;
    String? fallbackReason = hasAnyAiKey ? null : 'No AI key';
    List<RecommendationCard> aiCards = const [];

    Future<void> runAi() async {
      if (!hasAnyAiKey) return;
      try {
        final candidates = await _gemini.generateCandidates(
          apiKey: geminiApiKey,
          backupApiKey: backupAiKey,
          model: geminiModel,
          request: request,
          profile: profile,
          library: library,
          recentShownLabels: recentShownLabels,
        );

        final verifiedList = await Future.wait(
          candidates.take(12).map((cand) async {
            final primaryQuery =
                cand.originalTitle.isNotEmpty ? cand.originalTitle : cand.title;
            var results = await _tmdb.searchTyped(
              apiKey: tmdbApiKey,
              mediaType: cand.mediaType,
              query: primaryQuery,
              contentLanguage: contentLang,
            );
            var matched = TmdbMatcher.pickBestMatch(
              title: cand.title,
              originalTitle: cand.originalTitle,
              year: cand.year,
              preferredType: cand.mediaType,
              results: results,
            );
            if (matched == null &&
                cand.originalTitle.isNotEmpty &&
                cand.title.isNotEmpty &&
                cand.title != cand.originalTitle) {
              results = await _tmdb.searchTyped(
                apiKey: tmdbApiKey,
                mediaType: cand.mediaType,
                query: cand.title,
                contentLanguage: contentLang,
              );
              matched = TmdbMatcher.pickBestMatch(
                title: cand.title,
                originalTitle: cand.originalTitle,
                year: cand.year,
                preferredType: cand.mediaType,
                results: results,
              );
            }
            if (matched == null) return null;
            int? runtimeMinutes;
            if (maxRuntime != null && matched.mediaType == MediaType.movie) {
              runtimeMinutes = await _tmdb.fetchMovieRuntimeMinutes(
                apiKey: tmdbApiKey,
                tmdbId: matched.tmdbId,
              );
            }
            return (cand, matched, runtimeMinutes);
          }),
        );

        final built = <RecommendationCard>[];
        for (final triple in verifiedList) {
          if (triple == null) continue;
          final (cand, matched, runtimeMinutes) = triple;
          if (request.mediaTypeFilter != null &&
              matched.mediaType != request.mediaTypeFilter) {
            continue;
          }
          if (maxRuntime != null &&
              matched.mediaType == MediaType.movie &&
              runtimeMinutes != null &&
              runtimeMinutes > maxRuntime) {
            continue;
          }
          built.add(
            RecommendationCard(
              mediaType: matched.mediaType,
              tmdbId: matched.tmdbId,
              title: matched.title,
              originalTitle: matched.originalTitle,
              year: matched.year,
              posterPath: matched.posterPath,
              genreIds: matched.genreIds,
              tmdbRating: matched.voteAverage > 0 ? matched.voteAverage : null,
              reason: cand.reason,
              runtimeMinutes: runtimeMinutes,
            ),
          );
        }
        aiCards = built;
      } on GeminiQuotaException catch (e) {
        geminiFailed = true;
        fallbackReason = e.message;
        _log?.warn('Gemini fallback triggered: ${e.message}');
      } catch (e) {
        geminiFailed = true;
        fallbackReason = e.toString();
        _log?.warn('Gemini error, falling back to TMDB discover: $e');
      }
    }

    final parallelResults = await Future.wait<Object?>([
      directSearchFuture,
      runAi().then((_) => null),
    ]);
    final directResults = parallelResults[0] as List<TmdbSearchCandidate>;

    final verified = <RecommendationCard>[];
    final addedKeys = <String>{};
    final aiReasonByKey = <String, String>{
      for (final card in aiCards)
        if (card.reason.isNotEmpty) card.mediaKey.value: card.reason,
    };

    // 1. Pin up to 3 exact title matches for explicit user queries regardless of excludedGenres/recentShownIds.
    if (shouldSearchPromptDirect && directResults.isNotEmpty) {
      for (final item in directResults) {
        if (verified.length >= 3) break;
        if (request.mediaTypeFilter != null &&
            item.mediaType != request.mediaTypeFilter) {
          continue;
        }
        final isExact = TmdbMatcher.isExactTitleMatch(
          query: promptText,
          item: item,
          phoneticQuery: hasPhoneticPrompt ? phoneticPrompt : null,
        );
        if (!isExact) continue;
        final key = MediaKey(item.mediaType, item.tmdbId).value;
        if (!addedKeys.add(key)) continue;
        verified.add(
          RecommendationCard(
            mediaType: item.mediaType,
            tmdbId: item.tmdbId,
            title: item.title,
            originalTitle: item.originalTitle,
            year: item.year,
            posterPath: item.posterPath,
            genreIds: item.genreIds,
            tmdbRating: item.voteAverage > 0 ? item.voteAverage : null,
            reason: aiReasonByKey[key] ?? '',
            isExactMatch: true,
          ),
        );
      }
    }

    // 2. Append AI-verified recommendations applying exclusions.
    for (final card in aiCards) {
      final key = card.mediaKey.value;
      if (excludedMediaKeys.contains(key) || addedKeys.contains(key)) continue;
      if (card.genreIds.any(excludedGenres.contains)) continue;
      addedKeys.add(key);
      verified.add(card);
    }

    final usedFallback = geminiFailed;

    // 3. Backfill with remaining relevant direct catalog hits when < 4 cards.
    if (verified.length < 4 && directResults.isNotEmpty) {
      for (final item in directResults) {
        if (verified.length >= 8) break;
        if (request.mediaTypeFilter != null &&
            item.mediaType != request.mediaTypeFilter) {
          continue;
        }
        final key = MediaKey(item.mediaType, item.tmdbId).value;
        if (excludedMediaKeys.contains(key) || addedKeys.contains(key)) continue;
        if (item.genreIds.any(excludedGenres.contains)) continue;
        addedKeys.add(key);
        verified.add(
          RecommendationCard(
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
          ),
        );
      }
    }

    // 4. Backfill using TMDB /recommendations for the matched title before generic /discover.
    if (verified.length < 4 &&
        directResults.isNotEmpty &&
        tmdbApiKey.trim().isNotEmpty) {
      final seed = directResults.first;
      final similar = await _tmdb.fetchRecommendations(
        apiKey: tmdbApiKey,
        mediaType: seed.mediaType,
        tmdbId: seed.tmdbId,
        contentLanguage: contentLang,
      );
      for (final item in similar) {
        if (verified.length >= 8) break;
        if (request.mediaTypeFilter != null &&
            item.mediaType != request.mediaTypeFilter) {
          continue;
        }
        final key = MediaKey(item.mediaType, item.tmdbId).value;
        if (excludedMediaKeys.contains(key) || addedKeys.contains(key)) continue;
        if (item.genreIds.any(excludedGenres.contains)) continue;
        int? runtimeMinutes;
        if (maxRuntime != null && item.mediaType == MediaType.movie) {
          runtimeMinutes = await _tmdb.fetchMovieRuntimeMinutes(
            apiKey: tmdbApiKey,
            tmdbId: item.tmdbId,
          );
          if (runtimeMinutes != null && runtimeMinutes > maxRuntime) continue;
        }
        addedKeys.add(key);
        verified.add(
          RecommendationCard(
            mediaType: item.mediaType,
            tmdbId: item.tmdbId,
            title: item.title,
            originalTitle: item.originalTitle,
            year: item.year,
            posterPath: item.posterPath,
            genreIds: item.genreIds,
            tmdbRating: item.voteAverage > 0 ? item.voteAverage : null,
            reason: 'TMDB',
            runtimeMinutes: runtimeMinutes,
            fromFallback: true,
          ),
        );
      }
    }

    // 5. Free TMDB /discover backfill if < 4 cards verified.
    if (verified.length < 4 && tmdbApiKey.trim().isNotEmpty) {
      final targetTypes = request.mediaTypeFilter != null
          ? [request.mediaTypeFilter!]
          : [MediaType.movie, MediaType.tv];
      final presetGenres = _presetGenres(request.preset);
      final effectiveGenres =
          presetGenres.isNotEmpty ? presetGenres : _inferGenresFromPrompt(promptText);
      final safePage = discoverPage.clamp(1, 20);

      for (final type in targetTypes) {
        if (verified.length >= 8) break;
        final List<TmdbSearchCandidate> discovered;
        try {
          discovered = await _tmdb.discoverFallback(
            apiKey: tmdbApiKey,
            mediaType: type,
            contentLanguage: contentLang,
            withGenres: effectiveGenres,
            withoutGenres: excludedGenres.toList(),
            maxRuntimeMinutes: maxRuntime,
            minRating: 6.5,
            page: safePage,
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
          verified.add(
            RecommendationCard(
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
            ),
          );
        }
      }
    }

    return DiscoveryResult(
      cards: verified,
      usedFallback: usedFallback,
      fallbackReason: fallbackReason,
    );
  }

  List<int> _inferGenresFromPrompt(String prompt) {
    final low = prompt.toLowerCase();
    if (low.isEmpty) return const [];
    if (low.contains('комед') || low.contains('comedy') || low.contains('смішн') || low.contains('смешн')) {
      return const [35];
    }
    if (low.contains('фантаст') || low.contains('sci-fi') || low.contains('scifi') || low.contains('космос')) {
      return const [878];
    }
    if (low.contains('жах') || low.contains('ужас') || low.contains('horror') || low.contains('страшн')) {
      return const [27];
    }
    if (low.contains('трил') || low.contains('thriller') || low.contains('саспенс')) {
      return const [53];
    }
    if (low.contains('детектив') || low.contains('detective') || low.contains('кримін') || low.contains('кримин')) {
      return const [9648, 80];
    }
    if (low.contains('мульт') || low.contains('анімац') || low.contains('анимац') || low.contains('anime')) {
      return const [16];
    }
    if (low.contains('сімейн') || low.contains('семейн') || low.contains('family')) {
      return const [10751];
    }
    if (low.contains('пригод') || low.contains('приключ') || low.contains('adventur')) {
      return const [12];
    }
    if (low.contains('бойовик') ||
        low.contains('боевик') ||
        low.contains('action') ||
        low.contains('екшн') ||
        low.contains('экшн') ||
        low.contains('файтер') ||
        low.contains('fighter')) {
      return const [28];
    }
    if (low.contains('фентез') || low.contains('фэнтез') || low.contains('fantasy')) {
      return const [14];
    }
    if (low.contains('драм') || low.contains('drama')) {
      return const [18];
    }
    if (low.contains('мелодрам') || low.contains('романт') || low.contains('romance')) {
      return const [10749];
    }
    if (low.contains('істор') || low.contains('истор') || low.contains('history')) {
      return const [36];
    }
    if (low.contains('документ') || low.contains('documentary')) {
      return const [99];
    }
    return const [];
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
