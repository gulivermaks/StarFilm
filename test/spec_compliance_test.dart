import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/core/models/library_entry.dart';
import 'package:starfilm/core/models/profile.dart';
import 'package:starfilm/features/discovery/discovery_models.dart';

void main() {
  test('19 standard TMDB genres exclude any separate mysticism or supernatural toggles', () {
    expect(kStandardGenres.length, 19);
    for (final g in kStandardGenres) {
      expect(g.en.toLowerCase(), isNot(contains('supernatural')));
      expect(g.uk.toLowerCase(), isNot(contains('містик')));
      expect(g.ru.toLowerCase(), isNot(contains('мистик')));
    }
  });

  test('Guest mode omits narrow personal ratings while preserving doNotRecommend', () {
    final profile = UserProfile(
      id: 'main',
      name: 'Головний',
      preferences: const ProfilePreferences(excludedGenres: [27], personalized: true),
    );
    const rated = LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Fight Club',
      status: WatchStatus.watched,
      userRating: 10,
      sentiment: Sentiment.liked,
    );

    final payload = GeminiClient.buildCompactPromptPayload(
      request: const DiscoveryRequest(guestMode: true),
      profile: profile,
      library: const [rated],
      recentShownLabels: const ['Matrix (1999)'],
    );

    expect(payload.containsKey('preferences'), isFalse);
    expect(payload['doNotRecommend'], contains('Fight Club'));
    expect(payload['recentShown'], contains('Matrix (1999)'));
  });

  test('Codebase contains zero FreeMyTV or episode-progress user UI references', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);
    final forbiddenBranding = RegExp(r'freemytv', caseSensitive: false);
    final forbiddenEpisodeProgress = RegExp(
      r'\b(seasonNumber|episodeNumber|episodeProgress|nextEpisode|lastWatchedEpisode)\b',
    );

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      expect(forbiddenBranding.hasMatch(content), isFalse, reason: entity.path);
      expect(forbiddenEpisodeProgress.hasMatch(content), isFalse, reason: entity.path);
    }
  });
}
