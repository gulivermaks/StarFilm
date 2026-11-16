import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../../core/security/log_sanitizer.dart';
import '../library/backup_codec.dart';
import '../library/library_repository.dart';
import 'cloud_sync_models.dart';

class CloudAccountInfo {
  const CloudAccountInfo({required this.uid, required this.email});
  final String uid;
  final String email;
}

class _FirestoreCloudBackend implements CloudSyncBackend {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Object get serverTimestampSentinel => FieldValue.serverTimestamp();

  @override
  Future<void> ensureUserDoc(String uid) async {
    await _db.collection('users').doc(uid).set({
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> commitWrites(String uid, List<CloudWriteOp> writes) async {
    final userRef = _db.collection('users').doc(uid);
    for (final chunk in chunkOperations(writes, chunkSize: 450)) {
      final batch = _db.batch();
      for (final op in chunk) {
        final profileRef = userRef.collection('profiles').doc(op.profileId);
        final docRef = switch (op.entityType) {
          CloudEntityType.profile => profileRef,
          CloudEntityType.library => profileRef.collection('library').doc(op.docId),
          CloudEntityType.collection =>
            profileRef.collection('collections').doc(op.docId),
        };
        batch.set(docRef, op.data, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  @override
  Future<List<CloudPulledProfile>> fetchProfiles(String uid) async {
    final snap = await _db.collection('users').doc(uid).collection('profiles').get();
    final out = <CloudPulledProfile>[];
    for (final pDoc in snap.docs) {
      final pid = pDoc.id;
      if (!UserProfile.isValidId(pid)) continue;
      final pData = pDoc.data();
      final pServerTs = _readServerMillis(pData['serverSyncedAt']);
      out.add(
        CloudPulledProfile(
          serverSyncedAtMs: pServerTs,
          profile: UserProfile(
            id: pid,
            name: (pData['name'] ?? (pid == 'main' ? 'Головний' : pid)).toString(),
            preferences: ProfilePreferences.fromJson(
              pData['preferences'] is Map<String, dynamic>
                  ? pData['preferences'] as Map<String, dynamic>
                  : const {},
            ),
            clientUpdatedAt: (pData['clientUpdatedAt'] as num?)?.toInt() ?? 0,
            serverSyncedAt: pServerTs,
            deletedAt: (pData['deletedAt'] as num?)?.toInt(),
          ),
        ),
      );
    }
    return out;
  }

  @override
  Future<List<CloudPulledLibraryDoc>> fetchLibrarySince(
    String uid,
    String profileId,
    int lastServerCursorMs,
  ) async {
    final cursorTs = Timestamp.fromMillisecondsSinceEpoch(lastServerCursorMs);
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('profiles')
        .doc(profileId)
        .collection('library')
        .where('serverSyncedAt', isGreaterThan: cursorTs)
        .get();
    return snap.docs.map((doc) {
      final data = doc.data();
      final sMs = _readServerMillis(data['serverSyncedAt']);
      return CloudPulledLibraryDoc(
        docId: doc.id,
        serverSyncedAtMs: sMs,
        entry: fromFirestoreLibraryDoc(
          profileId: profileId,
          data: data,
          serverSyncedAtMs: sMs,
        ),
      );
    }).toList();
  }

  @override
  Future<List<CloudPulledCollectionDoc>> fetchCollectionsSince(
    String uid,
    String profileId,
    int lastServerCursorMs,
  ) async {
    final cursorTs = Timestamp.fromMillisecondsSinceEpoch(lastServerCursorMs);
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('profiles')
        .doc(profileId)
        .collection('collections')
        .where('serverSyncedAt', isGreaterThan: cursorTs)
        .get();
    return snap.docs.map((cDoc) {
      final cData = cDoc.data();
      final sMs = _readServerMillis(cData['serverSyncedAt']);
      return CloudPulledCollectionDoc(
        serverSyncedAtMs: sMs,
        collection: UserCollection(
          id: cDoc.id,
          profileId: profileId,
          title: (cData['title'] ?? '').toString(),
          mediaKeys: (cData['mediaKeys'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .where((k) => MediaKey.tryParse(k) != null)
              .toList(),
          clientUpdatedAt: (cData['clientUpdatedAt'] as num?)?.toInt() ?? 0,
          serverSyncedAt: sMs,
          deletedAt: (cData['deletedAt'] as num?)?.toInt(),
        ),
      );
    }).toList();
  }

  static int _readServerMillis(Object? value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is num) return value.toInt();
    return 0;
  }
}

class FirebaseSyncAdapter {
  FirebaseSyncAdapter({DiagnosticsLog? log, CloudSyncBackend? backend})
      : _log = log,
        _backend = backend ?? _FirestoreCloudBackend(),
        _initialized = backend != null;

  final DiagnosticsLog? _log;
  final CloudSyncBackend _backend;
  bool _initialized;

  bool get isConfigured => _initialized;

  Future<bool> tryInitialize() async {
    if (_initialized) return true;
    try {
      await Firebase.initializeApp();
      _initialized = true;
      return true;
    } catch (e) {
      _log?.info('Firebase not configured yet (local mode active): $e');
      _initialized = false;
      return false;
    }
  }

  CloudAccountInfo? currentUser() {
    if (!_initialized) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return CloudAccountInfo(uid: user.uid, email: user.email ?? '');
  }

  Future<CloudAccountInfo?> signInWithGoogle() async {
    if (!_initialized) return null;
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await FirebaseAuth.instance.signInWithCredential(cred);
    final user = result.user;
    if (user == null) return null;
    return CloudAccountInfo(uid: user.uid, email: user.email ?? '');
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  Future<SyncResultSummary> sync({
    required LibraryRepository repo,
    required String uid,
    required String deviceId,
    required int lastServerCursorMs,
    required void Function(int nextCursorMs) onSaveCursor,
  }) async {
    if (!_initialized || uid.isEmpty) {
      return const SyncResultSummary(state: SyncStatusState.notConfigured);
    }

    try {
      // 1. Incremental push strictly from pending_changes_table.
      final pendingRows = await repo.listPendingChanges();
      final processedIds = [for (final row in pendingRows) row.id];
      final dedupSeen = <String>{};
      final writes = <CloudWriteOp>[];
      final pushedProfiles = <String, int>{};
      final pushedLibrary = <String, int>{};
      final pushedCollections = <String, int>{};
      final sentinel = _backend.serverTimestampSentinel;

      for (final row in pendingRows) {
        final dedupKey = '${row.entityType}|${row.profileId}|${row.entityKey}';
        if (!dedupSeen.add(dedupKey)) continue;

        switch (row.entityType) {
          case 'profile':
            if (!UserProfile.isValidId(row.profileId)) break;
            final profile = await repo.findProfile(row.profileId);
            if (profile == null) break;
            pushedProfiles[profile.id] = profile.clientUpdatedAt;
            writes.add(
              CloudWriteOp(
                entityType: CloudEntityType.profile,
                profileId: profile.id,
                docId: profile.id,
                clientUpdatedAt: profile.clientUpdatedAt,
                data: toFirestoreProfileDoc(
                  profile,
                  serverTimestampSentinel: sentinel,
                ),
              ),
            );
          case 'library':
            final parsedKey = _parseFirestoreMediaId(row.entityKey);
            if (parsedKey == null) break;
            final entry = await repo.findEntry(row.profileId, parsedKey);
            if (entry == null) break;
            pushedLibrary['${entry.profileId}|${entry.firestoreId}'] =
                entry.clientUpdatedAt;
            writes.add(
              CloudWriteOp(
                entityType: CloudEntityType.library,
                profileId: entry.profileId,
                docId: entry.firestoreId,
                clientUpdatedAt: entry.clientUpdatedAt,
                data: toFirestoreLibraryDoc(
                  entry,
                  serverTimestampSentinel: sentinel,
                ),
              ),
            );
          case 'collection':
            final col = await repo.findCollection(row.profileId, row.entityKey);
            if (col == null) break;
            pushedCollections['${col.profileId}|${col.id}'] = col.clientUpdatedAt;
            writes.add(
              CloudWriteOp(
                entityType: CloudEntityType.collection,
                profileId: col.profileId,
                docId: col.id,
                clientUpdatedAt: col.clientUpdatedAt,
                data: toFirestoreCollectionDoc(
                  col,
                  serverTimestampSentinel: sentinel,
                ),
              ),
            );
        }
      }

      if (writes.isNotEmpty || lastServerCursorMs == 0) {
        await _backend.ensureUserDoc(uid);
      }

      var pushed = 0;
      if (writes.isNotEmpty) {
        await _backend.commitWrites(uid, writes);
        pushed = writes.length;
      }

      // Delete only the pending rows captured at the start of this sync pass.
      if (processedIds.isNotEmpty) {
        await repo.deletePendingChangesByIds(processedIds);
      }

      // 2. Incremental pull using serverSyncedAt cursor (skipping our own fresh echoes).
      var pulled = 0;
      var maxServerMs = lastServerCursorMs;
      final localProfileIds = {
        for (final p in await repo.listProfiles(includeDeleted: true)) p.id,
      };
      final cloudProfiles = await _backend.fetchProfiles(uid);
      final importedBundles = <ImportedProfileBundle>[];

      for (final pDoc in cloudProfiles) {
        final pid = pDoc.profile.id;
        if (pDoc.serverSyncedAtMs > maxServerMs) {
          maxServerMs = pDoc.serverSyncedAtMs;
        }
        final isOwnProfileEcho = pushedProfiles[pid] == pDoc.profile.clientUpdatedAt;
        final isNewOrUpdatedProfile = !localProfileIds.contains(pid) ||
            (!isOwnProfileEcho && pDoc.serverSyncedAtMs > lastServerCursorMs);

        final libDocs = await _backend.fetchLibrarySince(uid, pid, lastServerCursorMs);
        final pulledEntries = <LibraryEntry>[];
        for (final d in libDocs) {
          if (d.serverSyncedAtMs > maxServerMs) {
            maxServerMs = d.serverSyncedAtMs;
          }
          final sig = '$pid|${d.docId}';
          final isOwnEcho = d.entry.updatedByDevice == deviceId &&
              pushedLibrary[sig] == d.entry.clientUpdatedAt;
          if (isOwnEcho) continue;
          pulledEntries.add(d.entry);
          pulled++;
        }

        final colDocs =
            await _backend.fetchCollectionsSince(uid, pid, lastServerCursorMs);
        final pulledCols = <UserCollection>[];
        for (final c in colDocs) {
          if (c.serverSyncedAtMs > maxServerMs) {
            maxServerMs = c.serverSyncedAtMs;
          }
          final sig = '$pid|${c.collection.id}';
          final isOwnEcho = pushedCollections[sig] == c.collection.clientUpdatedAt;
          if (isOwnEcho) continue;
          pulledCols.add(c.collection);
          pulled++;
        }

        if (isNewOrUpdatedProfile) {
          pulled++;
        }

        if (isNewOrUpdatedProfile ||
            pulledEntries.isNotEmpty ||
            pulledCols.isNotEmpty) {
          importedBundles.add(
            ImportedProfileBundle(
              profile: pDoc.profile,
              entries: pulledEntries,
              collections: pulledCols,
              deletedTombstones: const {},
            ),
          );
        }
      }

      if (importedBundles.isNotEmpty) {
        await repo.mergeImportedBundle(
          BackupBundle(
            sourceFormat: 'starfilm',
            activeProfileId: 'main',
            profiles: importedBundles,
          ),
          deviceId: deviceId,
          accountUid: uid,
          queueSync: false,
        );
      }

      await repo.pruneOldTombstones(retentionDays: 90);

      if (maxServerMs > lastServerCursorMs) {
        onSaveCursor(maxServerMs);
      }

      return SyncResultSummary(
        state: SyncStatusState.synced,
        pushedCount: pushed,
        pulledCount: pulled,
      );
    } on FirebaseException catch (e) {
      _log?.warn('Firestore sync error (${e.code}): ${e.message}');
      if (e.code == 'resource-exhausted' || e.code == 'unavailable') {
        return SyncResultSummary(
          state: SyncStatusState.quotaExceeded,
          message: e.code,
        );
      }
      return SyncResultSummary(state: SyncStatusState.error, message: e.code);
    } catch (e) {
      _log?.error('Cloud sync failed: $e');
      return SyncResultSummary(state: SyncStatusState.error, message: '$e');
    }
  }

  static MediaKey? _parseFirestoreMediaId(String firestoreId) {
    final idx = firestoreId.indexOf('_');
    if (idx <= 0 || idx >= firestoreId.length - 1) return null;
    final typeRaw = firestoreId.substring(0, idx);
    final idRaw = int.tryParse(firestoreId.substring(idx + 1));
    if (idRaw == null || idRaw <= 0) return null;
    if (typeRaw != 'movie' && typeRaw != 'tv') return null;
    return MediaKey(MediaType.fromWire(typeRaw), idRaw);
  }
}
