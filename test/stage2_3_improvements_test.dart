import 'dart:convert';
import 'dart:typed_data';

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
import 'package:starfilm/core/models/library_entry.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/core/models/profile.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
import 'package:starfilm/core/security/secret_store.dart';
import 'package:starfilm/features/cloud_sync/firebase_sync_adapter.dart';
import 'package:starfilm/features/details/details_sheet.dart';
import 'package:starfilm/features/discovery/discovery_models.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/library/library_repository.dart';
import 'package:starfilm/features/library/library_tab.dart';
import 'package:starfilm/features/library/rating_csv_import.dart';
import 'package:starfilm/features/releases/digital_release_service.dart';
import 'package:starfilm/features/search/search_tab.dart';
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
  Future<String> getOrCreateDeviceId() async => 'dev_stage2_3';
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

AppServices _makeServices({
  required AppDatabase db,
  required MockClient mockHttp,
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
    secrets: secrets ?? _MemSecrets(),
    tmdb: tmdb,
    gemini: gemini,
    discovery: DiscoveryService(gemini: gemini, tmdb: tmdb, log: log),
    starTv: StarTvClient(client),
    updater: OtaUpdater(client),
    firebaseSync: _OfflineAdapter(log: log),
  );
}

http.Response _utf8Json(Map<String, dynamic> data, [int code = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    code,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('under90 preset enforces runtime <= 90 via TMDB and keeps +-1 year match without hard ?year=',
      () async {
    String? sentPromptJson;
    final searchQueryParams = <Map<String, String>>[];

    final mockHttp = MockClient((req) async {
      if (req.url.host == 'generativelanguage.googleapis.com') {
        final decoded = jsonDecode(req.body) as Map<String, dynamic>;
        sentPromptJson =
            decoded['contents'][0]['parts'][0]['text'] as String;
        return _utf8Json({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'recommendations': [
                        {
                          'title': 'Too Long Film',
                          'original_title': 'Too Long Film',
                          'year': 2015,
                          'media_type': 'movie',
                          'genre': 'Action',
                          'reason': 'Action',
                        },
                        {
                          'title': 'Short Shift Year',
                          'original_title': 'Short Shift Year',
                          'year': 2021,
                          'media_type': 'movie',
                          'genre': 'Drama',
                          'reason': 'Fast',
                        },
                      ],
                    }),
                  },
                ],
              },
            },
          ],
        });
      }
      if (req.url.host == 'api.tmdb.org' && req.url.path == '/3/search/movie') {
        searchQueryParams.add(req.url.queryParameters);
        final q = req.url.queryParameters['query'];
        if (q == 'Too Long Film') {
          return _utf8Json({
            'results': [
              {
                'id': 11,
                'title': 'Too Long Film',
                'original_title': 'Too Long Film',
                'release_date': '2015-05-01',
                'genre_ids': [28],
                'vote_average': 8.0,
              },
            ],
          });
        }
        return _utf8Json({
          'results': [
            {
              'id': 22,
              'title': 'Short Shift Year',
              'original_title': 'Short Shift Year',
              // 2020 vs Gemini 2021 (+-1 year allowed)
              'release_date': '2020-12-20',
              'genre_ids': [18],
              'vote_average': 7.5,
            },
          ],
        });
      }
      if (req.url.path == '/3/movie/11') {
        return _utf8Json({'id': 11, 'runtime': 120});
      }
      if (req.url.path == '/3/movie/22') {
        return _utf8Json({'id': 22, 'runtime': 85});
      }
      if (req.url.path.startsWith('/3/discover/')) {
        return _utf8Json({'results': []});
      }
      return http.Response('{}', 404);
    });

    final client = StarFilmHttpClient(client: mockHttp);
    final service = DiscoveryService(
      gemini: GeminiClient(client),
      tmdb: TmdbClient(client),
    );
    final res = await service.recommend(
      tmdbApiKey: 'TMDB_OK',
      geminiApiKey: 'GEMINI_OK',
      geminiModel: 'gemini-3.5-flash-lite',
      request: const DiscoveryRequest(preset: EveningPreset.under90),
      profile: UserProfile(
        id: 'main',
        name: 'Головний',
        preferences: const ProfilePreferences(contentLanguage: 'ru'),
      ),
      library: const [],
      recentShownIds: const {},
      recentShownLabels: const [],
    );

    expect(sentPromptJson, contains('"maxMinutes":90'));
    // Must not send hard ?year= filter during AI verification
    expect(searchQueryParams.any((p) => p.containsKey('year')), isFalse);
    // 120-min film rejected; 85-min +-1 year film kept with runtime populated
    expect(res.cards.map((c) => c.tmdbId).toList(), [22]);
    expect(res.cards.single.runtimeMinutes, 85);
  });

  test('Per-profile discovery cache persists across switchProfile and new profile inherits uiLanguage',
      () async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'ru',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final mockHttp = MockClient((req) async {
      if (req.url.host == 'generativelanguage.googleapis.com') {
        return _utf8Json({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'recommendations': [
                        {
                          'title': 'Начало',
                          'original_title': 'Inception',
                          'year': 2010,
                          'media_type': 'movie',
                          'genre': 'Фантастика',
                          'reason': 'Сон во сне',
                        },
                      ],
                    }),
                  },
                ],
              },
            },
          ],
        });
      }
      if (req.url.path == '/3/search/movie') {
        return _utf8Json({
          'results': [
            {
              'id': 27205,
              'title': 'Начало',
              'original_title': 'Inception',
              'release_date': '2010-07-16',
              'genre_ids': [28, 878],
              'vote_average': 8.4,
            },
          ],
        });
      }
      if (req.url.path.startsWith('/3/discover/')) {
        return _utf8Json({'results': []});
      }
      return http.Response('{}', 200);
    });

    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(_makeServices(db: db, mockHttp: mockHttp))],
    );
    addTearDown(container.dispose);
    final notifier = container.read(appControllerProvider.notifier);
    await notifier.bootstrap();

    await notifier.runDiscovery(const DiscoveryRequest(prompt: 'sci-fi'));
    expect(container.read(appControllerProvider).recommendations.first.tmdbId, 27205);

    // Create child profile -> should inherit uiLanguage 'ru' and start with empty recommendations
    await notifier.createProfile('Kids');
    final kidsState = container.read(appControllerProvider);
    expect(kidsState.activeProfile.preferences.contentLanguage, 'ru');
    expect(kidsState.recommendations, isEmpty);

    // Switching back to main restores cached recommendations without extra API calls!
    await notifier.switchProfile('main');
    expect(container.read(appControllerProvider).recommendations.first.tmdbId, 27205);
  });

  test('DigitalReleaseService checks newly added watchlist items beyond index 20 after filtering notified',
      () async {
    SharedPreferences.setMockInitialValues({
      'starfilm.notified_digital_releases': [
        for (var i = 1; i <= 25; i++) 'movie:$i',
      ],
    });
    final now = DateTime.utc(2026, 11, 15);
    final mockHttp = MockClient((req) async {
      if (req.url.path == '/3/movie/26/release_dates') {
        return _utf8Json({
          'results': [
            {
              'iso_3166_1': 'US',
              'release_dates': [
                {'type': 4, 'release_date': '2026-11-12T00:00:00.000Z'},
              ],
            },
          ],
        });
      }
      return _utf8Json({'results': []});
    });

    final tmdb = TmdbClient(StarFilmHttpClient(client: mockHttp));
    final service = DigitalReleaseService(tmdb);
    final entries = [
      for (var i = 1; i <= 26; i++)
        LibraryEntry(
          profileId: 'main',
          mediaType: MediaType.movie,
          tmdbId: i,
          title: 'Movie $i',
          status: WatchStatus.watchlist,
        ),
    ];

    final matches = await service.findNewlyReleasedMovies(
      tmdbApiKey: 'TMDB_OK',
      entries: entries,
      now: now,
    );
    expect(matches.map((m) => m.entry.tmdbId).toList(), [26]);
  });

  test('RatingCsvParser decodes Windows-1251 bytes and Importer skips unmatched rows without year',
      () async {
    // "Матрица" in CP1251 + ";1999;9"
    final cp1251Bytes = Uint8List.fromList([
      0xCC, 0xE0, 0xF2, 0xF0, 0xE8, 0xF6, 0xE0, // Матрица
      0x3B, 0x31, 0x39, 0x39, 0x39, 0x3B, 0x39, // ;1999;9
    ]);
    final decoded = RatingCsvParser.decodeBytesWithFallback(cp1251Bytes);
    expect(decoded, 'Матрица;1999;9');

    String? requestedLang;
    final mockHttp = MockClient((req) async {
      requestedLang = req.url.queryParameters['language'];
      if (req.url.queryParameters['query'] == 'Obscure Typo') {
        return _utf8Json({
          'results': [
            {
              'id': 999,
              'media_type': 'movie',
              'title': 'Completely Different Movie',
              'original_title': 'Completely Different Movie',
              'release_date': '2018-01-01',
            },
          ],
        });
      }
      return _utf8Json({'results': []});
    });
    final tmdb = TmdbClient(StarFilmHttpClient(client: mockHttp));
    final importer = RatingCsvImporter(tmdb);
    final rows = RatingCsvParser.parse('Obscure Typo - 8/10');
    final res = await importer.resolveRows(
      tmdbApiKey: 'TMDB_OK',
      rows: rows,
      resultContentLanguage: 'ru',
    );
    expect(requestedLang, 'ru-RU');
    expect(res.resolved, isEmpty);
    expect(res.skippedTitles, ['Obscure Typo']);
  });

  testWidgets('SearchTab keeps Latin queries in profile language and wraps filters cleanly on 360px',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'ru',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LibraryRepository(db).saveProfile(
      UserProfile(
        id: 'main',
        name: 'Головний',
        preferences: const ProfilePreferences(contentLanguage: 'ru'),
      ),
      queueSync: false,
    );

    String? capturedLanguage;
    final mockHttp = MockClient((req) async {
      if (req.url.path == '/3/search/multi') {
        capturedLanguage = req.url.queryParameters['language'];
        return _utf8Json({
          'results': [
            {
              'id': 27205,
              'media_type': 'movie',
              'title': 'Начало',
              'original_title': 'Inception',
              'release_date': '2010-07-16',
              'genre_ids': [28],
              'vote_average': 8.4,
            },
          ],
        });
      }
      return _utf8Json({});
    });

    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(_makeServices(db: db, mockHttp: mockHttp))],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(appControllerProvider.notifier).bootstrap());

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.35)),
            child: Scaffold(body: SearchTab()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Genre chip must be fully within 360px screen width!
    final genreRect = tester.getRect(find.text('Жанр'));
    expect(genreRect.right, lessThanOrEqualTo(360));

    await tester.enterText(find.byType(TextField), 'Inception');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(capturedLanguage, 'ru-RU');
    expect(find.text('Начало'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Card), matching: find.text('Inception')),
      findsOneWidget,
    );
    expect(find.text('Точное совпадение'), findsOneWidget);

    // Enabling a non-matching filter shows hidden-by-filters message + reset button
    await tester.tap(find.text('Сериалы'));
    await tester.pumpAndSettle();
    expect(find.textContaining('результаты скрыты фильтрами'), findsOneWidget);
    await tester.tap(find.text('Сбросить фильтры'));
    await tester.pumpAndSettle();
    expect(find.text('Начало'), findsOneWidget);

    await tester.tap(find.text('Хочу'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(container.read(appControllerProvider).entries.single.title, 'Начало');
    expect(find.byIcon(Icons.bookmark_added), findsOneWidget);
  });

  testWidgets('MediaDetailsSheet renders 1..10 in two rows, localizes countries, labels crew/cast',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'ru',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LibraryRepository(db).saveProfile(
      UserProfile(
        id: 'main',
        name: 'Головний',
        preferences: const ProfilePreferences(contentLanguage: 'ru'),
      ),
      queueSync: false,
    );

    final mockHttp = MockClient((req) async {
      if (req.url.path == '/3/movie/27205') {
        return _utf8Json({
          'id': 27205,
          'title': 'Начало',
          'original_title': 'Inception',
          'overview': 'Сон',
          'release_date': '2010-07-16',
          'runtime': 148,
          'vote_average': 8.4,
          'genres': [
            {'id': 28, 'name': 'боевик'},
          ],
          'production_countries': [
            {'iso_3166_1': 'GB', 'name': 'United Kingdom'},
            {'iso_3166_1': 'US', 'name': 'United States of America'},
          ],
          'credits': {
            'crew': [
              {'job': 'Director', 'name': 'Кристофер Нолан'},
            ],
            'cast': [
              {'name': 'Леонардо ДиКаприо'},
            ],
          },
          'videos': {'results': []},
          'external_ids': {},
        });
      }
      return _utf8Json({'results': []});
    });

    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(_makeServices(db: db, mockHttp: mockHttp))],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(appControllerProvider.notifier).bootstrap());

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: MediaDetailsSheet(
              mediaType: MediaType.movie,
              tmdbId: 27205,
              initialTitle: 'Начало',
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    // All 1..10 chips visible on 360px screen, with 6..10 in a second row below 1..5
    final r5 = tester.getRect(find.text('5'));
    final r10 = tester.getRect(find.text('10'));
    expect(r10.right, lessThanOrEqualTo(360));
    expect(r10.top, greaterThan(r5.bottom - 2));

    expect(find.text('Великобритания, США'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('Режиссёр: Кристофер Нолан'), findsOneWidget);
    expect(find.text('В ролях: Леонардо ДиКаприо'), findsOneWidget);
  });

  testWidgets('LibraryTab shows Collections chip without clipping and restores entry on Undo',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'ru',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appServicesProvider.overrideWithValue(
          _makeServices(db: db, mockHttp: MockClient((_) async => _utf8Json({}))),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      final n = container.read(appControllerProvider.notifier);
      await n.bootstrap();
      await n.saveEntryAction(
        mediaType: MediaType.movie,
        tmdbId: 550,
        title: 'Бойцовский клуб',
        status: WatchStatus.watchlist,
      );
    });

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: LibraryTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('Коллекции')).right, lessThanOrEqualTo(360));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(container.read(appControllerProvider).entries, isEmpty);

    await tester.tap(find.text('Отменить'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(container.read(appControllerProvider).entries.single.tmdbId, 550);
  });

  testWidgets('StarTvPairingDialog exposes camera QR button, runs preflight status, shows RU errors',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'ru',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final calls = <String>[];
    final mockHttp = MockClient((req) async {
      calls.add(req.url.path);
      if (req.url.path == '/api/status') {
        return _utf8Json({'tvId': 'tv1', 'deviceName': 'Living Room TV'});
      }
      if (req.url.path == '/api/auth') {
        return _utf8Json({'token': 'tok_123', 'tvId': 'tv1', 'deviceName': 'Living Room TV'});
      }
      return http.Response('{}', 404);
    });

    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(_makeServices(db: db, mockHttp: mockHttp))],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(appControllerProvider.notifier).bootstrap());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: StarTvPairingDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Сканировать QR-код камерой'), findsOneWidget);

    // External IP 8.8.8.8 triggers localized friendly Russian LAN message (no raw exception)
    await tester.enterText(find.byType(TextField).at(1), '8.8.8.8');
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Подключение возможно только в домашней сети Wi-Fi'),
      findsOneWidget,
    );

    // Valid LAN URL calls /api/status BEFORE /api/auth
    await tester.enterText(
      find.byType(TextField).first,
      'http://192.168.1.50:8088/?pin=123456',
    );
    await tester.tap(find.text('ОК'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(calls, ['/api/status', '/api/auth']);
  });

  test('syncWithHomeTv sends deletedProfiles map', () async {
    SharedPreferences.setMockInitialValues({'starfilm.onboarding_done': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    Map<String, dynamic>? capturedSyncPayload;
    final mockHttp = MockClient((req) async {
      if (req.url.path == '/api/library-sync') {
        capturedSyncPayload = jsonDecode(req.body) as Map<String, dynamic>;
        return _utf8Json({
          'profiles': {
            'active': 'main',
            'items': [
              {
                'id': 'main',
                'name': 'Головний',
                'library': {'items': []},
              },
            ],
          },
        });
      }
      return _utf8Json({});
    });
    final secrets = _MemSecrets();
    await secrets.saveStarTvDevice(
      const StarTvDevice(
        tvId: 'tv1',
        ip: '192.168.1.50',
        port: 8088,
        deviceName: 'Home TV',
        trustMode: StarTvTrustMode.home,
      ),
      'tok_1',
    );

    final container = ProviderContainer(
      overrides: [
        appServicesProvider.overrideWithValue(
          _makeServices(db: db, mockHttp: mockHttp, secrets: secrets),
        ),
      ],
    );
    addTearDown(container.dispose);
    final n = container.read(appControllerProvider.notifier);
    await n.bootstrap();
    await n.createProfile('TempProfile');
    final tempId = container.read(appControllerProvider).activeProfileId;
    await n.deleteProfile(tempId);

    await n.syncWithHomeTv();
    expect(capturedSyncPayload?['deletedProfiles'], isA<Map<String, dynamic>>());
    expect((capturedSyncPayload?['deletedProfiles'] as Map).containsKey(tempId), isTrue);
  });

  test('All Stage 2 and 3 l10n keys are non-empty across uk, ru, en', () {
    const keys = [
      'player_web_search',
      'director_label',
      'creator_label',
      'cast_label',
      'delete_profile_confirm_title',
      'delete_profile_confirm_body',
      'delete_collection_confirm_title',
      'delete_collection_confirm_body',
      'entry_removed_undo',
      'undo',
      'rename_profile',
      'profile_subtitle',
      'tmdb_attribution',
      'custom_gemini_model',
      'custom_gemini_title',
      'copy_diagnostics',
      'copied_diagnostics',
      'year_filter',
      'year_all',
      'year_2020_plus',
      'year_2010s',
      'year_2000s',
      'year_before_2000',
      'quick_watch',
      'csv_error_empty',
      'csv_error_too_many',
      'csv_error_format',
      'scan_qr_btn',
      'scan_qr_title',
      'scan_qr_hint',
      'startv_error_lan',
      'startv_error_auth',
      'startv_error_network',
      'backup_ai_key',
      'backup_ai_hint',
      'backup_ai_saved_provider',
      'exact_match_badge',
      'search_hidden_by_filters',
      'reset_filters',
      'pick_ai_no_key',
      'pick_ai_fallback_reason',
    ];
    for (final lang in ['uk', 'ru', 'en']) {
      final s = AppStrings(lang);
      for (final k in keys) {
        expect(s.t(k), isNot(equals(k)), reason: 'Missing $k for $lang');
      }
    }
  });
}
