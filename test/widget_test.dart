import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starfilm/app/app_state.dart';
import 'package:starfilm/core/db/app_database.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
import 'package:starfilm/core/security/secret_store.dart';
import 'package:starfilm/features/cloud_sync/firebase_sync_adapter.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/library/library_repository.dart';
import 'package:starfilm/features/search/tmdb_client.dart';
import 'package:starfilm/features/settings/ota_updater.dart';
import 'package:starfilm/features/startv/startv_client.dart';
import 'package:starfilm/features/startv/startv_models.dart';
import 'package:starfilm/main.dart';

class _InMemorySecretStore extends SecretStore {
  String _tmdb = '';
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
  Future<String> getOrCreateDeviceId() async => 'test-device-1';

  @override
  Future<List<StarTvDevice>> loadStarTvDevices() async => const [];
}

class _OfflineFirebaseSyncAdapter extends FirebaseSyncAdapter {
  _OfflineFirebaseSyncAdapter({super.log});

  @override
  Future<bool> tryInitialize() async => false;
}

void main() {
  testWidgets('StarFilm opens 3-tab HomeShell with Ukrainian default labels', (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'uk',
    });

    final log = DiagnosticsLog();
    final http = StarFilmHttpClient(log: log);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LibraryRepository(db);
    final secrets = _InMemorySecretStore();
    final tmdb = TmdbClient(http);
    final gemini = GeminiClient(http);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(
            AppServices(
              log: log,
              http: http,
              db: db,
              repo: repo,
              secrets: secrets,
              tmdb: tmdb,
              gemini: gemini,
              discovery: DiscoveryService(gemini: gemini, tmdb: tmdb, log: log),
              starTv: StarTvClient(http),
              updater: OtaUpdater(http),
              firebaseSync: _OfflineFirebaseSyncAdapter(log: log),
            ),
          ),
        ],
        child: const StarFilmApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('StarFilm'), findsOneWidget);
    expect(find.text('Підбір'), findsOneWidget);
    expect(find.text('Пошук'), findsOneWidget);
    expect(find.text('Моє'), findsOneWidget);
    expect(find.byIcon(Icons.tv), findsOneWidget);
  });
}
