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

class FirebaseSyncAdapter {
  FirebaseSyncAdapter({DiagnosticsLog? log}) : _log = log;

  final DiagnosticsLog? _log;
  bool _initialized = false;

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
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);

      // Ensure root user doc exists.
      await userRef.set({
        'schemaVersion': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final profiles = await repo.listProfiles(includeDeleted: true);
      final writes = <({DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data})>[];

      for (final p in profiles) {
        final pRef = userRef.collection('profiles').doc(p.id);
        writes.add((
          ref: pRef,
          data: toFirestoreProfileDoc(p, serverTimestampSentinel: FieldValue.serverTimestamp()),
        ));

        final entries = await repo.listEntries(p.id, includeDeleted: true);
        for (final e in entries) {
          writes.add((
            ref: pRef.collection('library').doc(e.firestoreId),
            data: toFirestoreLibraryDoc(
              e,
              serverTimestampSentinel: FieldValue.serverTimestamp(),
            ),
          ));
        }

        final collections = await repo.listCollections(p.id, includeDeleted: true);
        for (final c in collections) {
          writes.add((
            ref: pRef.collection('collections').doc(c.id),
            data: toFirestoreCollectionDoc(
              c,
              serverTimestampSentinel: FieldValue.serverTimestamp(),
            ),
          ));
        }
      }

      var pushed = 0;
      for (final chunk in chunkOperations(writes, chunkSize: 450)) {
        final batch = db.batch();
        for (final op in chunk) {
          batch.set(op.ref, op.data, SetOptions(merge: true));
        }
        await batch.commit();
        pushed += chunk.length;
      }

      // Incremental pull using serverSyncedAt cursor (clock-skew safe)
      var pulled = 0;
      var maxServerMs = lastServerCursorMs;
      final cursorTs = Timestamp.fromMillisecondsSinceEpoch(lastServerCursorMs);
      final profilesSnap = await userRef.collection('profiles').get();
      final importedBundles = <ImportedProfileBundle>[];

      for (final pDoc in profilesSnap.docs) {
        final pData = pDoc.data();
        final pid = pDoc.id;
        if (!UserProfile.isValidId(pid)) continue;
        final pServerTs = _readServerMillis(pData['serverSyncedAt']);
        if (pServerTs > maxServerMs) maxServerMs = pServerTs;

        final profile = UserProfile(
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
        );

        final libQuery = pDoc.reference
            .collection('library')
            .where('serverSyncedAt', isGreaterThan: cursorTs);
        final libSnap = await libQuery.get();
        final pulledEntries = <LibraryEntry>[];
        for (final doc in libSnap.docs) {
          final data = doc.data();
          final sMs = _readServerMillis(data['serverSyncedAt']);
          if (sMs > maxServerMs) maxServerMs = sMs;
          pulledEntries.add(fromFirestoreLibraryDoc(
            profileId: pid,
            data: data,
            serverSyncedAtMs: sMs,
          ));
          pulled++;
        }

        final colSnap = await pDoc.reference
            .collection('collections')
            .where('serverSyncedAt', isGreaterThan: cursorTs)
            .get();
        final pulledCols = <UserCollection>[];
        for (final cDoc in colSnap.docs) {
          final cData = cDoc.data();
          final sMs = _readServerMillis(cData['serverSyncedAt']);
          if (sMs > maxServerMs) maxServerMs = sMs;
          pulledCols.add(UserCollection(
            id: cDoc.id,
            profileId: pid,
            title: (cData['title'] ?? '').toString(),
            mediaKeys: (cData['mediaKeys'] as List<dynamic>? ?? const [])
                .map((e) => e.toString())
                .where((k) => MediaKey.tryParse(k) != null)
                .toList(),
            clientUpdatedAt: (cData['clientUpdatedAt'] as num?)?.toInt() ?? 0,
            serverSyncedAt: sMs,
            deletedAt: (cData['deletedAt'] as num?)?.toInt(),
          ));
        }

        importedBundles.add(ImportedProfileBundle(
          profile: profile,
          entries: pulledEntries,
          collections: pulledCols,
          deletedTombstones: const {},
        ));
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
      await repo.clearAllLocalUserCloudState();
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

  int _readServerMillis(Object? value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is num) return value.toInt();
    return 0;
  }
}
