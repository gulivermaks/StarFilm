import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starfilm/app/app_state.dart';
import 'package:starfilm/app/l10n.dart';
import 'package:starfilm/core/db/app_database.dart';
import 'package:starfilm/core/models/library_entry.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/core/models/profile.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
import 'package:starfilm/core/security/secret_store.dart';
import 'package:starfilm/features/cloud_sync/cloud_sync_models.dart';
import 'package:starfilm/features/cloud_sync/firebase_sync_adapter.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/discovery_tab.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/library/backup_codec.dart';
import 'package:starfilm/features/library/library_repository.dart';
import 'package:starfilm/features/onboarding/onboarding_screen.dart';
import 'package:starfilm/features/search/tmdb_client.dart';
import 'package:starfilm/features/settings/ota_updater.dart';
import 'package:starfilm/features/startv/startv_client.dart';

class _InMemorySecretStore extends SecretStore {
  _InMemorySecretStore({String initialTmdb = '', String initialGemini = ''})
      : _tmdb = initialTmdb,
        _gemini = initialGemini;

  String _tmdb;
  String _gemini;
  String _kp = '';

  @override
  Future<String> getTmdbKey() async => _tmdb;

  @override
  Future<void> setTmdbKey(String value) async => _tmdb = value.trim();

  @override
  Future<String> getGeminiKey() async => _gemini;

  @override
  Future<void> setGeminiKey(String value) async => _gemini = value.trim();

  @override
  Future<String> getKinopoiskKey() async => _kp;

  @override
  Future<void> setKinopoiskKey(String value) async => _kp = value.trim();

  @override
  Future<String> getOrCreateDeviceId() async => 'device_stage1_test';
}

class _FakeCloudBackend implements CloudSyncBackend {
  final Map<String, Map<String, UserProfile>> profilesByUid = {};
  final Map<String, Map<String, Map<String, LibraryEntry>>> entriesByUidProfile = {};
  final Map<String, Map<String, Map<String, UserCollection>>> colsByUidProfile = {};
  int serverClock = 100000;
  int commitCalls = 0;
  int totalOpsCommitted = 0;
  Future<void> Function()? onBeforeCommit;

  @override
  Object get serverTimestampSentinel => 'SERVER_TS';

  @override
  Future<void> ensureUserDoc(String uid) async {
    profilesByUid.putIfAbsent(uid, () => {});
    entriesByUidProfile.putIfAbsent(uid, () => {});
    colsByUidProfile.putIfAbsent(uid, () => {});
  }

  @override
  Future<void> commitWrites(String uid, List<CloudWriteOp> writes) async {
    if (onBeforeCommit != null) {
      await onBeforeCommit!();
    }
    commitCalls++;
    totalOpsCommitted += writes.length;
    await ensureUserDoc(uid);
    for (final op in writes) {
      serverClock += 100;
      switch (op.entityType) {
        case CloudEntityType.profile:
          final prefs = ProfilePreferences.fromJson(
            (op.data['preferences'] as Map<String, dynamic>?) ?? const {},
          );
          profilesByUid[uid]![op.profileId] = UserProfile(
            id: op.profileId,
            name: (op.data['name'] ?? op.profileId).toString(),
            preferences: prefs,
            clientUpdatedAt: (op.data['clientUpdatedAt'] as num?)?.toInt() ?? 0,
            serverSyncedAt: serverClock,
            deletedAt: (op.data['deletedAt'] as num?)?.toInt(),
          );
        case CloudEntityType.library:
          final map = entriesByUidProfile[uid]!.putIfAbsent(op.profileId, () => {});
          map[op.docId] = fromFirestoreLibraryDoc(
            profileId: op.profileId,
            data: op.data,
            serverSyncedAtMs: serverClock,
          );
        case CloudEntityType.collection:
          final map = colsByUidProfile[uid]!.putIfAbsent(op.profileId, () => {});
          map[op.docId] = UserCollection(
            id: op.docId,
            profileId: op.profileId,
            title: (op.data['title'] ?? '').toString(),
            mediaKeys: (op.data['mediaKeys'] as List<dynamic>? ?? const [])
                .map((e) => e.toString())
                .toList(),
            clientUpdatedAt: (op.data['clientUpdatedAt'] as num?)?.toInt() ?? 0,
            serverSyncedAt: serverClock,
            deletedAt: (op.data['deletedAt'] as num?)?.toInt(),
          );
      }
    }
  }

  @override
  Future<List<CloudPulledProfile>> fetchProfiles(String uid) async {
    final map = profilesByUid[uid] ?? const {};
    return [
      for (final p in map.values)
        CloudPulledProfile(profile: p, serverSyncedAtMs: p.serverSyncedAt),
    ];
  }

  @override
  Future<List<CloudPulledLibraryDoc>> fetchLibrarySince(
    String uid,
    String profileId,
    int lastServerCursorMs,
  ) async {
    final map = entriesByUidProfile[uid]?[profileId] ?? const {};
    return [
      for (final e in map.entries)
        if (e.value.serverSyncedAt > lastServerCursorMs)
          CloudPulledLibraryDoc(
            docId: e.key,
            entry: e.value,
            serverSyncedAtMs: e.value.serverSyncedAt,
          ),
    ];
  }

  @override
  Future<List<CloudPulledCollectionDoc>> fetchCollectionsSince(
    String uid,
    String profileId,
    int lastServerCursorMs,
  ) async {
    final map = colsByUidProfile[uid]?[profileId] ?? const {};
    return [
      for (final c in map.values)
        if (c.serverSyncedAt > lastServerCursorMs)
          CloudPulledCollectionDoc(
            collection: c,
            serverSyncedAtMs: c.serverSyncedAt,
          ),
    ];
  }
}

class _ControllableFirebaseSyncAdapter extends FirebaseSyncAdapter {
  _ControllableFirebaseSyncAdapter({
    required super.log,
    required CloudSyncBackend backend,
  }) : super(backend: backend);

  CloudAccountInfo? account;
  bool signedOutCalled = false;

  @override
  CloudAccountInfo? currentUser() => account;

  @override
  Future<CloudAccountInfo?> signInWithGoogle() async => account;

  @override
  Future<void> signOut() async {
    signedOutCalled = true;
    account = null;
  }
}

class _CorruptedStorage extends FlutterSecureStorage {
  const _CorruptedStorage();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw PlatformException(code: 'BadPaddingException', message: 'Keystore changed');
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
}

AppServices _makeStage1Services({
  required AppDatabase db,
  required MockClient mockHttp,
  required _FakeCloudBackend cloudBackend,
  required _ControllableFirebaseSyncAdapter syncAdapter,
  SecretStore? secrets,
}) {
  final log = DiagnosticsLog();
  final client = StarFilmHttpClient(log: log, client: mockHttp);
  final tmdb = TmdbClient(client, log: log);
  final gemini = GeminiClient(client);
  return AppServices(
    log: log,
    http: client,
    db: db,
    repo: LibraryRepository(db),
    secrets: secrets ?? _InMemorySecretStore(initialTmdb: 'TMDB_OK'),
    tmdb: tmdb,
    gemini: gemini,
    discovery: DiscoveryService(gemini: gemini, tmdb: tmdb, log: log),
    starTv: StarTvClient(client),
    updater: OtaUpdater(client),
    firebaseSync: syncAdapter,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Incremental sync pushes only pending items, skips own echoes, and keeps concurrent queue',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LibraryRepository(db);
    await repo.ensureMainProfile(nowMs: 1000);

    final backend = _FakeCloudBackend();
    final adapter = _ControllableFirebaseSyncAdapter(
      log: DiagnosticsLog(),
      backend: backend,
    )..account = const CloudAccountInfo(uid: 'uid_a', email: 'a@example.com');

    // Seed synced baseline on both client and cloud ('main' + 3 entries),
    // clear initial main-profile queue, then make 1 real pending edit.
    backend.profilesByUid['uid_a'] = {
      'main': UserProfile(
        id: 'main',
        name: 'Головний',
        clientUpdatedAt: 1000,
        serverSyncedAt: 1000,
      ),
    };
    await repo.clearPendingChanges();
    for (final id in [10, 20, 30]) {
      await repo.upsertEntry(
        LibraryEntry(
          profileId: 'main',
          mediaType: MediaType.movie,
          tmdbId: id,
          title: 'Movie $id',
          status: WatchStatus.watched,
          userRating: 8,
        ),
        deviceId: 'dev1',
        nowMs: 1000 + id,
        queueSync: false,
      );
    }
    await repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 40,
        title: 'Newly Rated',
        status: WatchStatus.watched,
        userRating: 9,
      ),
      deviceId: 'dev1',
      accountUid: 'uid_a',
      nowMs: 2000,
      queueSync: true,
    );

    // Simulate a concurrent edit made by the user WHILE commitWrites is running.
    var injectedConcurrent = false;
    backend.onBeforeCommit = () async {
      if (!injectedConcurrent) {
        injectedConcurrent = true;
        await repo.upsertEntry(
          const LibraryEntry(
            profileId: 'main',
            mediaType: MediaType.movie,
            tmdbId: 50,
            title: 'Concurrent Edit',
            status: WatchStatus.watchlist,
          ),
          deviceId: 'dev1',
          accountUid: 'uid_a',
          nowMs: 3000,
          queueSync: true,
        );
      }
    };

    var cursor = 1000;
    final res1 = await adapter.sync(
      repo: repo,
      uid: 'uid_a',
      deviceId: 'dev1',
      lastServerCursorMs: cursor,
      onSaveCursor: (next) => cursor = next,
    );

    expect(res1.state, SyncStatusState.synced);
    // Only movie_40 should be pushed, not movies 10/20/30 or unchanged profile.
    expect(res1.pushedCount, 1);
    // Our own fresh movie_40 echo must NOT be counted as pulled.
    expect(res1.pulledCount, 0);
    // Concurrent movie_50 added mid-flight must still remain in pending queue.
    expect(await repo.pendingChangesCount(), 1);

    // Second sync pushes only movie_50.
    final res2 = await adapter.sync(
      repo: repo,
      uid: 'uid_a',
      deviceId: 'dev1',
      lastServerCursorMs: cursor,
      onSaveCursor: (next) => cursor = next,
    );
    expect(res2.pushedCount, 1);
    expect(res2.pulledCount, 0);
    expect(await repo.pendingChangesCount(), 0);

    // Remote device edit arrives cleanly on third sync with zero writes.
    backend.serverClock += 500;
    backend.entriesByUidProfile['uid_a']!['main']!['movie_99'] = LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 99,
      title: 'From Second Phone',
      status: WatchStatus.watched,
      userRating: 10,
      statusChangedAt: 5000,
      ratingChangedAt: 5000,
      clientUpdatedAt: 5000,
      serverSyncedAt: backend.serverClock,
      updatedByDevice: 'dev2',
    );

    final commitsBefore = backend.commitCalls;
    final res3 = await adapter.sync(
      repo: repo,
      uid: 'uid_a',
      deviceId: 'dev1',
      lastServerCursorMs: cursor,
      onSaveCursor: (next) => cursor = next,
    );
    expect(res3.pushedCount, 0);
    expect(backend.commitCalls, commitsBefore);
    expect(res3.pulledCount, 1);
    final imported = await repo.findEntry('main', MediaKey(MediaType.movie, 99));
    expect(imported?.title, 'From Second Phone');
    expect(imported?.userRating, 10);
  });

  test('pruneOldTombstones removes entries deleted >90 days ago while preserving recent ones',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LibraryRepository(db);
    await repo.ensureMainProfile(nowMs: 1000);

    const nowMs = 200 * 24 * 60 * 60 * 1000;
    const oldDeletedAt = nowMs - 100 * 24 * 60 * 60 * 1000;
    const recentDeletedAt = nowMs - 10 * 24 * 60 * 60 * 1000;

    await repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 1,
        title: 'Old Deleted',
        status: WatchStatus.watchlist,
      ),
      deviceId: 'd',
      nowMs: oldDeletedAt - 1000,
      queueSync: false,
    );
    await repo.softDeleteEntry(
      'main',
      MediaKey(MediaType.movie, 1),
      deviceId: 'd',
      nowMs: oldDeletedAt,
      queueSync: false,
    );

    await repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 2,
        title: 'Recent Deleted',
        status: WatchStatus.watchlist,
      ),
      deviceId: 'd',
      nowMs: recentDeletedAt - 1000,
      queueSync: false,
    );
    await repo.softDeleteEntry(
      'main',
      MediaKey(MediaType.movie, 2),
      deviceId: 'd',
      nowMs: recentDeletedAt,
      queueSync: false,
    );

    final pruned = await repo.pruneOldTombstones(retentionDays: 90, nowMs: nowMs);
    expect(pruned, 1);
    expect(await repo.findEntry('main', MediaKey(MediaType.movie, 1)), isNull);
    expect(await repo.findEntry('main', MediaKey(MediaType.movie, 2)), isNotNull);
  });

  test('signOutFromGoogle clears local data and signInWithGoogle respects merge/replace/cancel',
      () async {
    SharedPreferences.setMockInitialValues({'starfilm.onboarding_done': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final backend = _FakeCloudBackend();
    backend.profilesByUid['uid_bob'] = {
      'main': UserProfile(id: 'main', name: 'Головний', serverSyncedAt: 2000),
    };
    backend.entriesByUidProfile['uid_bob'] = {
      'main': {
        'movie_603': const LibraryEntry(
          profileId: 'main',
          mediaType: MediaType.movie,
          tmdbId: 603,
          title: 'The Matrix (Cloud)',
          status: WatchStatus.watched,
          userRating: 10,
          clientUpdatedAt: 2000,
          serverSyncedAt: 2000,
          updatedByDevice: 'bob-tv',
        ),
      },
    };

    final syncAdapter = _ControllableFirebaseSyncAdapter(
      log: DiagnosticsLog(),
      backend: backend,
    );
    final services = _makeStage1Services(
      db: db,
      mockHttp: MockClient((_) async => http.Response('{}', 200)),
      cloudBackend: backend,
      syncAdapter: syncAdapter,
    );
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(appControllerProvider.notifier);
    await notifier.bootstrap();

    // User A creates a profile and saves a movie offline.
    await notifier.createProfile('UserA_Profile');
    await notifier.saveEntryAction(
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Fight Club (UserA)',
      status: WatchStatus.watched,
      userRating: 9,
    );
    expect(container.read(appControllerProvider).entries.length, 1);
    expect(container.read(appControllerProvider).profiles.length, 2);

    // User A signs in, then signs out -> device must be wiped clean for next user.
    syncAdapter.account = const CloudAccountInfo(uid: 'uid_alice', email: 'alice@test.com');
    await notifier.signInWithGoogle();
    await notifier.signOutFromGoogle();

    final afterSignOut = container.read(appControllerProvider);
    expect(afterSignOut.cloudUid, isEmpty);
    expect(afterSignOut.activeProfileId, 'main');
    expect(afterSignOut.profiles.length, 1);
    expect(afterSignOut.entries, isEmpty);
    expect(afterSignOut.pendingSyncCount, 0);

    // Suppose a guest later rated one local movie, then Bob signs in and cancels.
    await notifier.saveEntryAction(
      mediaType: MediaType.movie,
      tmdbId: 155,
      title: 'Local Draft Movie',
      status: WatchStatus.watchlist,
    );
    syncAdapter.account = const CloudAccountInfo(uid: 'uid_bob', email: 'bob@test.com');
    final canceled = await notifier.signInWithGoogle(
      onLocalDataConflict: (_, _) async => SignInMergeChoice.cancel,
    );
    expect(canceled, isFalse);
    expect(container.read(appControllerProvider).cloudUid, isEmpty);
    expect(container.read(appControllerProvider).entries.first.tmdbId, 155);

    // Now Bob signs in and chooses replaceLocalWithCloud -> no leak of movie 155 into Bob's cloud!
    syncAdapter.account = const CloudAccountInfo(uid: 'uid_bob', email: 'bob@test.com');
    final signedIn = await notifier.signInWithGoogle(
      onLocalDataConflict: (_, _) async => SignInMergeChoice.replaceLocalWithCloud,
    );
    expect(signedIn, isTrue);
    final bobState = container.read(appControllerProvider);
    expect(bobState.entries.map((e) => e.tmdbId).toList(), [603]);
    expect(backend.entriesByUidProfile['uid_bob']!['main']!.containsKey('movie_155'), isFalse);
  });

  test('Active profile deleted on another device resets activeProfileId to main after sync',
      () async {
    SharedPreferences.setMockInitialValues({'starfilm.onboarding_done': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final backend = _FakeCloudBackend();
    final syncAdapter = _ControllableFirebaseSyncAdapter(
      log: DiagnosticsLog(),
      backend: backend,
    )..account = const CloudAccountInfo(uid: 'uid_x', email: 'x@test.com');

    final services = _makeStage1Services(
      db: db,
      mockHttp: MockClient((_) async => http.Response('{}', 200)),
      cloudBackend: backend,
      syncAdapter: syncAdapter,
    );
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(appControllerProvider.notifier);
    await notifier.bootstrap();
    await notifier.createProfile('Kids');
    final kidsId = container.read(appControllerProvider).activeProfileId;
    expect(kidsId, startsWith('p_'));
    await notifier.syncCloudNow();

    // Another device soft-deletes 'Kids' in Firestore with a newer clientUpdatedAt.
    backend.serverClock += 1000;
    final remoteKids = backend.profilesByUid['uid_x']![kidsId]!;
    final newerClientTs = remoteKids.clientUpdatedAt + 5000;
    final deletedKids = remoteKids.copyWith(
      clientUpdatedAt: newerClientTs,
      serverSyncedAt: backend.serverClock,
      deletedAt: newerClientTs,
    );
    backend.profilesByUid['uid_x']![kidsId] = deletedKids;

    await notifier.syncCloudNow();
    final stateAfter = container.read(appControllerProvider);
    expect(stateAfter.activeProfileId, 'main');
    expect(stateAfter.profiles.map((p) => p.id), ['main']);
  });

  test('SecretStore safely recovers from PlatformException on corrupted Android Keystore',
      () async {
    final store = SecretStore(storage: const _CorruptedStorage());
    expect(await store.getTmdbKey(), '');
    expect(await store.getGeminiKey(), '');
    expect(await store.getKinopoiskKey(), '');
    expect(await store.loadStarTvDevices(), isEmpty);
    await store.setTmdbKey('abc');
  });

  testWidgets('DiscoveryTab renders full-width Pick button and has no Match button',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'ru',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final backend = _FakeCloudBackend();
    final syncAdapter = _ControllableFirebaseSyncAdapter(
      log: DiagnosticsLog(),
      backend: backend,
    );
    final mockHttp = MockClient((req) async {
      if (req.url.path.contains('/search/')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'results': [
              {
                'id': 550,
                'media_type': 'movie',
                'title': 'Бойцовский клуб',
                'original_title': 'Fight Club',
                'release_date': '1999-10-15',
                'vote_average': 8.4,
                'genre_ids': [18],
                'popularity': 90,
              },
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (req.url.host.contains('generativelanguage')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'recommendations': [
                          {
                            'title': 'Бойцовский клуб',
                            'original_title': 'Fight Club',
                            'year': 1999,
                            'media_type': 'movie',
                            'genre': 'Драма',
                            'reason': 'Культовый триллер',
                          },
                        ],
                      }),
                    },
                  ],
                },
              },
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 200);
    });

    final services = _makeStage1Services(
      db: db,
      mockHttp: mockHttp,
      cloudBackend: backend,
      syncAdapter: syncAdapter,
      secrets: _InMemorySecretStore(initialTmdb: 'TMDB_OK', initialGemini: 'AIzaTest'),
    );
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).bootstrap(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DiscoveryTab())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Match вдвоём'), findsNothing);
    await tester.tap(find.text('Подобрать'));
    await tester.pump();
    for (var i = 0; i < 40 && container.read(appControllerProvider).isPicking; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Ещё варианты'), findsOneWidget);
    final pickRect = tester.getRect(find.text('Подобрать'));
    expect(pickRect.width, greaterThan(40));
    final pickButtonRect = tester.getRect(
      find.ancestor(of: find.text('Подобрать'), matching: find.byType(FilledButton)),
    );
    expect(pickButtonRect.width, greaterThan(300));
  });

  testWidgets('Onboarding Next button preserves pre-existing API keys instead of wiping them',
      (tester) async {
    SharedPreferences.setMockInitialValues({'starfilm.ui_lang': 'ru'});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final backend = _FakeCloudBackend();
    final syncAdapter = _ControllableFirebaseSyncAdapter(
      log: DiagnosticsLog(),
      backend: backend,
    );
    final secrets = _InMemorySecretStore(
      initialTmdb: 'EXISTING_TMDB',
      initialGemini: 'AIzaExisting',
    );
    final services = _makeStage1Services(
      db: db,
      mockHttp: MockClient((_) async => http.Response('{}', 200)),
      cloudBackend: backend,
      syncAdapter: syncAdapter,
      secrets: secrets,
    );
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).bootstrap(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Step 0 -> Step 1 (keys)
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();

    // Existing keys should appear pre-filled and NOT be wiped when pressing Next.
    expect(find.text('EXISTING_TMDB'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();

    final state = container.read(appControllerProvider);
    expect(state.tmdbKey, 'EXISTING_TMDB');
    expect(state.geminiKey, 'AIzaExisting');
    final savedTmdb = await tester.runAsync(() => secrets.getTmdbKey());
    expect(savedTmdb, 'EXISTING_TMDB');
  });

  test('All new Stage 1 cloud conflict and sign-out l10n keys exist for uk/ru/en', () {
    const keys = [
      'cloud_conflict_title',
      'cloud_conflict_body',
      'cloud_conflict_merge',
      'cloud_conflict_replace',
      'signout_confirm_title',
      'signout_confirm_body',
      'signout_pending_body',
      'signout_action',
      'signout_sync_first',
    ];
    for (final lang in ['uk', 'ru', 'en']) {
      final s = AppStrings(lang);
      for (final k in keys) {
        expect(s.t(k), isNot(equals(k)), reason: 'Missing $k for $lang');
      }
    }
  });
}
