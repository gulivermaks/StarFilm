import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starfilm/app/app_state.dart';
import 'package:starfilm/app/l10n.dart';
import 'package:starfilm/core/db/app_database.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/core/models/profile.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
import 'package:starfilm/core/security/secret_store.dart';
import 'package:starfilm/features/cloud_sync/firebase_sync_adapter.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/library/backup_codec.dart';
import 'package:starfilm/features/library/library_repository.dart';
import 'package:starfilm/features/search/tmdb_client.dart';
import 'package:starfilm/features/settings/ota_updater.dart';
import 'package:starfilm/features/settings/settings_screen.dart';
import 'package:starfilm/features/startv/startv_client.dart';
import 'package:starfilm/features/startv/startv_models.dart';
import 'package:starfilm/main.dart';

class _TestSecretStore extends SecretStore {
  String _tmdb = '';
  String _gemini = '';
  String _kp = '';

  @override
  Future<String> getTmdbKey() async => _tmdb;

  @override
  Future<void> setTmdbKey(String value) async => _tmdb = value.trim();

  @override
  Future<String> getGeminiKey() async => _gemini;

  @override
  Future<String> setGeminiKey(String value) async => _gemini = value.trim();

  @override
  Future<String> getKinopoiskKey() async => _kp;

  @override
  Future<void> setKinopoiskKey(String value) async => _kp = value.trim();

  @override
  Future<String> getOrCreateDeviceId() async => 'test-device-2';

  @override
  Future<List<StarTvDevice>> loadStarTvDevices() async => const [];
}

class _OfflineSyncAdapter extends FirebaseSyncAdapter {
  _OfflineSyncAdapter({super.log});

  @override
  Future<bool> tryInitialize() async => false;
}

AppServices _makeTestServices({
  required AppDatabase db,
  required http.Client mockHttp,
}) {
  final log = DiagnosticsLog();
  final httpClient = StarFilmHttpClient(client: mockHttp, log: log);
  final tmdb = TmdbClient(httpClient, log: log);
  final gemini = GeminiClient(httpClient);
  return AppServices(
    log: log,
    http: httpClient,
    db: db,
    repo: LibraryRepository(db),
    secrets: _TestSecretStore(),
    tmdb: tmdb,
    gemini: gemini,
    discovery: DiscoveryService(gemini: gemini, tmdb: tmdb, log: log),
    starTv: StarTvClient(httpClient),
    updater: OtaUpdater(httpClient),
    firebaseSync: _OfflineSyncAdapter(log: log),
  );
}

void main() {
  testWidgets('Onboarding verifies TMDB and Gemini keys inline with clear messages',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': false,
      'starfilm.ui_lang': 'uk',
    });

    final mockHttp = MockClient((req) async {
      if (req.url.host == 'api.tmdb.org') {
        final ok = req.url.queryParameters['api_key'] == 'VALID_TMDB';
        return http.Response(ok ? '{}' : '{"status_code":7}', ok ? 200 : 401);
      }
      if (req.url.host == 'generativelanguage.googleapis.com') {
        final ok = req.url.queryParameters['key'] == 'VALID_GEMINI';
        return http.Response(ok ? '{"name":"models/ok"}' : '{"error":{}}', ok ? 200 : 400);
      }
      return http.Response('{}', 404);
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final services = _makeTestServices(db: db, mockHttp: mockHttp);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const StarFilmApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Advance from step 0 (language) to step 1 (keys)
    await tester.tap(find.text('Далі'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding_tmdb_verify')), findsOneWidget);
    expect(find.byKey(const Key('onboarding_gemini_verify')), findsOneWidget);

    // Empty TMDB verify shows inline validation message
    await tester.tap(find.byKey(const Key('onboarding_tmdb_verify')));
    await tester.pump();
    expect(find.text('Введіть ключ для перевірки'), findsOneWidget);

    // Valid TMDB key shows inline success message
    await tester.enterText(find.byKey(const Key('onboarding_tmdb_field')), 'VALID_TMDB');
    await tester.tap(find.byKey(const Key('onboarding_tmdb_verify')));
    await tester.pumpAndSettle();
    expect(find.text('Ключ перевірено успішно'), findsOneWidget);
    expect(await services.secrets.getTmdbKey(), 'VALID_TMDB');

    // Invalid Gemini key shows inline error message
    await tester.enterText(find.byKey(const Key('onboarding_gemini_field')), 'BAD_GEMINI');
    await tester.tap(find.byKey(const Key('onboarding_gemini_verify')));
    await tester.pumpAndSettle();
    expect(find.text('Ключ не прийнято сервером'), findsOneWidget);
  });

  testWidgets('Backup import mode dialog offers merge and snapshot replace', (tester) async {
    BackupImportMode? picked;
    final bundle = BackupBundle(
      sourceFormat: 'starfilm',
      activeProfileId: 'main',
      profiles: [
        ImportedProfileBundle(
          profile: UserProfile(id: 'main', name: 'Головний'),
          entries: const [],
          collections: const [],
          deletedTombstones: const {},
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  picked = await SettingsScreen.showBackupImportModeDialog(
                    context,
                    bundle: bundle,
                    strings: AppStrings('uk'),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text("Об'єднати (додати новіші)"), findsOneWidget);
    expect(find.text('Відновити стан з копії (замінити бібліотеку)'), findsOneWidget);

    await tester.tap(find.text('Відновити стан з копії (замінити бібліотеку)'));
    await tester.pumpAndSettle();

    expect(picked, BackupImportMode.replace);
  });

  test('AppController.saveEntryAction transitions watched (rated) directly to watchlist',
      () async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'uk',
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final services = _makeTestServices(
      db: db,
      mockHttp: MockClient((_) async => http.Response('{}', 200)),
    );
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);

    // Wait for bootstrap
    container.read(appControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final notifier = container.read(appControllerProvider.notifier);

    // Save as watched with rating 9
    await notifier.saveEntryAction(
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Бійцівський клуб',
      status: WatchStatus.watched,
      userRating: 9,
    );
    var saved = container.read(appControllerProvider).entries.single;
    expect(saved.status, WatchStatus.watched);
    expect(saved.userRating, 9);

    // Directly move to watchlist (without going through watching -> dismissed)
    await notifier.saveEntryAction(
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Бійцівський клуб',
      status: WatchStatus.watchlist,
    );
    saved = container.read(appControllerProvider).entries.single;
    expect(saved.status, WatchStatus.watchlist);
    expect(saved.userRating, isNull);

    // Rating on watchlist still auto-transitions back to watched
    await notifier.saveEntryAction(
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Бійцівський клуб',
      userRating: 8,
    );
    saved = container.read(appControllerProvider).entries.single;
    expect(saved.status, WatchStatus.watched);
    expect(saved.userRating, 8);
  });
}
