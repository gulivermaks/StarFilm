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

    // Newer explicit move to watchlist clears older rating instead of snapping back to watched
    const ratedWatched = LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Fight Club',
      status: WatchStatus.watched,
      userRating: 9,
      statusChangedAt: 1000,
      ratingChangedAt: 1000,
      sentimentChangedAt: 1000,
      clientUpdatedAt: 1000,
    );
    const movedToWatchlist = LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Fight Club',
      status: WatchStatus.watchlist,
      userRating: 9,
      statusChangedAt: 2000,
      ratingChangedAt: 1000,
      sentimentChangedAt: 1000,
      clientUpdatedAt: 2000,
    );
    final mergedToWatchlist = LibraryEntry.merge(ratedWatched, movedToWatchlist);
    expect(mergedToWatchlist.status, WatchStatus.watchlist);
    expect(mergedToWatchlist.userRating, isNull);
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

  test('replaceFromBackupBundle restores exact snapshot and soft-deletes newer entries', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LibraryRepository(db);
    await repo.ensureMainProfile(nowMs: 100);

    // Initial state at t=1000 exported to backup
    await repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 27205,
        title: 'Початок',
        status: WatchStatus.watchlist,
      ),
      deviceId: 'dev-1',
      nowMs: 1000,
    );
    final snapshotJson = BackupCodec.encodeStarFilmBackup(
      activeProfileId: 'main',
      profiles: await repo.listProfiles(),
      entriesByProfile: {'main': await repo.listEntries('main')},
      collectionsByProfile: const {},
      deletedByProfile: const {},
    );

    // Later edits at t=2000: modify existing entry, add a new entry, add a profile & collection
    await repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 27205,
        title: 'Початок',
        status: WatchStatus.watched,
        userRating: 10,
      ),
      deviceId: 'dev-1',
      nowMs: 2000,
    );
    await repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 603,
        title: 'Матриця',
        status: WatchStatus.watched,
        userRating: 9,
      ),
      deviceId: 'dev-1',
      nowMs: 2000,
    );
    final extraProfile = await repo.createProfile('Гість', nowMs: 2000);
    await repo.saveCollection(
      const UserCollection(
        id: 'col_extra',
        profileId: 'main',
        title: 'Нове',
        mediaKeys: ['movie:603'],
        clientUpdatedAt: 2000,
      ),
    );

    final bundle = BackupCodec.decodeBackup(snapshotJson);

    // Merge mode keeps newer edits and extra entry
    await repo.mergeImportedBundle(bundle, deviceId: 'dev-1');
    var mainEntries = await repo.listEntries('main');
    expect(mainEntries.length, 2);
    expect(
      mainEntries.firstWhere((e) => e.tmdbId == 27205).status,
      WatchStatus.watched,
    );

    // Replace mode restores snapshot verbatim and soft-deletes newer additions
    final restoredCount = await repo.replaceFromBackupBundle(
      bundle,
      deviceId: 'dev-1',
      nowMs: 3000,
    );
    expect(restoredCount, 1);

    mainEntries = await repo.listEntries('main');
    expect(mainEntries.length, 1);
    expect(mainEntries.first.tmdbId, 27205);
    expect(mainEntries.first.status, WatchStatus.watchlist);
    expect(mainEntries.first.userRating, isNull);

    final allWithTombstones = await repo.listEntries('main', includeDeleted: true);
    final deletedMatrix = allWithTombstones.where((e) => e.tmdbId == 603).single;
    expect(deletedMatrix.isDeleted, isTrue);

    final activeProfiles = await repo.listProfiles();
    expect(activeProfiles.map((p) => p.id), ['main']);
    final allProfiles = await repo.listProfiles(includeDeleted: true);
    expect(allProfiles.firstWhere((p) => p.id == extraProfile.id).isDeleted, isTrue);

    expect(await repo.listCollections('main'), isEmpty);
  });
}
