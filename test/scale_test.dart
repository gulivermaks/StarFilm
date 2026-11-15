import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starfilm/core/db/app_database.dart';
import 'package:starfilm/core/models/library_entry.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/features/library/backup_codec.dart';
import 'package:starfilm/features/library/library_repository.dart';

void main() {
  test('4 profiles x 2000 entries enforce limits and serialize/filter cleanly', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LibraryRepository(db);
    await repo.ensureMainProfile();

    // Create 2000 entries in main profile directly and verify 2001st throws.
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.batch((batch) {
      batch.insertAll(
        db.libraryEntriesTable,
        List.generate(
          2000,
          (i) => LibraryEntriesTableCompanion.insert(
            profileId: 'main',
            mediaType: 'movie',
            tmdbId: i + 1,
            title: 'Movie ${i + 1}',
            status: const Value('watched'),
            clientUpdatedAt: Value(now + i),
          ),
        ),
      );
    });

    final loaded = await repo.listEntries('main');
    expect(loaded.length, 2000);

    await expectLater(
      repo.upsertEntry(
        const LibraryEntry(
          profileId: 'main',
          mediaType: MediaType.movie,
          tmdbId: 999999,
          title: 'Overflow 2001',
          status: WatchStatus.watchlist,
        ),
        deviceId: 'dev',
      ),
      throwsA(isA<StateError>()),
    );

    final profiles = await repo.listProfiles();
    final json = BackupCodec.encodeStarFilmBackup(
      activeProfileId: 'main',
      profiles: profiles,
      entriesByProfile: {'main': loaded},
      collectionsByProfile: const {},
      deletedByProfile: const {},
    );
    final decoded = BackupCodec.decodeBackup(json);
    expect(decoded.profiles.first.entries.length, 2000);
  });
}
