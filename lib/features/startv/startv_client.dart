import 'dart:convert';

import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../../core/network/starfilm_http_client.dart';
import '../library/backup_codec.dart';
import 'startv_models.dart';

class StarTvException implements Exception {
  StarTvException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'StarTvException($statusCode): $message';
}

class StarTvStatus {
  const StarTvStatus({
    required this.tvId,
    required this.deviceName,
    required this.installedPlayers,
    required this.syncApiVersion,
  });

  final String tvId;
  final String deviceName;
  final List<String> installedPlayers;
  final int syncApiVersion;
}

class StarTvAuthResult {
  const StarTvAuthResult({
    required this.token,
    required this.tvId,
    required this.deviceName,
    required this.installedPlayers,
    required this.syncApiVersion,
  });

  final String token;
  final String tvId;
  final String deviceName;
  final List<String> installedPlayers;
  final int syncApiVersion;
}

class StarTvClient {
  StarTvClient(this._http);

  final StarFilmHttpClient _http;

  Future<StarTvStatus> fetchStatus({required String ip, int port = 8088}) async {
    final uri = Uri(scheme: 'http', host: ip.trim(), port: port, path: '/api/status');
    final res = await _http.get(uri, timeout: const Duration(seconds: 6));
    if (!res.isOk) {
      throw StarTvException('Status failed', statusCode: res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final players = (data['installedPlayers'] as List<dynamic>? ?? const ['auto'])
        .map((e) => e.toString())
        .toList();
    return StarTvStatus(
      tvId: (data['tvId'] ?? '').toString(),
      deviceName: (data['deviceName'] ?? 'StarTV').toString(),
      installedPlayers: players.isEmpty ? const ['auto'] : players,
      syncApiVersion: (data['syncApiVersion'] is num)
          ? (data['syncApiVersion'] as num).toInt()
          : 0,
    );
  }

  Future<StarTvAuthResult> authenticate({
    required String ip,
    int port = 8088,
    required String pin,
  }) async {
    final uri = Uri(scheme: 'http', host: ip.trim(), port: port, path: '/api/auth');
    final res = await _http.postForm(
      uri,
      {'pin': pin.trim(), 'client': 'starfilm'},
      timeout: const Duration(seconds: 8),
    );
    if (!res.isOk) {
      throw StarTvException('Authentication failed', statusCode: res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = (data['token'] ?? '').toString().trim();
    if (token.isEmpty) {
      throw StarTvException('Empty token in /api/auth response');
    }
    final players = (data['installedPlayers'] as List<dynamic>? ?? const ['auto'])
        .map((e) => e.toString())
        .toList();
    return StarTvAuthResult(
      token: token,
      tvId: (data['tvId'] ?? '').toString(),
      deviceName: (data['deviceName'] ?? 'StarTV').toString(),
      installedPlayers: players.isEmpty ? const ['auto'] : players,
      syncApiVersion: (data['syncApiVersion'] is num)
          ? (data['syncApiVersion'] as num).toInt()
          : 0,
    );
  }

  Future<void> launchMedia({
    required StarTvDevice device,
    required String bearerToken,
    required int tmdbId,
    required MediaType mediaType,
    required String title,
    String originalTitle = '',
    int? year,
    String player = 'auto',
  }) async {
    final uri = device.baseUri.replace(path: '/api/ai-launch');
    final res = await _http.postForm(
      uri,
      {
        'tmdbId': '$tmdbId',
        'mediaType': mediaType.wireValue,
        'title': title,
        if (originalTitle.isNotEmpty) 'originalTitle': originalTitle,
        if (year != null && year > 0) 'year': '$year',
        'player': player,
      },
      headers: {'Authorization': 'Bearer $bearerToken'},
    );
    if (!res.isOk) {
      throw StarTvException('Launch failed', statusCode: res.statusCode);
    }
  }

  Future<void> launchTrailer({
    required StarTvDevice device,
    required String bearerToken,
    required int tmdbId,
    required MediaType mediaType,
    required String title,
    int? year,
  }) async {
    final uri = device.baseUri.replace(path: '/api/trailer');
    final res = await _http.postForm(
      uri,
      {
        'tmdbId': '$tmdbId',
        'mediaType': mediaType.wireValue,
        'title': title,
        if (year != null && year > 0) 'year': '$year',
      },
      headers: {'Authorization': 'Bearer $bearerToken'},
    );
    if (!res.isOk) {
      throw StarTvException('Trailer launch failed', statusCode: res.statusCode);
    }
  }

  Future<void> transferApiKey({
    required StarTvDevice device,
    required String bearerToken,
    required String provider, // 'gemini', 'tmdb', or 'kinopoisk'
    required String apiKey,
  }) async {
    if (!device.canTransferKeys) {
      throw StarTvException('Key transfer is blocked in Guest TV mode');
    }
    if (provider != 'gemini' && provider != 'tmdb' && provider != 'kinopoisk') {
      throw ArgumentError.value(provider, 'provider');
    }
    final uri = device.baseUri.replace(path: '/api/keys');
    final res = await _http.postForm(
      uri,
      {'provider': provider, 'action': 'save', 'key': apiKey.trim()},
      headers: {'Authorization': 'Bearer $bearerToken'},
    );
    if (!res.isOk) {
      throw StarTvException('Key transfer failed', statusCode: res.statusCode);
    }
  }

  Future<BackupBundle> syncLibrary({
    required StarTvDevice device,
    required String bearerToken,
    required String activeProfileId,
    required List<UserProfile> profiles,
    required Map<String, List<LibraryEntry>> entriesByProfile,
    required Map<String, Map<String, int>> deletedByProfile,
    Map<String, int> deletedProfiles = const {},
  }) async {
    if (!device.canSyncLibrary) {
      throw StarTvException('Library sync is blocked in Guest TV mode');
    }

    final payload = {
      'active': activeProfileId,
      'profiles': profiles.where((p) => !p.isDeleted).map((p) {
        final entries = entriesByProfile[p.id] ?? const <LibraryEntry>[];
        final tombstones = deletedByProfile[p.id] ?? const <String, int>{};
        return {
          'id': p.id,
          'name': p.name,
          'profileUpdatedAt': p.clientUpdatedAt,
          'library': {
            'schemaVersion': 1,
            'personalized': p.preferences.personalized,
            'filters': {
              'excludedGenres': p.preferences.excludedGenres,
              'contentLanguage': p.preferences.contentLanguage,
              'mediaType': 'movie',
              'genre': '',
              'mood': '',
              'minutes': 0,
              'guestMode': false,
            },
            'items': entries
                .where((e) => !e.isDeleted)
                .map((e) => {
                      'tmdbId': e.tmdbId,
                      'mediaType': e.mediaType.wireValue,
                      'title': e.title,
                      'originalTitle': e.originalTitle,
                      'year': e.year ?? 0,
                      'posterPath': e.posterPath,
                      if (e.tmdbRating != null) 'rating': e.tmdbRating!.toStringAsFixed(1),
                      if (e.runtimeMinutes != null) 'runtime': e.runtimeMinutes,
                      'liked': e.sentiment == Sentiment.liked,
                      'disliked': e.sentiment == Sentiment.disliked,
                      'watched': e.status == WatchStatus.watched,
                      'watching': e.status == WatchStatus.watching,
                      'watchlist': e.status == WatchStatus.watchlist,
                      'dismissed': e.status == WatchStatus.dismissed,
                      'userRating': e.userRating ?? 0,
                      'updatedAt': e.clientUpdatedAt,
                      'statusChangedAt': e.statusChangedAt,
                      'ratingChangedAt': e.ratingChangedAt,
                      'sentimentChangedAt': e.sentimentChangedAt,
                      'preserveNote': true,
                    })
                .toList(),
            'deleted': tombstones,
          },
        };
      }).toList(),
      if (deletedProfiles.isNotEmpty) 'deletedProfiles': deletedProfiles,
    };

    final uri = device.baseUri.replace(path: '/api/library-sync');
    final res = await _http.postJson(
      uri,
      payload,
      headers: {'Authorization': 'Bearer $bearerToken'},
      timeout: const Duration(seconds: 25),
    );
    if (!res.isOk) {
      throw StarTvException('Library sync failed', statusCode: res.statusCode);
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final profilesObj = decoded['profiles'] ?? decoded;
    return BackupCodec.decodeBackup(jsonEncode({
      'schemaVersion': 1,
      'profiles': profilesObj is Map<String, dynamic> ? profilesObj : decoded,
    }));
  }
}
