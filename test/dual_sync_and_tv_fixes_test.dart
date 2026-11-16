import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starfilm/app/app_state.dart';
import 'package:starfilm/core/db/app_database.dart';
import 'package:starfilm/core/models/library_entry.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/core/models/profile.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
import 'package:starfilm/core/security/secret_store.dart';
import 'package:starfilm/features/cloud_sync/firebase_sync_adapter.dart';
import 'package:starfilm/features/details/details_sheet.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/library/backup_codec.dart';
import 'package:starfilm/features/library/library_repository.dart';
import 'package:starfilm/features/library/library_tab.dart';
import 'package:starfilm/features/search/tmdb_client.dart';
import 'package:starfilm/features/settings/ota_updater.dart';
import 'package:starfilm/features/startv/startv_client.dart';
import 'package:starfilm/features/startv/startv_models.dart';
import 'package:starfilm/features/startv/startv_pairing_dialog.dart';

class _MemSecrets extends SecretStore {
  String tmdb = 'TMDB_OK';
  String gemini = 'AIzaTest';
  final Map<String, String> _tokens = {};
  final List<StarTvDevice> _tvs = [];

  @override
  Future<String> getTmdbKey() async => tmdb;
  @override
  Future<void> setTmdbKey(String value) async => tmdb = value.trim();
  @override
  Future<String> getGeminiKey() async => gemini;
  @override
  Future<void> setGeminiKey(String value) async => gemini = value.trim();
  @override
  Future<String> getKinopoiskKey() async => '';
  @override
  Future<void> setKinopoiskKey(String value) async {}
  @override
  Future<String> getOrCreateDeviceId() async => 'dev_dual_test';
  @override
  Future<List<StarTvDevice>> loadStarTvDevices() async => _tvs;
  @override
  Future<void> saveStarTvDevice(StarTvDevice device, String bearerToken) async {
    _tvs
      ..clear()
      ..add(device);
    _tokens[device.tvId] = bearerToken;
  }

  @override
  Future<String?> getStarTvToken(StarTvDevice device) async => _tokens[device.tvId];
}

class _OfflineAdapter extends FirebaseSyncAdapter {
  _OfflineAdapter({super.log});
  @override
  Future<bool> tryInitialize() async => false;
}

AppServices _buildTestServices({
  required AppDatabase db,
  required MockClient mockHttp,
  SecretStore? secrets,
}) {
  final log = DiagnosticsLog();
  final httpClient = StarFilmHttpClient(log: log, client: mockHttp);
  final tmdb = TmdbClient(httpClient, log: log);
  final gemini = GeminiClient(httpClient);
  return AppServices(
    log: log,
    http: httpClient,
    db: db,
    repo: LibraryRepository(db),
    secrets: secrets ?? _MemSecrets(),
    tmdb: tmdb,
    gemini: gemini,
    discovery: DiscoveryService(gemini: gemini, tmdb: tmdb, log: log),
    starTv: StarTvClient(httpClient),
    updater: OtaUpdater(httpClient),
    firebaseSync: _OfflineAdapter(log: log),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('StarTvClient normalizes default main name and parses deletedProfiles in response',
      () async {
    late Map<String, dynamic> capturedPayload;
    final mock = MockClient((req) async {
      if (req.url.path == '/api/library-sync') {
        capturedPayload = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'profiles': {
              'active': 'main',
              'items': [
                {
                  'id': 'main',
                  'name': '',
                  'profileUpdatedAt': 2000,
                  'library': {
                    'schemaVersion': 1,
                    'personalized': true,
                    'profileUpdatedAt': 2000,
                    'filters': {'excludedGenres': [], 'contentLanguage': 'ru'},
                    'items': [],
                  },
                },
              ],
            },
            'deletedProfiles': {'p_tvdead1': 3000},
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final log = DiagnosticsLog();
    final client = StarTvClient(StarFilmHttpClient(log: log, client: mock));
    const device = StarTvDevice(
      tvId: 'tv1',
      ip: '192.168.1.50',
      port: 8088,
      deviceName: 'StarTV',
      trustMode: StarTvTrustMode.home,
    );

    final bundle = await client.syncLibrary(
      device: device,
      bearerToken: 'tok',
      activeProfileId: 'main',
      profiles: [
        UserProfile(id: 'main', name: 'Головний', clientUpdatedAt: 1000),
        UserProfile(id: 'p_keep1', name: 'Семья', clientUpdatedAt: 1000),
      ],
      entriesByProfile: const {},
      deletedByProfile: const {},
    );

    final sentProfiles = capturedPayload['profiles'] as List<dynamic>;
    expect((sentProfiles[0] as Map)['name'], '');
    expect((sentProfiles[1] as Map)['name'], 'Семья');
    expect(bundle.deletedProfiles, {'p_tvdead1': 3000});
  });

  test(
      'mergeImportedBundle skips unchanged entries, preserves favoriteGenres, and applies deletedProfiles',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LibraryRepository(db);
    await repo.ensureMainProfile();

    await repo.saveProfile(
      UserProfile(
        id: 'main',
        name: 'Головний',
        preferences: const ProfilePreferences(
          excludedGenres: [27],
          favoriteGenres: [878, 53],
          contentLanguage: 'ru',
        ),
        clientUpdatedAt: 1000,
      ),
      queueSync: false,
    );
    await repo.saveProfile(
      UserProfile(id: 'p_tvdead1', name: 'Old TV Profile', clientUpdatedAt: 1500),
      queueSync: false,
    );
    await repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 27205,
        title: 'Начало',
        status: WatchStatus.watched,
        userRating: 9,
        statusChangedAt: 1000,
        ratingChangedAt: 1000,
        sentimentChangedAt: 1000,
        clientUpdatedAt: 1000,
      ),
      deviceId: 'dev1',
      nowMs: 1000,
      queueSync: false,
    );
    await db.delete(db.pendingChangesTable).go();
    expect(await repo.pendingChangesCount(), 0);

    final tvBundle = BackupBundle(
      sourceFormat: 'startv',
      activeProfileId: 'main',
      deletedProfiles: const {'p_tvdead1': 2000},
      profiles: [
        ImportedProfileBundle(
          profile: UserProfile(
            id: 'main',
            name: 'Головний',
            preferences: const ProfilePreferences(
              excludedGenres: [27],
              favoriteGenres: [],
              contentLanguage: 'ru',
            ),
            clientUpdatedAt: 2000,
          ),
          entries: const [
            LibraryEntry(
              profileId: 'main',
              mediaType: MediaType.movie,
              tmdbId: 27205,
              title: 'Начало',
              status: WatchStatus.watched,
              userRating: 9,
              statusChangedAt: 1000,
              ratingChangedAt: 1000,
              sentimentChangedAt: 1000,
              clientUpdatedAt: 1000,
            ),
          ],
          collections: const [],
          deletedTombstones: const {},
        ),
      ],
    );

    await repo.mergeImportedBundle(tvBundle, deviceId: 'dev1', accountUid: 'u1', queueSync: true);

    final profiles = await repo.listProfiles();
    expect(profiles.map((p) => p.id), ['main']);
    expect(profiles.first.preferences.favoriteGenres, [53, 878]);
    // Only the deleted profile change is queued; unchanged entry & main profile do not trigger writes.
    expect(await repo.pendingChangesCount(), 1);
  });

  testWidgets('LibraryTab displays Hidden/Other tab for dismissed and status-none items',
      (tester) async {
    SharedPreferences.setMockInitialValues({'starfilm_onboarding': true, 'starfilm_ui_lang': 'ru'});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final services = _buildTestServices(
      db: db,
      mockHttp: MockClient((_) async => http.Response('{}', 200)),
    );
    await services.repo.ensureMainProfile();
    await services.repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 628,
        title: 'Интервью с вампиром',
        status: WatchStatus.none,
        sentiment: Sentiment.disliked,
      ),
      deviceId: 'd1',
      nowMs: 1000,
      queueSync: false,
    );
    await services.repo.upsertEntry(
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 85,
        title: 'Индиана Джонс',
        status: WatchStatus.dismissed,
      ),
      deviceId: 'd1',
      nowMs: 1000,
      queueSync: false,
    );

    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      final n = container.read(appControllerProvider.notifier);
      await n.bootstrap();
      await n.setUiLanguage('ru');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LibraryTab())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Скрытые / Прочие'), findsOneWidget);
    await tester.tap(find.text('Скрытые / Прочие'));
    await tester.pumpAndSettle();

    expect(find.text('Интервью с вампиром'), findsOneWidget);
    expect(find.text('Индиана Джонс'), findsOneWidget);
  });

  testWidgets(
      'MediaDetailsSheet shows TV player picker and Trailer on TV without overflow at 360px 1.35x',
      (tester) async {
    SharedPreferences.setMockInitialValues({'starfilm_onboarding': true, 'starfilm_ui_lang': 'ru'});
    String? launchedPlayer;
    var trailerCalled = false;

    final mock = MockClient((req) async {
      if (req.url.host == 'api.themoviedb.org') {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'id': 27205, 'title': 'Начало', 'overview': 'Сюжет'})),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (req.url.path == '/api/ai-launch') {
        launchedPlayer = Uri.splitQueryString(req.body)['player'];
        return http.Response('{"status":"ok"}', 200);
      }
      if (req.url.path == '/api/trailer') {
        trailerCalled = true;
        return http.Response('{"status":"ok"}', 200);
      }
      return http.Response('{}', 200);
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secrets = _MemSecrets();
    const tv = StarTvDevice(
      tvId: 'tv_1',
      ip: '192.168.1.50',
      port: 8088,
      deviceName: 'StarTV W2',
      trustMode: StarTvTrustMode.home,
      installedPlayers: ['auto', 'lampa', 'vlc', 'torrserve'],
    );
    await secrets.saveStarTvDevice(tv, 'secret-token');

    final services = _buildTestServices(db: db, mockHttp: mock, secrets: secrets);
    await services.repo.ensureMainProfile();

    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      final n = container.read(appControllerProvider.notifier);
      await n.bootstrap();
      await n.setUiLanguage('ru');
    });

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.35)),
            child: Scaffold(
              body: MediaDetailsSheet(
                mediaType: MediaType.movie,
                tmdbId: 27205,
                initialTitle: 'Начало',
                initialOriginalTitle: 'Inception',
                initialYear: 2010,
                initialPosterPath: '',
                initialGenreIds: [28],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Трейлер на ТВ'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Трейлер на ТВ'), findsOneWidget);

    await tester.tap(find.text('Трейлер на ТВ'));
    await tester.pumpAndSettle();
    expect(trailerCalled, isTrue);

    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    expect(find.text('VLC'), findsOneWidget);
    expect(find.text('TorrServe'), findsOneWidget);

    await tester.tap(find.text('VLC'));
    await tester.pumpAndSettle();
    expect(launchedPlayer, 'vlc');
  });

  test('syncWithHomeTv updates installedPlayers from /api/library-sync and fallback /api/status',
      () async {
    SharedPreferences.setMockInitialValues({'starfilm_onboarding': true, 'starfilm_ui_lang': 'uk'});
    var syncReturnsPlayers = true;
    final mock = MockClient((req) async {
      if (req.url.path == '/api/library-sync') {
        return http.Response(
          jsonEncode({
            'schemaVersion': 1,
            if (syncReturnsPlayers) 'installedPlayers': ['auto', 'lampa', 'vlc', 'vimu'],
            'profiles': {
              'active': 'main',
              'items': [
                {
                  'id': 'main',
                  'name': '',
                  'profileUpdatedAt': 2000,
                  'library': {
                    'schemaVersion': 1,
                    'personalized': true,
                    'profileUpdatedAt': 2000,
                    'filters': {'excludedGenres': [], 'contentLanguage': 'uk'},
                    'items': [],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path == '/api/status') {
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'tvId': 'tv_1',
            'deviceName': 'StarTV W2',
            'installedPlayers': ['auto', 'lampa', 'kodi'],
            'syncApiVersion': 1,
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secrets = _MemSecrets();
    await secrets.saveStarTvDevice(
      const StarTvDevice(
        tvId: 'tv_1',
        ip: '192.168.1.50',
        port: 8088,
        deviceName: 'StarTV W2',
        trustMode: StarTvTrustMode.home,
        installedPlayers: ['auto', 'lampa'],
      ),
      'tok_1',
    );
    final services = _buildTestServices(db: db, mockHttp: mock, secrets: secrets);
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);
    final n = container.read(appControllerProvider.notifier);
    await n.bootstrap();

    await n.syncWithHomeTv();
    expect(
      container.read(appControllerProvider).activeTv?.installedPlayers,
      ['auto', 'lampa', 'vlc', 'vimu'],
    );

    syncReturnsPlayers = false;
    await n.syncWithHomeTv();
    expect(
      container.read(appControllerProvider).activeTv?.installedPlayers,
      ['auto', 'lampa', 'kodi'],
    );
  });

  testWidgets('StarTvPairingDialog parses ip:port manually and separates IP vs QR errors',
      (tester) async {
    SharedPreferences.setMockInitialValues({'starfilm_onboarding': true, 'starfilm_ui_lang': 'uk'});
    final requestedUris = <Uri>[];
    final mock = MockClient((req) async {
      requestedUris.add(req.url);
      if (req.url.path == '/api/status') {
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'tvId': 'tv_custom',
            'deviceName': 'StarTV Box',
            'installedPlayers': ['auto', 'lampa'],
            'syncApiVersion': 1,
          }),
          200,
        );
      }
      if (req.url.path == '/api/auth') {
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'token': 'tok_custom',
            'tvId': 'tv_custom',
            'deviceName': 'StarTV Box',
            'installedPlayers': ['auto', 'lampa'],
            'syncApiVersion': 1,
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    expect(
      StarTvQrPayload.tryParseHostPort('192.168.1.50:8089'),
      (ip: '192.168.1.50', port: 8089),
    );
    expect(
      StarTvQrPayload.tryParseHostPort('10.0.0.5'),
      (ip: '10.0.0.5', port: 8088),
    );
    expect(StarTvQrPayload.tryParseHostPort('8.8.8.8:8088'), isNull);
    expect(StarTvQrPayload.tryParseHostPort('192.168.'), isNull);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secrets = _MemSecrets();
    final services = _buildTestServices(db: db, mockHttp: mock, secrets: secrets);
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await container.read(appControllerProvider.notifier).bootstrap();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StarTvPairingDialog())),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    final okButton = find.text('ОК');
    // Test invalid IP -> shows LAN error, not invalid QR error
    await tester.enterText(fields.at(1), '8.8.8.8:8088');
    await tester.enterText(fields.at(2), '123456');
    await tester.tap(okButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('192.168.x.x'), findsOneWidget);

    // Test invalid QR -> shows invalid QR error
    await tester.enterText(fields.at(0), 'not-a-valid-qr');
    await tester.tap(okButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('QR'), findsWidgets);

    // Clear QR and pair using manual IP:port
    await tester.enterText(fields.at(0), '');
    await tester.enterText(fields.at(1), '192.168.1.50:8089');
    await tester.enterText(fields.at(2), '123456');
    await tester.tap(okButton);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(requestedUris.any((u) => u.host == '192.168.1.50' && u.port == 8089), isTrue);
  });
}
