import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starfilm/core/models/library_entry.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/core/models/profile.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';
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
        if (req.url.path.contains('gemini-3.5-flash-lite')) {
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

    expect(GeminiClient.normalizeModel('gemini-3.5-flash-lite'), 'gemini-3.5-flash-lite');
    expect(GeminiClient.normalizeModel('gemini-3.6-flash'), 'gemini-3.6-flash');
    expect(GeminiClient.normalizeModel('gemini-3.8-flash'), 'gemini-3.8-flash');
    expect(GeminiClient.normalizeModel('gemini-4-hydrogen'), 'gemini-4-hydrogen');
    expect(GeminiClient.normalizeModel('gemini-2.0-flash'), 'gemini-3.5-flash-lite');
    expect(GeminiClient.normalizeModel('gemini-1.5-flash'), 'gemini-3.5-flash-lite');

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
    expect(requestedGeminiModels.any((p) => p.contains('gemini-3.5-flash-lite')), isTrue);
    expect(requestedGeminiModels.any((p) => p.contains('gemini-3.1-flash-lite')), isTrue);
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

  test('GeminiClient handles 400 simplified retry, dynamic /v1beta/models discovery, and Groq/OpenRouter backup failover',
      () async {
    final groqKey = 'gsk_testbackupkey1234567890abcdef';
    final openRouterKey = 'sk-or-v1-testbackupkey1234567890abcdef';
    expect(
      LogSanitizer.mask('Headers Authorization: Bearer $groqKey and key=$openRouterKey'),
      isNot(anyOf(contains(groqKey), contains(openRouterKey))),
    );
    expect(GeminiClient.detectProvider(groqKey), AiKeyProvider.groq);
    expect(GeminiClient.detectProvider(openRouterKey), AiKeyProvider.openRouter);
    expect(GeminiClient.detectProvider('AIzaPrimary12345'), AiKeyProvider.gemini);

    var gemini38Attempts = 0;
    var usedDynamicModel = false;
    final mockDiscoveryHttp = MockClient((req) async {
      if (req.url.host == 'generativelanguage.googleapis.com') {
        if (req.url.path == '/v1beta/models') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-3.8-flash-tts',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/gemini-custom-free',
                  'supportedGenerationMethods': ['generateContent'],
                },
              ],
            })),
            200,
          );
        }
        if (req.url.path.contains('gemini-3.8-flash:generateContent')) {
          gemini38Attempts++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final genCfg = body['generationConfig'] as Map<String, dynamic>;
          if (genCfg.containsKey('thinkingConfig')) {
            expect(genCfg['thinkingConfig']['thinkingLevel'], 'low');
            return http.Response('{"error":{"code":400,"message":"unsupported"}}', 400);
          }
          // Simplified retry also simulated as 429 so cascade proceeds to dynamic discovery
          return http.Response('{"error":{"code":429}}', 429);
        }
        if (req.url.path.contains('gemini-custom-free:generateContent')) {
          usedDynamicModel = true;
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text': 'Here is your pick:\n{"recommendations":[{"title":"Дюна","original_title":"Dune","year":2021,"media_type":"movie","genre":"Sci-Fi","reason":"Эпик"}]}',
                      }
                    ],
                  },
                }
              ],
            })),
            200,
          );
        }
        return http.Response('{"error":{"code":429}}', 429);
      }
      return http.Response('{}', 404);
    });

    final geminiClient = GeminiClient(StarFilmHttpClient(client: mockDiscoveryHttp));
    final dynamicRes = await geminiClient.generateCandidates(
      apiKey: 'AIzaDynamicTest',
      model: 'gemini-3.8-flash',
      request: const DiscoveryRequest(prompt: 'Sci-fi'),
      profile: UserProfile(id: 'main', name: 'Main'),
      library: const [],
      recentShownLabels: const [],
    );
    expect(gemini38Attempts, 2); // initial + simplified 400 retry
    expect(usedDynamicModel, isTrue);
    expect(dynamicRes.single.originalTitle, 'Dune');

    // Now test failover from exhausted Gemini key to Groq backup key, and to OpenRouter
    var calledGroq = false;
    var calledOpenRouter = false;
    final mockBackupHttp = MockClient((req) async {
      if (req.url.host == 'generativelanguage.googleapis.com') {
        return http.Response('{"error":{"code":429}}', 429);
      }
      if (req.url.host == 'api.groq.com') {
        if (req.url.path == '/openai/v1/models') {
          return http.Response('{"data":[]}', 200);
        }
        calledGroq = true;
        if (req.headers['Authorization'] == 'Bearer $groqKey') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'recommendations': [
                        {
                          'title': 'Драйв',
                          'original_title': 'Drive',
                          'year': 2011,
                          'media_type': 'movie',
                          'genre': 'Crime',
                          'reason': 'Неоновый триллер',
                        }
                      ],
                    }),
                  },
                }
              ],
            })),
            200,
          );
        }
        return http.Response('{}', 401);
      }
      if (req.url.host == 'openrouter.ai') {
        if (req.url.path == '/api/v1/auth/key') {
          return http.Response('{"data":{}}', 200);
        }
        calledOpenRouter = true;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '```json\n{"recommendations":[{"title":"Побег из Шоушенка","original_title":"The Shawshank Redemption","year":1994,"media_type":"movie","genre":"Drama","reason":"Классика"}]}\n```',
                },
              }
            ],
          })),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final backupClient = GeminiClient(StarFilmHttpClient(client: mockBackupHttp));
    expect(await backupClient.verifyBackupKey(groqKey), isTrue);
    expect(await backupClient.verifyBackupKey(openRouterKey), isTrue);

    final groqRes = await backupClient.generateCandidates(
      apiKey: 'AIzaExhausted',
      backupApiKey: groqKey,
      model: 'gemini-3.5-flash-lite',
      request: const DiscoveryRequest(prompt: 'Crime'),
      profile: UserProfile(id: 'main', name: 'Main'),
      library: const [],
      recentShownLabels: const [],
    );
    expect(calledGroq, isTrue);
    expect(groqRes.single.originalTitle, 'Drive');

    final orRes = await backupClient.generateCandidates(
      apiKey: 'AIzaExhausted',
      backupApiKey: openRouterKey,
      model: 'gemini-3.5-flash-lite',
      request: const DiscoveryRequest(prompt: 'Drama'),
      profile: UserProfile(id: 'main', name: 'Main'),
      library: const [],
      recentShownLabels: const [],
    );
    expect(calledOpenRouter, isTrue);
    expect(orRes.single.originalTitle, 'The Shawshank Redemption');
  });

  test('TmdbClient.searchCatalog ranks exact titles #1 across locales and DiscoveryService pins exact matches + /recommendations backfill',
      () async {
    final mockHttp = MockClient((req) async {
      if (req.url.host == 'api.tmdb.org') {
        final q = (req.url.queryParameters['query'] ?? '').toLowerCase();
        final lang = req.url.queryParameters['language'] ?? '';

        if (req.url.path == '/3/search/movie') {
          if (q == 'дюна') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'total_pages': 1,
                'results': [
                  {
                    'id': 693134,
                    'title': 'Дюна: Частина друга',
                    'original_title': 'Dune: Part Two',
                    'release_date': '2024-02-27',
                    'poster_path': '/dune2.jpg',
                    'genre_ids': [878, 12],
                    'vote_average': 8.3,
                    'vote_count': 6000,
                    'popularity': 350.0,
                  },
                  {
                    'id': 438631,
                    'title': 'Дюна',
                    'original_title': 'Dune',
                    'release_date': '2021-09-15',
                    'poster_path': '/dune1.jpg',
                    'genre_ids': [878, 12],
                    'vote_average': 7.8,
                    'vote_count': 1200,
                    'popularity': 40.0,
                  },
                ],
              })),
              200,
            );
          }
          if (q == 'стрит файтер') {
            // Non-empty irrelevant hit to verify phonetic merge still triggers
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'total_pages': 1,
                'results': [
                  {
                    'id': 9001,
                    'title': 'Файтер з вулиці',
                    'original_title': 'Random Brawler',
                    'release_date': '2019-01-01',
                    'poster_path': '/rnd.jpg',
                    'genre_ids': [28],
                    'vote_average': 6.0,
                    'vote_count': 500,
                    'popularity': 80.0,
                  },
                ],
              })),
              200,
            );
          }
          if (q == 'street fighter') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'total_pages': 1,
                'results': [
                  {
                    'id': 11667,
                    'title': 'Вуличний боєць',
                    'original_title': 'Street Fighter',
                    'release_date': '1994-12-23',
                    'poster_path': '/sf.jpg',
                    'genre_ids': [28],
                    'vote_average': 5.1,
                    'vote_count': 900,
                    'popularity': 25.0,
                  },
                ],
              })),
              200,
            );
          }
          return http.Response('{"total_pages":1,"results":[]}', 200);
        }

        if (req.url.path == '/3/search/tv') {
          if (q == 'squid game' && lang == 'ru-RU') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'total_pages': 1,
                'results': [
                  {
                    'id': 93405,
                    'name': 'Игра в кальмара',
                    'original_name': '오징어 게임',
                    'first_air_date': '2021-09-17',
                    'poster_path': '/squid.jpg',
                    'genre_ids': [10759, 9648],
                    'vote_average': 7.8,
                    'vote_count': 13000,
                    'popularity': 200.0,
                  },
                ],
              })),
              200,
            );
          }
          if (q == 'squid game' && lang == 'en-US') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'total_pages': 1,
                'results': [
                  {
                    'id': 93405,
                    'name': 'Squid Game',
                    'original_name': '오징어 게임',
                    'first_air_date': '2021-09-17',
                    'poster_path': '/squid.jpg',
                    'genre_ids': [10759, 9648],
                    'vote_average': 7.8,
                    'vote_count': 13000,
                    'popularity': 200.0,
                  },
                ],
              })),
              200,
            );
          }
          return http.Response('{"total_pages":1,"results":[]}', 200);
        }

        if (req.url.path == '/3/movie/438631/recommendations') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'results': [
                {
                  'id': 335984,
                  'title': 'Той, хто біжить по лезу 2049',
                  'original_title': 'Blade Runner 2049',
                  'release_date': '2017-10-04',
                  'poster_path': '/br.jpg',
                  'genre_ids': [878, 18],
                  'vote_average': 7.6,
                  'vote_count': 12000,
                  'popularity': 70.0,
                },
              ],
            })),
            200,
          );
        }

        if (req.url.path.startsWith('/3/discover/')) {
          return http.Response('{"results":[]}', 200);
        }
      }

      if (req.url.host == 'generativelanguage.googleapis.com') {
        return http.Response('{"error":{"code":429}}', 429);
      }

      return http.Response('{}', 404);
    });

    final client = StarFilmHttpClient(client: mockHttp);
    final tmdb = TmdbClient(client);

    // 1. Exact title "Дюна" ranks above more popular "Дюна: Частина друга"
    final duneRes = await tmdb.searchCatalog(
      apiKey: 'TMDB_OK',
      query: 'Дюна',
      contentLanguage: 'uk',
    );
    expect(duneRes.first.tmdbId, 438631);
    expect(duneRes.first.title, 'Дюна');

    // 2. Non-Ukrainian/non-Latin title ("Squid Game" while profile is ru) preserves Russian title AND gets exact match via en-US
    final squidRes = await tmdb.searchCatalog(
      apiKey: 'TMDB_OK',
      query: 'Squid Game',
      contentLanguage: 'ru',
    );
    expect(squidRes.single.tmdbId, 93405);
    expect(squidRes.single.title, 'Игра в кальмара');
    expect(
      TmdbMatcher.isExactTitleMatch(query: 'Squid Game', item: squidRes.single),
      isTrue,
    );

    // 3. Phonetic fallback merges even when primary results are non-empty
    final sfRes = await tmdb.searchCatalog(
      apiKey: 'TMDB_OK',
      query: 'стрит файтер',
      contentLanguage: 'uk',
    );
    expect(sfRes.first.tmdbId, 11667);

    // 4. DiscoveryService pins exact match even when genre (878) is excluded & already in recentShownIds,
    //    and uses TMDB /recommendations backfill for similar films!
    final service = DiscoveryService(gemini: GeminiClient(client), tmdb: tmdb);
    final recRes = await service.recommend(
      tmdbApiKey: 'TMDB_OK',
      geminiApiKey: 'AIzaLimit',
      geminiModel: GeminiClient.fallbackModel,
      request: const DiscoveryRequest(prompt: 'Дюна'),
      profile: UserProfile(
        id: 'main',
        name: 'Головний',
        preferences: const ProfilePreferences(excludedGenres: [878]),
      ),
      library: const [],
      recentShownIds: const {'movie:438631'},
      recentShownLabels: const [],
    );
    expect(recRes.cards.first.tmdbId, 438631);
    expect(recRes.cards.first.isExactMatch, isTrue);
    expect(recRes.usedFallback, isTrue);
    // Blade Runner 2049 has genre 878 which is excluded from recommendations, while pinned exact Dune stays!
    expect(recRes.cards.any((c) => c.tmdbId == 335984), isFalse);

    // With no excluded genres, Blade Runner 2049 is recommended via /recommendations
    final recResSimilar = await service.recommend(
      tmdbApiKey: 'TMDB_OK',
      geminiApiKey: 'AIzaLimit',
      geminiModel: GeminiClient.fallbackModel,
      request: const DiscoveryRequest(prompt: 'Дюна'),
      profile: UserProfile(id: 'main', name: 'Головний'),
      library: const [],
      recentShownIds: const {},
      recentShownLabels: const [],
    );
    expect(recResSimilar.cards.map((c) => c.tmdbId), [438631, 693134, 335984]);
  });
}
