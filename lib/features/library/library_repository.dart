import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import 'backup_codec.dart';

class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  Future<void> ensureMainProfile({int? nowMs}) async {
    final existing = await (_db.select(_db.profilesTable)
          ..where((t) => t.id.equals('main')))
        .getSingleOrNull();
    if (existing != null) return;
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.profilesTable).insert(
          ProfilesTableCompanion.insert(
            id: 'main',
            name: 'Головний',
            clientUpdatedAt: Value(ts),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<List<UserProfile>> listProfiles({bool includeDeleted = false}) async {
    await ensureMainProfile();
    final rows = await _db.select(_db.profilesTable).get();
    final out = <UserProfile>[];
    for (final r in rows) {
      if (!includeDeleted && r.deletedAt != null && r.deletedAt! > 0) continue;
      out.add(UserProfile(
        id: r.id,
        name: r.name,
        preferences: ProfilePreferences.fromJson({
          'excludedGenres': AppDatabase.decodeIntList(r.excludedGenresJson),
          'favoriteGenres': AppDatabase.decodeIntList(r.favoriteGenresJson),
          'contentLanguage': r.contentLanguage,
          'personalized': r.personalized,
        }),
        clientUpdatedAt: r.clientUpdatedAt,
        serverSyncedAt: r.serverSyncedAt,
        deletedAt: r.deletedAt,
      ));
    }
    out.sort((a, b) {
      if (a.isMain) return -1;
      if (b.isMain) return 1;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  Future<UserProfile> createProfile(
    String name, {
    String accountUid = '',
    int? nowMs,
  }) async {
    final active = await listProfiles();
    if (active.length >= UserProfile.maxProfiles) {
      throw StateError('Maximum ${UserProfile.maxProfiles} profiles allowed');
    }
    final rng = Random.secure();
    final suffix = List.generate(8, (_) => rng.nextInt(36).toRadixString(36)).join();
    final id = 'p_$suffix';
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final profile = UserProfile(id: id, name: name, clientUpdatedAt: ts);
    await saveProfile(profile, accountUid: accountUid);
    return profile;
  }

  Future<void> saveProfile(
    UserProfile profile, {
    String accountUid = '',
    bool queueSync = true,
  }) async {
    await _db.into(_db.profilesTable).insertOnConflictUpdate(
          ProfilesTableCompanion(
            id: Value(profile.id),
            name: Value(profile.name),
            excludedGenresJson:
                Value(jsonEncode(profile.preferences.excludedGenres)),
            favoriteGenresJson:
                Value(jsonEncode(profile.preferences.favoriteGenres)),
            contentLanguage: Value(profile.preferences.contentLanguage),
            personalized: Value(profile.preferences.personalized),
            clientUpdatedAt: Value(profile.clientUpdatedAt),
            serverSyncedAt: Value(profile.serverSyncedAt),
            deletedAt: Value(profile.deletedAt),
          ),
        );
    if (queueSync) {
      await _enqueueChange(
        accountUid: accountUid,
        entityType: 'profile',
        profileId: profile.id,
        entityKey: profile.id,
        nowMs: profile.clientUpdatedAt,
      );
    }
  }

  Future<void> deleteProfile(
    String profileId, {
    String accountUid = '',
    int? nowMs,
  }) async {
    if (profileId == 'main') {
      throw ArgumentError('Main profile cannot be deleted');
    }
    final profiles = await listProfiles(includeDeleted: true);
    final target = profiles.where((p) => p.id == profileId).firstOrNull;
    if (target == null) return;
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await saveProfile(
      target.copyWith(clientUpdatedAt: ts, deletedAt: ts),
      accountUid: accountUid,
    );
  }

  Future<List<LibraryEntry>> listEntries(
    String profileId, {
    bool includeDeleted = false,
  }) async {
    final query = _db.select(_db.libraryEntriesTable)
      ..where((t) => t.profileId.equals(profileId));
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull() | t.deletedAt.equals(0));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.clientUpdatedAt)]);
    final rows = await query.get();
    return rows.map(_rowToEntry).toList();
  }

  Future<LibraryEntry?> findEntry(String profileId, MediaKey key) async {
    final row = await (_db.select(_db.libraryEntriesTable)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.mediaType.equals(key.mediaType.wireValue) &
              t.tmdbId.equals(key.tmdbId)))
        .getSingleOrNull();
    return row == null ? null : _rowToEntry(row);
  }

  Future<LibraryEntry> upsertEntry(
    LibraryEntry incoming, {
    required String deviceId,
    String accountUid = '',
    int? nowMs,
    bool queueSync = true,
  }) async {
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await findEntry(incoming.profileId, incoming.mediaKey);

    if (existing == null) {
      final liveCount = (await listEntries(incoming.profileId)).length;
      if (liveCount >= UserProfile.maxEntriesPerProfile) {
        throw StateError('Profile library limit (${UserProfile.maxEntriesPerProfile}) reached');
      }
    }

    final normalized = incoming.normalized(nowMs: ts, deviceId: deviceId);
    final toSave = existing == null
        ? normalized
        : LibraryEntry(
            profileId: normalized.profileId,
            mediaType: normalized.mediaType,
            tmdbId: normalized.tmdbId,
            title: normalized.title.isNotEmpty ? normalized.title : existing.title,
            originalTitle: normalized.originalTitle.isNotEmpty
                ? normalized.originalTitle
                : existing.originalTitle,
            year: normalized.year ?? existing.year,
            posterPath: normalized.posterPath.isNotEmpty
                ? normalized.posterPath
                : existing.posterPath,
            genreIds: normalized.genreIds.isNotEmpty
                ? normalized.genreIds
                : existing.genreIds,
            tmdbRating: normalized.tmdbRating ?? existing.tmdbRating,
            runtimeMinutes: normalized.runtimeMinutes ?? existing.runtimeMinutes,
            status: normalized.status,
            userRating: normalized.userRating,
            sentiment: normalized.sentiment,
            statusChangedAt: normalized.status != existing.status
                ? ts
                : existing.statusChangedAt,
            ratingChangedAt: normalized.userRating != existing.userRating
                ? ts
                : existing.ratingChangedAt,
            sentimentChangedAt: normalized.sentiment != existing.sentiment
                ? ts
                : existing.sentimentChangedAt,
            clientUpdatedAt: ts,
            serverSyncedAt: existing.serverSyncedAt,
            deletedAt: null,
            updatedByDevice: deviceId,
          );

    await _writeEntryRow(toSave);
    if (queueSync) {
      await _enqueueChange(
        accountUid: accountUid,
        entityType: 'library',
        profileId: toSave.profileId,
        entityKey: toSave.firestoreId,
        nowMs: ts,
      );
    }
    return toSave;
  }

  Future<void> softDeleteEntry(
    String profileId,
    MediaKey key, {
    required String deviceId,
    String accountUid = '',
    int? nowMs,
    bool queueSync = true,
  }) async {
    final existing = await findEntry(profileId, key);
    if (existing == null) return;
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final tombstone = LibraryEntry(
      profileId: profileId,
      mediaType: key.mediaType,
      tmdbId: key.tmdbId,
      title: existing.title,
      originalTitle: existing.originalTitle,
      year: existing.year,
      posterPath: existing.posterPath,
      genreIds: existing.genreIds,
      tmdbRating: existing.tmdbRating,
      runtimeMinutes: existing.runtimeMinutes,
      status: WatchStatus.none,
      userRating: null,
      sentiment: Sentiment.neutral,
      statusChangedAt: ts,
      ratingChangedAt: ts,
      sentimentChangedAt: ts,
      clientUpdatedAt: ts,
      serverSyncedAt: existing.serverSyncedAt,
      deletedAt: ts,
      updatedByDevice: deviceId,
    );
    await _writeEntryRow(tombstone);
    if (queueSync) {
      await _enqueueChange(
        accountUid: accountUid,
        entityType: 'library',
        profileId: profileId,
        entityKey: tombstone.firestoreId,
        nowMs: ts,
      );
    }
  }

  /// Applies an incoming sync/backup bundle using per-field timestamp merge.
  Future<int> mergeImportedBundle(
    BackupBundle bundle, {
    required String deviceId,
    String accountUid = '',
    bool queueSync = true,
  }) async {
    var mergedCount = 0;
    for (final pBundle in bundle.profiles) {
      final profiles = await listProfiles(includeDeleted: true);
      final existingProfile =
          profiles.where((p) => p.id == pBundle.profile.id).firstOrNull;
      if (existingProfile == null) {
        final activeCount = profiles.where((p) => !p.isDeleted).length;
        if (activeCount < UserProfile.maxProfiles) {
          await saveProfile(pBundle.profile, accountUid: accountUid, queueSync: queueSync);
        } else {
          continue;
        }
      } else if (pBundle.profile.clientUpdatedAt > existingProfile.clientUpdatedAt) {
        await saveProfile(pBundle.profile, accountUid: accountUid, queueSync: queueSync);
      }

      for (final incoming in pBundle.entries) {
        final existing = await findEntry(pBundle.profile.id, incoming.mediaKey);
        final merged = existing == null
            ? incoming.normalized(nowMs: incoming.clientUpdatedAt, deviceId: deviceId)
            : LibraryEntry.merge(existing, incoming);
        await _writeEntryRow(merged);
        if (queueSync) {
          await _enqueueChange(
            accountUid: accountUid,
            entityType: 'library',
            profileId: merged.profileId,
            entityKey: merged.firestoreId,
            nowMs: merged.clientUpdatedAt,
          );
        }
        mergedCount++;
      }

      // Apply incoming deletion tombstones
      for (final entry in pBundle.deletedTombstones.entries) {
        final parsed = MediaKey.tryParse(entry.key);
        if (parsed == null) continue;
        final existing = await findEntry(pBundle.profile.id, parsed);
        if (existing != null && entry.value > existing.clientUpdatedAt) {
          await softDeleteEntry(
            pBundle.profile.id,
            parsed,
            deviceId: deviceId,
            accountUid: accountUid,
            nowMs: entry.value,
            queueSync: queueSync,
          );
        }
      }

      // Merge collections
      for (final col in pBundle.collections) {
        await saveCollection(col, accountUid: accountUid, queueSync: queueSync);
      }
    }
    return mergedCount;
  }

  Future<List<UserCollection>> listCollections(
    String profileId, {
    bool includeDeleted = false,
  }) async {
    final query = _db.select(_db.collectionsTable)
      ..where((t) => t.profileId.equals(profileId));
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull() | t.deletedAt.equals(0));
    }
    final rows = await query.get();
    return rows
        .map((r) => UserCollection(
              id: r.id,
              profileId: r.profileId,
              title: r.title,
              mediaKeys: AppDatabase.decodeStringList(r.mediaKeysJson),
              clientUpdatedAt: r.clientUpdatedAt,
              serverSyncedAt: r.serverSyncedAt,
              deletedAt: r.deletedAt,
            ))
        .toList();
  }

  Future<void> saveCollection(
    UserCollection col, {
    String accountUid = '',
    bool queueSync = true,
  }) async {
    await _db.into(_db.collectionsTable).insertOnConflictUpdate(
          CollectionsTableCompanion(
            id: Value(col.id),
            profileId: Value(col.profileId),
            title: Value(col.title.length > 60 ? col.title.substring(0, 60) : col.title),
            mediaKeysJson: Value(jsonEncode(col.mediaKeys.take(500).toList())),
            clientUpdatedAt: Value(col.clientUpdatedAt),
            serverSyncedAt: Value(col.serverSyncedAt),
            deletedAt: Value(col.deletedAt),
          ),
        );
    if (queueSync) {
      await _enqueueChange(
        accountUid: accountUid,
        entityType: 'collection',
        profileId: col.profileId,
        entityKey: col.id,
        nowMs: col.clientUpdatedAt,
      );
    }
  }

  Future<int> pendingChangesCount({String? accountUid}) async {
    final query = _db.select(_db.pendingChangesTable);
    if (accountUid != null) {
      query.where((t) => t.accountUid.equals(accountUid));
    }
    final rows = await query.get();
    return rows.length;
  }

  Future<void> clearAllLocalUserCloudState() async {
    await _db.delete(_db.pendingChangesTable).go();
  }

  Future<void> _writeEntryRow(LibraryEntry entry) async {
    await _db.into(_db.libraryEntriesTable).insertOnConflictUpdate(
          LibraryEntriesTableCompanion(
            profileId: Value(entry.profileId),
            mediaType: Value(entry.mediaType.wireValue),
            tmdbId: Value(entry.tmdbId),
            title: Value(entry.title),
            originalTitle: Value(entry.originalTitle),
            year: Value(entry.year),
            posterPath: Value(entry.posterPath),
            genreIdsJson: Value(jsonEncode(entry.genreIds)),
            tmdbRating: Value(entry.tmdbRating),
            runtimeMinutes: Value(entry.runtimeMinutes),
            status: Value(entry.status.wireValue),
            userRating: Value(entry.userRating),
            sentiment: Value(entry.sentiment.wireValue),
            statusChangedAt: Value(entry.statusChangedAt),
            ratingChangedAt: Value(entry.ratingChangedAt),
            sentimentChangedAt: Value(entry.sentimentChangedAt),
            clientUpdatedAt: Value(entry.clientUpdatedAt),
            serverSyncedAt: Value(entry.serverSyncedAt),
            deletedAt: Value(entry.deletedAt),
            updatedByDevice: Value(entry.updatedByDevice),
          ),
        );
  }

  Future<void> _enqueueChange({
    required String accountUid,
    required String entityType,
    required String profileId,
    required String entityKey,
    required int nowMs,
  }) async {
    await _db.into(_db.pendingChangesTable).insert(
          PendingChangesTableCompanion.insert(
            accountUid: Value(accountUid),
            entityType: entityType,
            profileId: profileId,
            entityKey: entityKey,
            createdAt: nowMs,
          ),
        );
  }

  LibraryEntry _rowToEntry(LibraryEntriesTableData row) {
    return LibraryEntry(
      profileId: row.profileId,
      mediaType: MediaType.fromWire(row.mediaType),
      tmdbId: row.tmdbId,
      title: row.title,
      originalTitle: row.originalTitle,
      year: row.year,
      posterPath: row.posterPath,
      genreIds: AppDatabase.decodeIntList(row.genreIdsJson),
      tmdbRating: row.tmdbRating,
      runtimeMinutes: row.runtimeMinutes,
      status: WatchStatus.fromWire(row.status),
      userRating: row.userRating,
      sentiment: Sentiment.fromWire(row.sentiment),
      statusChangedAt: row.statusChangedAt,
      ratingChangedAt: row.ratingChangedAt,
      sentimentChangedAt: row.sentimentChangedAt,
      clientUpdatedAt: row.clientUpdatedAt,
      serverSyncedAt: row.serverSyncedAt,
      deletedAt: row.deletedAt,
      updatedByDevice: row.updatedByDevice,
    );
  }
}
