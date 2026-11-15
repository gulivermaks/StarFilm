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
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
import 'package:starfilm/core/security/secret_store.dart';
import 'package:starfilm/features/cloud_sync/firebase_sync_adapter.dart';
import 'package:starfilm/features/details/details_sheet.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/discovery_tab.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/library/library_repository.dart';
import 'package:starfilm/features/library/library_tab.dart';
import 'package:starfilm/features/search/search_tab.dart';
import 'package:starfilm/features/search/tmdb_client.dart';
import 'package:starfilm/features/settings/ota_updater.dart';
import 'package:starfilm/features/settings/settings_screen.dart';
import 'package:starfilm/features/startv/startv_client.dart';
import 'package:starfilm/features/startv/startv_models.dart';

class _TestSecretStore extends SecretStore {
  _TestSecretStore({String initialTmdb = ''}) : _tmdb = initialTmdb;

  String _tmdb;
  String _gemini = '';

  @override
  Future<String> getTmdbKey() async => _tmdb;

  @override
  Future<void> setTmdbKey(String value) async => _tmdb = value.trim();

  @override
  Future<String> getGeminiKey() async => _gemini;

  @override
  Future<void> setGeminiKey(String value) async => _gemini = value.trim();

  @override
  Future<String> getOrCreateDeviceId() async => 'test-device-ui';

  @override
  Future<List<StarTvDevice>> loadStarTvDevices() async => const [];
}

class _OfflineSyncAdapter extends FirebaseSyncAdapter {
  _OfflineSyncAdapter({super.log});

  @override
  Future<bool> tryInitialize() async => false;
}

AppServices _makeUiTestServices({
  required AppDatabase db,
  required http.Client mockHttp,
  String initialTmdb = '',
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
    secrets: _TestSecretStore(initialTmdb: initialTmdb),
    tmdb: tmdb,
    gemini: gemini,
    discovery: DiscoveryService(gemini: gemini, tmdb: tmdb, log: log),
    starTv: StarTvClient(httpClient),
    updater: OtaUpdater(httpClient),
    firebaseSync: _OfflineSyncAdapter(log: log),
  );
}

Future<ProviderContainer> _bootTestContainer(
  WidgetTester tester,
  AppServices services,
) async {
  final container = ProviderContainer(
    overrides: [appServicesProvider.overrideWithValue(services)],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() async {
    container.read(appControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  return container;
}

void main() {
  testWidgets('MediaDetailsSheet toggles Sentiment, clears rating, and edits Collections',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'uk',
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final services = _makeUiTestServices(
      db: db,
      mockHttp: MockClient((_) async => http.Response('{}', 200)),
    );
    final container = await _bootTestContainer(tester, services);
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).createCollection('На вихідні'),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: MediaDetailsSheet(
              mediaType: MediaType.movie,
              tmdbId: 27205,
              initialTitle: 'Початок',
              initialOriginalTitle: 'Inception',
              initialYear: 2010,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap rating 8, verify it saves, then tap clear rating.
    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();
    expect(container.read(appControllerProvider).entries.single.userRating, 8);

    await tester.tap(find.text('Зняти оцінку'));
    await tester.pumpAndSettle();
    expect(container.read(appControllerProvider).entries.single.userRating, isNull);

    // Toggle Like chip on then off.
    await tester.tap(find.text('Подобається'));
    await tester.pumpAndSettle();
    expect(
      container.read(appControllerProvider).entries.single.sentiment,
      Sentiment.liked,
    );

    await tester.tap(find.text('Подобається'));
    await tester.pumpAndSettle();
    expect(
      container.read(appControllerProvider).entries.single.sentiment,
      Sentiment.neutral,
    );

    // Scroll down the MediaDetailsSheet ListView and toggle existing collection FilterChip.
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    final chipFinder = find.widgetWithText(FilterChip, 'На вихідні');
    await tester.tap(chipFinder);
    await tester.pumpAndSettle();
    expect(
      container.read(appControllerProvider).collections.single.mediaKeys,
      ['movie:27205'],
    );
  });

  testWidgets('LibraryTab expands collections, removes items, renames, and deletes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'uk',
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final services = _makeUiTestServices(
      db: db,
      mockHttp: MockClient((_) async => http.Response('{}', 200)),
    );
    final container = await _bootTestContainer(tester, services);

    final notifier = container.read(appControllerProvider.notifier);
    await tester.runAsync(() async {
      await notifier.saveEntryAction(
        mediaType: MediaType.movie,
        tmdbId: 27205,
        title: 'Початок',
        status: WatchStatus.watchlist,
      );
      final col = await notifier.createCollection('Фаворити');
      await notifier.toggleItemInCollection(col!, MediaKey(MediaType.movie, 27205));
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: LibraryTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Collections sub-tab.
    await tester.tap(find.text('Колекції'));
    await tester.pumpAndSettle();

    expect(find.text('Фаворити'), findsOneWidget);
    expect(find.text('Тайтлів: 1'), findsOneWidget);

    // Expand collection and verify item appears.
    await tester.tap(find.text('Фаворити'));
    await tester.pumpAndSettle();
    expect(find.text('Початок'), findsOneWidget);

    // Remove item from collection.
    await tester.tap(find.byTooltip('Прибрати з колекції'));
    await tester.pumpAndSettle();
    expect(find.text('У колекції поки немає тайтлів'), findsOneWidget);

    // Open menu -> rename collection.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Перейменувати'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Топ список');
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
    expect(find.text('Топ список'), findsOneWidget);

    // Open menu -> delete collection.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Видалити'));
    await tester.pumpAndSettle();
    expect(find.text('Топ список'), findsNothing);
  });

  testWidgets('DiscoveryTab surfaces discovery errors and SearchTab uses ru/en l10n cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'ru',
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final services = _makeUiTestServices(
      db: db,
      initialTmdb: 'BAD_KEY',
      mockHttp: MockClient((_) async => http.Response('{"status_code":7}', 401)),
    );
    final container = await _bootTestContainer(tester, services);

    // Check SearchTab renders Russian genre filter and error message, no hardcoded Ukrainian.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SearchTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Жанр'), findsOneWidget);
    expect(find.text('Введите название для поиска в TMDB'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Matrix');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(find.textContaining('Недействительный TMDB API Key'), findsOneWidget);

    // Switch to English and check DiscoveryTab error banner.
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).setUiLanguage('en'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DiscoveryTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recommend'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load picks:'), findsOneWidget);
  });

  testWidgets('SettingsScreen.showUpdateAvailableDialog renders notes and triggers download',
      (tester) async {
    Uri? launchedUri;
    final release = ReleaseAssetInfo(
      versionName: '0.05',
      downloadUrl: 'https://github.com/gulivermaks/StarFilm/releases/download/v0.05/StarFilm.apk',
      expectedSize: 1024,
      expectedSha256: 'abc',
      releaseNotes: 'Collections & Sentiment UI',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  SettingsScreen.showUpdateAvailableDialog(
                    context,
                    release: release,
                    strings: AppStrings('en'),
                    onDownload: (uri) async {
                      launchedUri = uri;
                      return true;
                    },
                  );
                },
                child: const Text('ShowUpdate'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ShowUpdate'));
    await tester.pumpAndSettle();

    expect(find.text('StarFilm 0.05 update available'), findsOneWidget);
    expect(find.text('Collections & Sentiment UI'), findsOneWidget);

    await tester.tap(find.text('Download APK'));
    await tester.pumpAndSettle();

    expect(launchedUri?.toString(), release.downloadUrl);
  });
}
