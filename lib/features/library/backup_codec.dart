import 'dart:convert';

import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';

class UserCollection {
  const UserCollection({
    required this.id,
    required this.profileId,
    required this.title,
    required this.mediaKeys,
    this.clientUpdatedAt = 0,
    this.serverSyncedAt = 0,
    this.deletedAt,
  });

  final String id;
  final String profileId;
  final String title;
  final List<String> mediaKeys;
  final int clientUpdatedAt;
  final int serverSyncedAt;
  final int? deletedAt;

  bool get isDeleted => deletedAt != null && deletedAt! > 0;
}

class ImportedProfileBundle {
  const ImportedProfileBundle({
    required this.profile,
    required this.entries,
    required this.collections,
    required this.deletedTombstones,
  });

  final UserProfile profile;
  final List<LibraryEntry> entries;
  final List<UserCollection> collections;
  final Map<String, int> deletedTombstones;
}

class BackupBundle {
  const BackupBundle({
    required this.sourceFormat,
    required this.activeProfileId,
    required this.profiles,
  });

  final String sourceFormat; // 'starfilm' or 'startv'
  final String activeProfileId;
  final List<ImportedProfileBundle> profiles;
}

/// Encodes/decodes both `starfilm_backup.json` and StarTV (`SettingsBackup` / `TasteStore` v1) JSON.
class BackupCodec {
  const BackupCodec._();

  static const int starfilmSchemaVersion = 1;

  static String encodeStarFilmBackup({
    required String activeProfileId,
    required List<UserProfile> profiles,
    required Map<String, List<LibraryEntry>> entriesByProfile,
    required Map<String, List<UserCollection>> collectionsByProfile,
    required Map<String, Map<String, int>> deletedByProfile,
  }) {
    final payload = {
      'app': 'StarFilm',
      'schemaVersion': starfilmSchemaVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'activeProfileId': activeProfileId,
      'profiles': profiles.where((p) => !p.isDeleted).map((p) {
        final entries = (entriesByProfile[p.id] ?? const []).where((e) => !e.isDeleted);
        final collections =
            (collectionsByProfile[p.id] ?? const []).where((c) => !c.isDeleted);
        final tombstones = deletedByProfile[p.id] ?? const {};
        return {
          'id': p.id,
          'name': p.name,
          'clientUpdatedAt': p.clientUpdatedAt,
          'preferences': p.preferences.toJson(),
          'items': entries
              .map((e) => {
                    'mediaType': e.mediaType.wireValue,
                    'tmdbId': e.tmdbId,
                    'title': e.title,
                    'originalTitle': e.originalTitle,
                    'year': e.year,
                    'posterPath': e.posterPath,
                    'genreIds': e.genreIds,
                    'tmdbRating': e.tmdbRating,
                    'runtimeMinutes': e.runtimeMinutes,
                    'status': e.status.wireValue,
                    'userRating': e.userRating,
                    'sentiment': e.sentiment.wireValue,
                    'statusChangedAt': e.statusChangedAt,
                    'ratingChangedAt': e.ratingChangedAt,
                    'sentimentChangedAt': e.sentimentChangedAt,
                    'clientUpdatedAt': e.clientUpdatedAt,
                  })
              .toList(),
          'collections': collections
              .map((c) => {
                    'id': c.id,
                    'title': c.title,
                    'mediaKeys': c.mediaKeys,
                    'clientUpdatedAt': c.clientUpdatedAt,
                  })
              .toList(),
          'deleted': tombstones,
        };
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static BackupBundle decodeBackup(String rawJson, {int? fallbackNowMs}) {
    final nowMs = fallbackNowMs ?? DateTime.now().millisecondsSinceEpoch;
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup root must be a JSON object');
    }

    if (decoded['app'] == 'StarFilm' && decoded['profiles'] is List) {
      return _decodeStarFilm(decoded, nowMs);
    }

    // StarTV SettingsBackup or TasteStore v1 backup
    if (decoded['schemaVersion'] == 1) {
      return _decodeStarTv(decoded, nowMs);
    }

    throw const FormatException('Unsupported backup format or schemaVersion');
  }

  static BackupBundle _decodeStarFilm(Map<String, dynamic> root, int nowMs) {
    final profilesList = root['profiles'] as List<dynamic>;
    final bundles = <ImportedProfileBundle>[];
    for (final rawProfile in profilesList) {
      if (rawProfile is! Map<String, dynamic>) continue;
      final id = (rawProfile['id'] ?? '').toString().trim();
      if (!UserProfile.isValidId(id)) continue;
      final name = (rawProfile['name'] ?? (id == 'main' ? 'Головний' : id)).toString();
      final prefsJson = rawProfile['preferences'] is Map<String, dynamic>
          ? rawProfile['preferences'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final profile = UserProfile(
        id: id,
        name: name,
        preferences: ProfilePreferences.fromJson(prefsJson),
        clientUpdatedAt: _asInt(rawProfile['clientUpdatedAt']) ?? nowMs,
      );

      final entries = <LibraryEntry>[];
      for (final rawItem in (rawProfile['items'] as List<dynamic>? ?? const [])) {
        if (rawItem is! Map<String, dynamic>) continue;
        final tmdbId = _asInt(rawItem['tmdbId']) ?? 0;
        if (tmdbId <= 0) continue;
        final mediaType = MediaType.fromWire((rawItem['mediaType'] ?? 'movie').toString());
        final title = (rawItem['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final userRating = _asInt(rawItem['userRating']);
        entries.add(
          LibraryEntry(
            profileId: id,
            mediaType: mediaType,
            tmdbId: tmdbId,
            title: title,
            originalTitle: (rawItem['originalTitle'] ?? '').toString(),
            year: _asInt(rawItem['year']),
            posterPath: (rawItem['posterPath'] ?? '').toString(),
            genreIds: (rawItem['genreIds'] as List<dynamic>? ?? const [])
                .map(_asInt)
                .whereType<int>()
                .toList(),
            tmdbRating: _asDouble(rawItem['tmdbRating']),
            runtimeMinutes: _asInt(rawItem['runtimeMinutes']),
            status: WatchStatus.fromWire(rawItem['status']?.toString()),
            userRating: (userRating != null && userRating > 0) ? userRating : null,
            sentiment: Sentiment.fromWire(rawItem['sentiment']?.toString()),
            statusChangedAt: _asInt(rawItem['statusChangedAt']) ?? nowMs,
            ratingChangedAt: _asInt(rawItem['ratingChangedAt']) ?? nowMs,
            sentimentChangedAt: _asInt(rawItem['sentimentChangedAt']) ?? nowMs,
            clientUpdatedAt: _asInt(rawItem['clientUpdatedAt']) ?? nowMs,
          ).normalized(nowMs: nowMs),
        );
      }

      final collections = <UserCollection>[];
      for (final rawCol in (rawProfile['collections'] as List<dynamic>? ?? const [])) {
        if (rawCol is! Map<String, dynamic>) continue;
        final cid = (rawCol['id'] ?? '').toString().trim();
        final ctitle = (rawCol['title'] ?? '').toString().trim();
        if (cid.isEmpty || ctitle.isEmpty) continue;
        final keys = (rawCol['mediaKeys'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .where((k) => MediaKey.tryParse(k) != null)
            .toList();
        collections.add(UserCollection(
          id: cid,
          profileId: id,
          title: ctitle.length > 60 ? ctitle.substring(0, 60) : ctitle,
          mediaKeys: keys,
          clientUpdatedAt: _asInt(rawCol['clientUpdatedAt']) ?? nowMs,
        ));
      }

      final tombstones = <String, int>{};
      final rawDeleted = rawProfile['deleted'];
      if (rawDeleted is Map) {
        rawDeleted.forEach((k, v) {
          final ts = _asInt(v);
          if (ts != null && ts > 0 && MediaKey.tryParse(k.toString()) != null) {
            tombstones[k.toString()] = ts;
          }
        });
      }

      bundles.add(ImportedProfileBundle(
        profile: profile,
        entries: entries,
        collections: collections,
        deletedTombstones: tombstones,
      ));
    }

    return BackupBundle(
      sourceFormat: 'starfilm',
      activeProfileId: (root['activeProfileId'] ?? 'main').toString(),
      profiles: bundles,
    );
  }

  static BackupBundle _decodeStarTv(Map<String, dynamic> root, int nowMs) {
    final bundles = <ImportedProfileBundle>[];
    String activeId = 'main';

    final profilesObj = root['profiles'];
    if (profilesObj is Map<String, dynamic> && profilesObj['items'] is List) {
      activeId = (profilesObj['active'] ?? 'main').toString();
      for (final rawP in profilesObj['items'] as List<dynamic>) {
        if (rawP is! Map<String, dynamic>) continue;
        final id = (rawP['id'] ?? '').toString().trim();
        if (!UserProfile.isValidId(id)) continue;
        final lib = rawP['library'];
        if (lib is! Map<String, dynamic>) continue;
        final name = (rawP['name'] ?? '').toString().trim();
        bundles.add(_decodeStarTvTasteStore(
          profileId: id,
          profileName: name.isEmpty ? (id == 'main' ? 'Головний' : id) : name,
          storeJson: lib,
          nowMs: nowMs,
        ));
      }
    } else if (root['library'] is Map<String, dynamic>) {
      bundles.add(_decodeStarTvTasteStore(
        profileId: 'main',
        profileName: 'Головний',
        storeJson: root['library'] as Map<String, dynamic>,
        nowMs: nowMs,
      ));
    } else if (root['items'] is List) {
      bundles.add(_decodeStarTvTasteStore(
        profileId: 'main',
        profileName: 'Головний',
        storeJson: root,
        nowMs: nowMs,
      ));
    } else {
      throw const FormatException('Missing library data in StarTV backup');
    }

    return BackupBundle(
      sourceFormat: 'startv',
      activeProfileId: activeId,
      profiles: bundles,
    );
  }

  static ImportedProfileBundle _decodeStarTvTasteStore({
    required String profileId,
    required String profileName,
    required Map<String, dynamic> storeJson,
    required int nowMs,
  }) {
    final filters = storeJson['filters'] is Map<String, dynamic>
        ? storeJson['filters'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final prefs = ProfilePreferences.fromJson({
      'excludedGenres': filters['excludedGenres'] ?? const [],
      'contentLanguage': filters['contentLanguage'] ?? 'uk',
      'personalized': storeJson['personalized'] ?? true,
    });

    final profile = UserProfile(
      id: profileId,
      name: profileName,
      preferences: prefs,
      clientUpdatedAt: _asInt(storeJson['profileUpdatedAt']) ?? nowMs,
    );

    final entries = <LibraryEntry>[];
    for (final rawItem in (storeJson['items'] as List<dynamic>? ?? const [])) {
      if (rawItem is! Map<String, dynamic>) continue;
      final tmdbId = _asInt(rawItem['tmdbId']) ?? 0;
      if (tmdbId <= 0) continue;
      final title = (rawItem['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final mediaType = MediaType.fromWire((rawItem['mediaType'] ?? 'movie').toString());

      // Convert StarTV boolean flags to single StarFilm WatchStatus.
      // Intentionally ignores StarTV `progressNote` per StarFilm v1 spec.
      WatchStatus status = WatchStatus.none;
      if (rawItem['dismissed'] == true) {
        status = WatchStatus.dismissed;
      } else if (rawItem['watched'] == true) {
        status = WatchStatus.watched;
      } else if (rawItem['watching'] == true) {
        status = WatchStatus.watching;
      } else if (rawItem['watchlist'] == true) {
        status = WatchStatus.watchlist;
      }

      Sentiment sentiment = Sentiment.neutral;
      if (rawItem['liked'] == true) {
        sentiment = Sentiment.liked;
      } else if (rawItem['disliked'] == true) {
        sentiment = Sentiment.disliked;
      }

      final rating = _asInt(rawItem['userRating']);
      final itemUpdatedAt = _asInt(rawItem['updatedAt']) ?? nowMs;
      entries.add(
        LibraryEntry(
          profileId: profileId,
          mediaType: mediaType,
          tmdbId: tmdbId,
          title: title,
          originalTitle: (rawItem['originalTitle'] ?? '').toString(),
          year: _asInt(rawItem['year']),
          posterPath: (rawItem['posterPath'] ?? '').toString(),
          tmdbRating: _asDouble(rawItem['rating']),
          runtimeMinutes: _asInt(rawItem['runtime']),
          status: status,
          userRating: (rating != null && rating > 0) ? rating : null,
          sentiment: sentiment,
          statusChangedAt: _asInt(rawItem['statusChangedAt']) ?? itemUpdatedAt,
          ratingChangedAt: _asInt(rawItem['ratingChangedAt']) ?? itemUpdatedAt,
          sentimentChangedAt: _asInt(rawItem['sentimentChangedAt']) ?? itemUpdatedAt,
          clientUpdatedAt: itemUpdatedAt,
        ).normalized(nowMs: nowMs),
      );
    }

    final tombstones = <String, int>{};
    final rawDeleted = storeJson['deleted'];
    if (rawDeleted is Map) {
      rawDeleted.forEach((k, v) {
        final ts = _asInt(v);
        if (ts != null && ts > 0 && MediaKey.tryParse(k.toString()) != null) {
          tombstones[k.toString()] = ts;
        }
      });
    }

    return ImportedProfileBundle(
      profile: profile,
      entries: entries,
      collections: const [],
      deletedTombstones: tombstones,
    );
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
