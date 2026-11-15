import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
import 'package:starfilm/core/security/secret_store.dart';
import 'package:starfilm/features/cloud_sync/firebase_sync_adapter.dart';
import 'package:starfilm/features/details/details_sheet.dart';
import 'package:starfilm/features/discovery/discovery_models.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/discovery/match_swipe_sheet.dart';
import 'package:starfilm/features/library/library_repository.dart';
import 'package:starfilm/features/library/rating_csv_import.dart';
import 'package:starfilm/features/players/mobile_players.dart';
import 'package:starfilm/features/ratings/kinopoisk_client.dart';
import 'package:starfilm/features/releases/digital_release_service.dart';
import 'package:starfilm/features/search/search_tab.dart';
import 'package:starfilm/features/search/tmdb_client.dart';
import 'package:starfilm/features/settings/ota_updater.dart';
import 'package:starfilm/features/startv/startv_client.dart';
import 'package:starfilm/features/startv/startv_models.dart';

class _V08SecretStore extends SecretStore {
  _V08SecretStore({String initialTmdb = '', String initialKp = ''})
      : _tmdb = initialTmdb,
        _kp = initialKp;

  String _tmdb;
  String _gemini = '';
  String _kp;

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
  Future<String> getOrCreateDeviceId() async => 'test-device-v08';

  @override
  Future<List<StarTvDevice>> loadStarTvDevices() async => const [];
}

class _OfflineSyncAdapter extends FirebaseSyncAdapter {
  _OfflineSyncAdapter({super.log});

  @override
  Future<bool> tryInitialize() async => false;
}

AppServices _makeV08Services({
  required AppDatabase db,
  required http.Client mockHttp,
  String initialTmdb = 'VALID_TMDB',
  String initialKp = '',
}) {
  final log = DiagnosticsLog();
  final httpClient = StarFilmHttpClient(client: mockHttp, log: log);
  final tmdb = TmdbClient(httpClient, log: log);
  final gemini = GeminiClient(httpClient);
  final kp = KinopoiskClient(httpClient, log: log);
  return AppServices(
    log: log,
    http: httpClient,
    db: db,
    repo: LibraryRepository(db),
    secrets: _V08SecretStore(initialTmdb: initialTmdb, initialKp: initialKp),
    tmdb: tmdb,
    gemini: gemini,
    discovery: DiscoveryService(gemini: gemini, tmdb: tmdb, log: log),
    starTv: StarTvClient(httpClient),
    updater: OtaUpdater(httpClient),
    firebaseSync: _OfflineSyncAdapter(log: log),
    kinopoisk: kp,
    digitalReleases: DigitalReleaseService(tmdb),
  );
}

Future<ProviderContainer> _bootContainer(
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
  test('KinopoiskClient verifies keys, fetches KP+IMDb ratings, and LogSanitizer masks UUID keys',
      () async {
    const validUuidKey = '12345678-1234-4abc-8def-1234567890ab';
    final log = DiagnosticsLog();
    final mockHttp = MockClient((req) async {
      if (req.url.host != 'kinopoiskapiunofficial.tech') {
        return http.Response('{}', 404);
      }
      final key = req.headers['X-API-KEY'] ?? '';
      if (req.url.path == '/api/v2.2/films/301') {
        if (key == validUuidKey) return http.Response('{}', 200);
        if (key == 'QUOTA_REACHED_KEY') return http.Response('{}', 402);
        return http.Response('{}', 401);
      }
      if (req.url.path == '/api/v2.2/films' && req.url.queryParameters['imdbId'] == 'tt1375666') {
        return http.Response(
          jsonEncode({
            'items': [
              {'ratingKinopoisk': 8.6, 'ratingImdb': 8.8},
            ],
          }),
          200,
        );
      }
      if (req.url.path == '/api/v2.1/films/search-by-keyword') {
        return http.Response(
          jsonEncode({
            'films': [
              {
                'nameRu': 'Матрица',
                'nameEn': 'The Matrix',
                'year': '1999',
                'rating': '8.5',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    });

    final client = KinopoiskClient(StarFilmHttpClient(client: mockHttp, log: log), log: log);

    expect(await client.verifyKey('bad'), isFalse);
    expect(await client.verifyKey(validUuidKey), isTrue);
    expect(await client.verifyKey('QUOTA_REACHED_KEY'), isTrue);
    expect(await client.verifyKey('INVALID_KEY_VALUE'), isFalse);

    final byImdb = await client.fetchRatings(
      apiKey: validUuidKey,
      imdbId: 'tt1375666',
      title: 'Inception',
      year: 2010,
    );
    expect(byImdb, isNotNull);
    expect(byImdb!.kinopoiskRating, 8.6);
    expect(byImdb.imdbRating, 8.8);

    final byKeyword = await client.fetchRatings(
      apiKey: validUuidKey,
      title: 'The Matrix',
      year: 1999,
    );
    expect(byKeyword, isNotNull);
    expect(byKeyword!.kinopoiskRating, 8.5);

    final masked = LogSanitizer.mask('Error calling API with X-API-KEY $validUuidKey');
    expect(masked, isNot(contains(validUuidKey)));
    expect(masked, contains('***'));
  });

  test('RatingCsvParser and RatingCsvImporter parse CSV/TSV/dash formats and resolve TMDB items',
      () async {
    const raw = '''
Назва;Рік;Оцінка;Тип
Inception;2010;9;movie
Дюна	2021	8
Fight Club (1999) — 10/10
Unknown Unmatched Film;1995;7
''';
    final parsed = RatingCsvParser.parse(raw);
    expect(parsed, hasLength(4));
    expect(parsed[0].title, 'Inception');
    expect(parsed[0].year, 2010);
    expect(parsed[0].rating, 9);
    expect(parsed[0].mediaType, MediaType.movie);
    expect(parsed[1].title, 'Дюна');
    expect(parsed[1].rating, 8);
    expect(parsed[2].title, 'Fight Club');
    expect(parsed[2].year, 1999);
    expect(parsed[2].rating, 10);

    final log = DiagnosticsLog();
    final mockHttp = MockClient((req) async {
      final q = (req.url.queryParameters['query'] ?? '').toLowerCase();
      if (q.contains('inception')) {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 27205,
                'title': 'Inception',
                'original_title': 'Inception',
                'release_date': '2010-07-16',
                'vote_average': 8.4,
                'genre_ids': [28, 878],
              },
            ],
          }),
          200,
        );
      }
      if (q.contains('дюна')) {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 438631,
                'media_type': 'movie',
                'title': 'Дюна',
                'original_title': 'Dune',
                'release_date': '2021-09-15',
                'vote_average': 7.8,
                'genre_ids': [878],
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (q.contains('fight club')) {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 550,
                'media_type': 'movie',
                'title': 'Fight Club',
                'original_title': 'Fight Club',
                'release_date': '1999-10-15',
                'vote_average': 8.4,
                'genre_ids': [18],
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{"results":[]}', 200);
    });

    final tmdb = TmdbClient(StarFilmHttpClient(client: mockHttp, log: log), log: log);
    final importer = RatingCsvImporter(tmdb);
    final progressTicks = <String>[];
    final result = await importer.resolveRows(
      tmdbApiKey: 'VALID_TMDB',
      rows: parsed,
      onProgress: (done, total) => progressTicks.add('$done/$total'),
    );

    expect(result.resolved, hasLength(3));
    expect(result.resolved[0].candidate.tmdbId, 27205);
    expect(result.resolved[0].rating, 9);
    expect(result.skippedTitles, ['Unknown Unmatched Film (1995)']);
    expect(progressTicks.last, '4/4');
  });

  test('DigitalReleaseService checks Watchlist MOVIES only and deduplicates notifications',
      () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.utc(2026, 11, 15);
    final recentDigitalStr = '2026-11-10T00:00:00.000Z';

    var requestedPaths = <String>[];
    final log = DiagnosticsLog();
    final mockHttp = MockClient((req) async {
      requestedPaths.add(req.url.path);
      if (req.url.path == '/3/movie/101/release_dates') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'iso_3166_1': 'US',
                'release_dates': [
                  {'type': 3, 'release_date': '2026-09-01T00:00:00.000Z'},
                  {'type': 4, 'release_date': recentDigitalStr},
                ],
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{"results":[]}', 200);
    });

    final tmdb = TmdbClient(StarFilmHttpClient(client: mockHttp, log: log), log: log);
    final service = DigitalReleaseService(tmdb);

    final entries = [
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 101,
        title: 'Watchlist Movie',
        status: WatchStatus.watchlist,
      ),
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.tv,
        tmdbId: 202,
        title: 'Watchlist Series Should Be Ignored',
        status: WatchStatus.watchlist,
      ),
      const LibraryEntry(
        profileId: 'main',
        mediaType: MediaType.movie,
        tmdbId: 303,
        title: 'Watched Movie Ignored',
        status: WatchStatus.watched,
      ),
    ];

    final firstRun = await service.findNewlyReleasedMovies(
      tmdbApiKey: 'VALID_TMDB',
      entries: entries,
      now: now,
    );
    expect(firstRun, hasLength(1));
    expect(firstRun.single.entry.tmdbId, 101);
    expect(firstRun.single.releaseDate.year, 2026);
    expect(firstRun.single.releaseDate.month, 11);
    expect(firstRun.single.releaseDate.day, 10);
    expect(requestedPaths, ['/3/movie/101/release_dates']);

    // Repeat check must not re-notify the already notified movie.
    final secondRun = await service.findNewlyReleasedMovies(
      tmdbApiKey: 'VALID_TMDB',
      entries: entries,
      now: now,
    );
    expect(secondRun, isEmpty);
  });

  test('MobilePlayerId includes VLC, MX Player, Kodi, and TorrServe with valid launch plans', () {
    expect(MobilePlayerId.values.map((p) => p.label), containsAll([
      'VLC',
      'MX Player',
      'Kodi',
      'TorrServe',
    ]));
    for (final p in [
      MobilePlayerId.vlc,
      MobilePlayerId.mxPlayer,
      MobilePlayerId.kodi,
      MobilePlayerId.torrServe,
    ]) {
      final plan = PlayerLaunchPlanner.plan(
        player: p,
        mediaType: MediaType.movie,
        title: 'Blade Runner 2049',
        year: 2017,
      );
      expect(plan.packageName, isNotNull);
      expect(plan.packageName, isNotEmpty);
      expect(plan.clipboardText, 'Blade Runner 2049 2017');
    }
  });

  testWidgets('MatchSwipeSheet runs two-player swipe turn and finds mutual match',
      (tester) async {
    final s = AppStrings('en');
    const cards = [
      RecommendationCard(
        mediaType: MediaType.movie,
        tmdbId: 27205,
        title: 'Inception',
        originalTitle: 'Inception',
        year: 2010,
        posterPath: '',
        genreIds: [28],
        tmdbRating: 8.4,
        reason: 'Mind-bending heist',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchSwipeSheet(cards: cards, strings: s),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Player 1 turn • 1/1'), findsOneWidget);
    expect(find.text('Inception'), findsOneWidget);

    // Player 1 likes card.
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    // Handoff screen between Player 1 and Player 2.
    expect(find.text('Hand the phone to Player 2'), findsOneWidget);
    await tester.tap(find.text('Start Player 2 turn'));
    await tester.pumpAndSettle();

    // Player 2 likes same card -> mutual match.
    expect(find.text('Player 2 turn • 1/1'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(find.text('It’s a Match! (1)'), findsOneWidget);
    expect(find.text('Inception'), findsOneWidget);
  });

  testWidgets('MediaDetailsSheet displays Kinopoisk, IMDb, and Movie Digital Release badges',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'en',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final mockHttp = MockClient((req) async {
      if (req.url.host == 'api.tmdb.org' && req.url.path == '/3/movie/101/release_dates') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'iso_3166_1': 'US',
                'release_dates': [
                  {'type': 4, 'release_date': '2026-10-05T00:00:00.000Z'},
                ],
              },
            ],
          }),
          200,
        );
      }
      if (req.url.host == 'api.tmdb.org' && req.url.path == '/3/movie/101') {
        return http.Response(
          jsonEncode({
            'id': 101,
            'title': 'Dune: Part Two',
            'original_title': 'Dune: Part Two',
            'overview': 'Paul Atreides unites with Chani and the Fremen.',
            'release_date': '2024-03-01',
            'runtime': 166,
            'vote_average': 8.3,
            'genres': [
              {'id': 878, 'name': 'Science Fiction'},
            ],
            'external_ids': {'imdb_id': 'tt15239678'},
            'credits': {'crew': [], 'cast': []},
            'videos': {'results': []},
          }),
          200,
        );
      }
      if (req.url.host == 'kinopoiskapiunofficial.tech' && req.url.path == '/api/v2.2/films') {
        return http.Response(
          jsonEncode({
            'items': [
              {'ratingKinopoisk': 8.5, 'ratingImdb': 8.7},
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    final services = _makeV08Services(
      db: db,
      mockHttp: mockHttp,
      initialTmdb: 'VALID_TMDB',
      initialKp: '12345678-1234-4abc-8def-1234567890ab',
    );
    final container = await _bootContainer(tester, services);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: MediaDetailsSheet(
              mediaType: MediaType.movie,
              tmdbId: 101,
              initialTitle: 'Dune: Part Two',
              initialYear: 2024,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('KP 8.5'), findsOneWidget);
    expect(find.text('IMDb 8.7'), findsOneWidget);
    expect(find.text('Digital: 05.10.2026'), findsOneWidget);
  });

  testWidgets('SearchTab voice mic fills search query via launcher channel and searches TMDB',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'starfilm.onboarding_done': true,
      'starfilm.ui_lang': 'en',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    const channel = MethodChannel('app.starfilm.android/launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'startVoiceInput') {
          return 'Interstellar';
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final mockHttp = MockClient((req) async {
      if (req.url.path.contains('/search/multi')) {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 157336,
                'media_type': 'movie',
                'title': 'Interstellar',
                'original_title': 'Interstellar',
                'release_date': '2014-11-07',
                'vote_average': 8.7,
                'genre_ids': [878],
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{"genres":[]}', 200);
    });

    final services = _makeV08Services(db: db, mockHttp: mockHttp);
    final container = await _bootContainer(tester, services);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SearchTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('Interstellar'), findsWidgets);
  });

  test('All uk/ru/en v0.08 l10n keys are non-empty and interpolated cleanly', () {
    const expectedKeys = [
      'kp_key',
      'onboarding_get_kp',
      'kp_rating',
      'imdb_rating',
      'voice_input_tooltip',
      'voice_unavailable',
      'csv_import_btn',
      'csv_import_hint',
      'csv_pick_file',
      'csv_paste_label',
      'csv_import_run',
      'csv_import_progress',
      'csv_import_done',
      'match_swipe_btn',
      'match_swipe_title',
      'match_player_turn',
      'match_hand_off',
      'match_hand_off_desc',
      'match_start_p2',
      'match_like',
      'match_skip',
      'match_found_title',
      'match_none_title',
      'match_none_desc',
      'match_open_details',
      'release_alerts_toggle',
      'release_alerts_desc',
      'release_check_now',
      'release_found_banner',
      'release_none_found',
      'digital_release_badge',
    ];
    for (final lang in ['uk', 'ru', 'en']) {
      final s = AppStrings(lang);
      for (final key in expectedKeys) {
        final v = s.t(key);
        expect(v, isNot(equals(key)), reason: 'Missing $key for $lang');
        expect(v.trim(), isNotEmpty, reason: 'Empty $key for $lang');
      }
    }
  });
}
