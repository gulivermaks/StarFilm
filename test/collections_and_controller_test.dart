import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starfilm/app/app_state.dart';
import 'package:starfilm/core/db/app_database.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
import 'package:starfilm/core/security/secret_store.dart';
import 'package:starfilm/features/cloud_sync/firebase_sync_adapter.dart';
import 'package:starfilm/features/discovery/discovery_models.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/library/library_repository.dart';
import 'package:starfilm/features/search/tmdb_client.dart';
import 'package:starfilm/features/settings/ota_updater.dart';
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
  Future<String> getOrCreateDeviceId() async => 'test-device-collections';

  @override
  Future<List<StarTvDevice>> loadStarTvDevices() async => const [];
}

class _OfflineSyncAdapter extends FirebaseSyncAdapter {
  _OfflineSyncAdapter({super.log});

  @override
  Future<bool> tryInitialize() async => false;
}

AppServices _makeServices({
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

void main() {
  test('AppController manages collections (create, toggle, rename, delete) and sync queue',
      () async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'uk',
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final services = _makeServices(
      db: db,
      mockHttp: MockClient((_) async => http.Response('{}', 200)),
    );
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);

    container.read(appControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final notifier = container.read(appControllerProvider.notifier);

    // Blank title is ignored.
    expect(await notifier.createCollection('   '), isNull);
    expect(container.read(appControllerProvider).collections, isEmpty);

    // Create collection.
    final col = await notifier.createCollection('  На вечір  ');
    expect(col, isNotNull);
    expect(col!.title, 'На вечір');
    expect(container.read(appControllerProvider).collections, hasLength(1));

    // Toggle item in & out.
    final movieKey = MediaKey(MediaType.movie, 27205);
    await notifier.toggleItemInCollection(col, movieKey);
    var updated = container.read(appControllerProvider).collections.single;
    expect(updated.mediaKeys, ['movie:27205']);

    await notifier.toggleItemInCollection(updated, movieKey);
    updated = container.read(appControllerProvider).collections.single;
    expect(updated.mediaKeys, isEmpty);

    // Rename collection.
    await notifier.renameCollection(updated, 'Класика');
    updated = container.read(appControllerProvider).collections.single;
    expect(updated.title, 'Класика');

    // Soft-delete collection: hidden from active list, persisted as tombstone.
    await notifier.deleteCollection(updated);
    expect(container.read(appControllerProvider).collections, isEmpty);
    final allIncludingDeleted =
        await services.repo.listCollections('main', includeDeleted: true);
    expect(allIncludingDeleted.single.isDeleted, isTrue);
  });

  test('AppController stores clearRating, Sentiment, and surfaces discovery errors',
      () async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'uk',
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var shouldFailDiscovery = true;
    final services = _makeServices(
      db: db,
      initialTmdb: 'VALID_TMDB',
      mockHttp: MockClient((req) async {
        if (shouldFailDiscovery) {
          return http.Response('{"status_message":"Invalid API key"}', 401);
        }
        if (req.url.path.contains('/discover/')) {
          return http.Response(
            '{"results":[{"id":550,"title":"Fight Club","release_date":"1999-10-15","vote_average":8.4,"genre_ids":[18]}]}',
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);

    container.read(appControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final notifier = container.read(appControllerProvider.notifier);

    // Save rating and Like sentiment, then clear rating while keeping status & sentiment.
    await notifier.saveEntryAction(
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Бійцівський клуб',
      status: WatchStatus.watched,
      userRating: 9,
      sentiment: Sentiment.liked,
    );
    var saved = container.read(appControllerProvider).entries.single;
    expect(saved.userRating, 9);
    expect(saved.sentiment, Sentiment.liked);

    await notifier.saveEntryAction(
      mediaType: MediaType.movie,
      tmdbId: 550,
      title: 'Бійцівський клуб',
      clearRating: true,
    );
    saved = container.read(appControllerProvider).entries.single;
    expect(saved.userRating, isNull);
    expect(saved.status, WatchStatus.watched);
    expect(saved.sentiment, Sentiment.liked);

    // Failed discovery populates lastDiscoveryError.
    await notifier.runDiscovery(const DiscoveryRequest(prompt: 'трилер'));
    var state = container.read(appControllerProvider);
    expect(state.isPicking, isFalse);
    expect(state.lastDiscoveryError, isNotEmpty);

    // Next successful discovery clears lastDiscoveryError.
    shouldFailDiscovery = false;
    await notifier.runDiscovery(const DiscoveryRequest(prompt: 'трилер'));
    state = container.read(appControllerProvider);
    expect(state.lastDiscoveryError, isEmpty);
    expect(state.recommendations, hasLength(1));
  });
}
