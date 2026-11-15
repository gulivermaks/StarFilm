import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starfilm/core/db/app_database.dart';
import 'package:starfilm/core/models/library_entry.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/features/cloud_sync/cloud_sync_models.dart';
import 'package:starfilm/features/library/backup_codec.dart';
import 'package:starfilm/features/library/library_repository.dart';

void main() {
  test('LibraryEntry invariants and independent field merge work cleanly', () {
    // Rating on watchlist transitions to watched; watching keeps watching
    final ratedWatchlist = const LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Fight Club',
      status: WatchStatus.watchlist,
      userRating: 9,
    ).normalized(nowMs: 1000);
    expect(ratedWatchlist.status, WatchStatus.watched);

    final ratedWatching = const LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.tv,
      tmdbId: 1396,
      title: 'Breaking Bad',
      status: WatchStatus.watching,
      userRating: 10,
    ).normalized(nowMs: 1000);
    expect(ratedWatching.status, WatchStatus.watching);
    expect(ratedWatching.userRating, 10);

    // Dismissed clears liked
    final dismissed = const LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 10,
      title: 'Test',
      status: WatchStatus.dismissed,
      sentiment: Sentiment.liked,
    ).normalized(nowMs: 1000);
    expect(dismissed.sentiment, Sentiment.neutral);

    // Independent merge: phone updates rating at t=2000, TV updates status at t=2500
    const phoneEntry = LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Fight Club',
      status: WatchStatus.watching,
      userRating: 9,
      statusChangedAt: 1000,
      ratingChangedAt: 2000,
      sentimentChangedAt: 1000,
      clientUpdatedAt: 2000,
    );
    const tvEntry = LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Fight Club',
      status: WatchStatus.watched,
      userRating: 7,
      statusChangedAt: 2500,
      ratingChangedAt: 1000,
      sentimentChangedAt: 1000,
      clientUpdatedAt: 2500,
    );
    final merged = LibraryEntry.merge(phoneEntry, tvEntry);
    expect(merged.status, WatchStatus.watched);
    expect(merged.userRating, 9);
  });

  test('BackupCodec imports StarTV backup ignoring progressNote and round-trips StarFilm JSON', () {
    final starTvBackup = jsonEncode({
      'schemaVersion': 1,
      'prefs': {'city': 'Kyiv'},
      'library': {
        'schemaVersion': 1,
        'personalized': true,
        'filters': {
          'excludedGenres': [27],
          'contentLanguage': 'uk',
        },
        'items': [
          {
            'tmdbId': 1399,
            'mediaType': 'tv',
            'title': 'Гра престолів',
            'originalTitle': 'Game of Thrones',
            'year': 2011,
            'watching': true,
            'userRating': 9,
            'progressNote': 'S2 E4',
          }
        ],
      },
    });

    final decodedTv = BackupCodec.decodeBackup(starTvBackup);
    expect(decodedTv.sourceFormat, 'startv');
    expect(decodedTv.profiles.length, 1);
    expect(decodedTv.profiles.first.entries.first.title, 'Гра престолів');
    expect(decodedTv.profiles.first.entries.first.status, WatchStatus.watching);
    expect(decodedTv.profiles.first.entries.first.userRating, 9);

    final encoded = BackupCodec.encodeStarFilmBackup(
      activeProfileId: 'main',
      profiles: [decodedTv.profiles.first.profile],
      entriesByProfile: {'main': decodedTv.profiles.first.entries},
      collectionsByProfile: const {},
      deletedByProfile: const {},
    );
    expect(encoded, isNot(contains('progressNote')));
    expect(encoded, isNot(contains('S2 E4')));
  });

  test('chunkOperations splits batches > 450 items and Drift repo enforces 4 profiles', () async {
    final chunks = chunkOperations(List<int>.generate(1000, (i) => i));
    expect(chunks.length, 3);
    expect(chunks[0].length, 450);
    expect(chunks[1].length, 450);
    expect(chunks[2].length, 100);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LibraryRepository(db);
    await repo.ensureMainProfile();
    await repo.createProfile('Друг 1');
    await repo.createProfile('Друг 2');
    await repo.createProfile('Друг 3');
    expect(
      () => repo.createProfile('Зайвий 5'),
      throwsA(isA<StateError>()),
    );
  });
}
