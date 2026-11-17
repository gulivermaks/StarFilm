import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starfilm/core/models/library_entry.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/core/models/profile.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/features/discovery/discovery_models.dart';
import 'package:starfilm/features/discovery/discovery_service.dart';
import 'package:starfilm/features/discovery/gemini_client.dart';
import 'package:starfilm/features/search/tmdb_client.dart';
import 'package:starfilm/features/search/tmdb_matcher.dart';
import 'package:starfilm/features/startv/startv_client.dart';
import 'package:starfilm/features/startv/startv_models.dart';

void main() {
  test('TmdbMatcher matches normalized titles within +-1 year', () {
    final candidates = [
      const TmdbSearchCandidate(
        tmdbId: 603,
        mediaType: MediaType.movie,
        title: 'Матриця',
        originalTitle: 'The Matrix',
        year: 1999,
        posterPath: '/matrix.jpg',
        genreIds: [28, 878],
        voteAverage: 8.2,
        popularity: 95,
      ),
      const TmdbSearchCandidate(
        tmdbId: 9999,
        mediaType: MediaType.movie,
        title: 'Матриця',
        originalTitle: 'Fake Matrix',
        year: 2010,
        posterPath: '',
        genreIds: [28],
        voteAverage: 4.0,
        popularity: 1,
      ),
    ];

    final match = TmdbMatcher.pickBestMatch(
      title: 'Матриця',
      originalTitle: 'The Matrix',
      year: 2000,
      results: candidates,
    );
    expect(match?.tmdbId, 603);
  });

  test('DiscoveryService makes 1 Gemini call, filters excluded/watched, and falls back on 429', () async {
    var geminiCalls = 0;
    final mockHttp = MockClient((req) async {
      if (req.url.host == 'generativelanguage.googleapis.com') {
        geminiCalls++;
        if (req.url.queryParameters['key'] == 'RATE_LIMITED') {
          return http.Response('{"error":{"code":429}}', 429);
        }
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
                            'title': 'Початок',
                            'original_title': 'Inception',
                            'year': 2010,
                            'media_type': 'movie',
                            'genre': 'Фантастика',
                            'reason': 'Захопливий сюжет',
                          },
                          {
                            'title': 'Вже бачив',
                            'original_title': 'Already Watched',
                            'year': 2020,
                            'media_type': 'movie',
                            'genre': 'Драма',
                            'reason': 'Має бути відфільтровано',
                          },
                          {
                            'title': 'Вигаданий фільм',
                            'original_title': 'Non Existent Film',
                            'year': 2023,
                            'media_type': 'movie',
                            'genre': 'Драма',
                            'reason': 'Галюцинація',
                          },
                        ]
                      }),
                    }
                  ]
                }
              }
            ]
          })),
          200,
        );
      }

      if (req.url.host == 'api.tmdb.org' && req.url.path == '/3/search/movie') {
        final q = req.url.queryParameters['query'] ?? '';
        if (q == 'Inception') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'results': [
                {
                  'id': 27205,
                  'title': 'Початок',
                  'original_title': 'Inception',
                  'release_date': '2010-07-16',
                  'poster_path': '/inc.jpg',
                  'genre_ids': [28, 878],
                  'vote_average': 8.4,
                  'popularity': 100,
                }
              ]
            })),
            200,
          );
        }
        if (q == 'Already Watched') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'results': [
                {
                  'id': 777,
                  'title': 'Вже бачив',
                  'original_title': 'Already Watched',
                  'release_date': '2020-01-01',
                  'poster_path': '/w.jpg',
                  'genre_ids': [18],
                  'vote_average': 7.5,
                  'popularity': 50,
                }
              ]
            })),
            200,
          );
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }

      if (req.url.host == 'api.tmdb.org' && req.url.path.startsWith('/3/discover/')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'results': [
              {
                'id': 155,
                'title': 'Темний лицар',
                'original_title': 'The Dark Knight',
                'release_date': '2008-07-18',
                'poster_path': '/tdk.jpg',
                'genre_ids': [28, 80],
                'vote_average': 8.5,
                'popularity': 90,
              }
            ]
          })),
          200,
        );
      }

      return http.Response('{}', 404);
    });

    final client = StarFilmHttpClient(client: mockHttp);
    final service = DiscoveryService(
      gemini: GeminiClient(client),
      tmdb: TmdbClient(client),
    );
    final profile = UserProfile(
      id: 'main',
      name: 'Головний',
      preferences: const ProfilePreferences(excludedGenres: [27]),
    );
    const watched = LibraryEntry(
      profileId: 'main',
      mediaType: MediaType.movie,
      tmdbId: 777,
      title: 'Вже бачив',
      status: WatchStatus.watched,
    );

    final res = await service.recommend(
      tmdbApiKey: 'TMDB_OK',
      geminiApiKey: 'GEMINI_OK',
      geminiModel: 'gemini-2.5-flash-lite',
      request: const DiscoveryRequest(prompt: 'Фантастика'),
      profile: profile,
      library: const [watched],
      recentShownIds: const {},
      recentShownLabels: const [],
    );

    expect(geminiCalls, 1);
    expect(res.cards.any((c) => c.tmdbId == 27205), isTrue);
    expect(res.cards.any((c) => c.tmdbId == 777), isFalse);

    // On 429, fallback uses TMDB /discover without failing
    final fallbackRes = await service.recommend(
      tmdbApiKey: 'TMDB_OK',
      geminiApiKey: 'RATE_LIMITED',
      geminiModel: 'gemini-2.5-flash-lite',
      request: const DiscoveryRequest(prompt: 'Фантастика'),
      profile: profile,
      library: const [watched],
      recentShownIds: const {},
      recentShownLabels: const [],
    );
    expect(fallbackRes.usedFallback, isTrue);
    expect(fallbackRes.cards.any((c) => c.tmdbId == 155), isTrue);
  });

  test('StarTvClient blocks library-sync and key transfer in Guest TV mode', () async {
    String? lastLaunchedTmdbId;
    final mockHttp = MockClient((req) async {
      if (req.url.path == '/api/ai-launch') {
        lastLaunchedTmdbId = Uri.splitQueryString(req.body)['tmdbId'];
        return http.Response('{"status":"ok"}', 200);
      }
      return http.Response('{}', 403);
    });

    final starTv = StarTvClient(StarFilmHttpClient(client: mockHttp));
    const guestTv = StarTvDevice(
      tvId: 'tv-guest',
      ip: '192.168.1.50',
      port: 8088,
      deviceName: 'Friend TV',
      trustMode: StarTvTrustMode.guest,
    );

    await starTv.launchMedia(
      device: guestTv,
      bearerToken: 'tok',
      tmdbId: 27205,
      mediaType: MediaType.movie,
      title: 'Inception',
    );
    expect(lastLaunchedTmdbId, '27205');

    expect(
      () => starTv.transferApiKey(
        device: guestTv,
        bearerToken: 'tok',
        provider: 'tmdb',
        apiKey: 'secret',
      ),
      throwsA(isA<StarTvException>()),
    );
    expect(
      () => starTv.syncLibrary(
        device: guestTv,
        bearerToken: 'tok',
        activeProfileId: 'main',
        profiles: [UserProfile(id: 'main', name: 'Головний')],
        entriesByProfile: const {},
        deletedByProfile: const {},
      ),
      throwsA(isA<StarTvException>()),
    );
  });

  test('TmdbClient supports v4 Bearer token, throws on 401, and GeminiClient falls back on 404 model', () async {
    http.Response utf8Json(Map<String, dynamic> body) => http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    String? capturedAuthHeader;
    String? capturedQueryApiKey;
    final requestedGeminiModels = <String>[];

    final mockHttp = MockClient((req) async {
      if (req.url.host == 'api.tmdb.org') {
        capturedAuthHeader = req.headers['Authorization'];
        capturedQueryApiKey = req.url.queryParameters['api_key'];
        if (capturedAuthHeader == 'Bearer eyJ_BAD') {
          return http.Response('{"status_code":7}', 401);
        }
        return utf8Json({
          'results': [
            {
              'id': 603,
              'media_type': 'movie',
              'title': 'The Matrix',
              'original_title': 'The Matrix',
              'release_date': '1999-03-31',
              'genre_ids': [28, 878],
              'vote_average': 8.2,
            }
          ],
        });
      }
      if (req.url.host == 'generativelanguage.googleapis.com') {
        requestedGeminiModels.add(req.url.path);
        if (req.url.path.contains('gemini-2.5-flash-lite')) {
          return http.Response('{"error":{"code":404}}', 404);
        }
        return utf8Json({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'recommendations': [
                        {
                          'title': 'Матриця',
                          'original_title': 'The Matrix',
                          'year': 1999,
                          'media_type': 'movie',
                          'genre': 'Фантастика',
                          'reason': 'Культовий sci-fi.',
                        }
                      ],
                    }),
                  }
                ],
              },
            }
          ],
        });
      }
      return http.Response('{}', 404);
    });

    final client = StarFilmHttpClient(client: mockHttp);
    final tmdb = TmdbClient(client);

    final okResults = await tmdb.searchMulti(
      apiKey: 'eyJhbGciOiJIUzI1NiJ9.long_v4_token_abcdefghijklmnopqrstuvwxyz',
      query: 'Matrix',
    );
    expect(okResults, hasLength(1));
    expect(capturedAuthHeader, startsWith('Bearer eyJ'));
    expect(capturedQueryApiKey, isNull);

    await expectLater(
      () => tmdb.searchMulti(apiKey: 'eyJ_BAD', query: 'Matrix'),
      throwsA(isA<TmdbHttpException>()),
    );

    expect(GeminiClient.normalizeModel('gemini-3.5-flash-lite'), 'gemini-2.5-flash-lite');
    expect(GeminiClient.normalizeModel('gemini-3.8-flash'), 'gemini-2.5-flash-lite');

    final gemini = GeminiClient(client);
    final candidates = await gemini.generateCandidates(
      apiKey: 'AIzaTest',
      model: 'gemini-3.5-flash-lite',
      request: const DiscoveryRequest(prompt: 'Sci-fi'),
      profile: UserProfile(id: 'main', name: 'Головний'),
      library: const [],
      recentShownLabels: const [],
    );
    expect(candidates, hasLength(1));
    expect(requestedGeminiModels.any((p) => p.contains('gemini-2.5-flash-lite')), isTrue);
    expect(requestedGeminiModels.any((p) => p.contains('gemini-2.5-flash:')), isTrue);
  });

  test('TmdbMatcher.phoneticLatinQuery and DiscoveryService resolve Cyrillic loanwords like "стрит файтер"',
      () async {
    expect(TmdbMatcher.phoneticLatinQuery('стрит файтер'), 'street fighter');
    expect(TmdbMatcher.phoneticLatinQuery('мортал комбат 1995'), 'mortal kombat 1995');
    expect(
      TmdbMatcher.titlesMatch('Street Fighter', 'Street Fighter: Вуличний боєць'),
      isTrue,
    );
    expect(
      TmdbMatcher.titlesMatch('Вуличний боєць', 'Street Fighter: Вуличний боєць'),
      isTrue,
    );

    final searchedQueries = <String>[];
    final mockHttp = MockClient((req) async {
      if (req.url.host == 'api.tmdb.org' && req.url.path == '/3/search/multi') {
        final q = req.url.queryParameters['query'] ?? '';
        searchedQueries.add(q);
        if (q.toLowerCase() == 'street fighter') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'results': [
                {
                  'id': 11667,
                  'media_type': 'movie',
                  'title': 'Вуличний боєць',
                  'original_title': 'Street Fighter',
                  'release_date': '1994-12-23',
                  'poster_path': '/sf.jpg',
                  'genre_ids': [28, 12],
                  'vote_average': 5.1,
                  'popularity': 40,
                }
              ]
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }
      if (req.url.host == 'api.tmdb.org' && req.url.path.startsWith('/3/discover/')) {
        return http.Response(jsonEncode({'results': []}), 200);
      }
      return http.Response('{}', 404);
    });

    final client = StarFilmHttpClient(client: mockHttp);
    final tmdb = TmdbClient(client);
    final searchRes = await tmdb.searchMulti(
      apiKey: 'TMDB_OK',
      query: 'стрит файтер',
      contentLanguage: 'uk',
    );
    expect(searchRes.map((e) => e.tmdbId), [11667]);
    expect(searchedQueries, ['стрит файтер', 'street fighter']);

    final service = DiscoveryService(gemini: GeminiClient(client), tmdb: tmdb);
    final recRes = await service.recommend(
      tmdbApiKey: 'TMDB_OK',
      geminiApiKey: '',
      geminiModel: GeminiClient.fallbackModel,
      request: const DiscoveryRequest(prompt: 'стрит файтер'),
      profile: UserProfile(id: 'main', name: 'Головний'),
      library: const [],
      recentShownIds: const {},
      recentShownLabels: const [],
    );
    expect(recRes.usedFallback, isTrue);
    expect(recRes.cards.first.tmdbId, 11667);
    expect(recRes.cards.first.title, 'Вуличний боєць');
  });
}
