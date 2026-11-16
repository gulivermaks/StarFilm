import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../library/backup_codec.dart';

enum SyncStatusState {
  offlineLocal,
  notConfigured,
  syncing,
  synced,
  quotaExceeded,
  error,
}

enum SignInMergeChoice {
  mergeLocalWithCloud,
  replaceLocalWithCloud,
  cancel,
}

class LocalLibrarySummary {
  const LocalLibrarySummary({
    required this.extraProfilesCount,
    required this.entriesCount,
    required this.collectionsCount,
  });

  final int extraProfilesCount;
  final int entriesCount;
  final int collectionsCount;

  bool get hasData =>
      extraProfilesCount > 0 || entriesCount > 0 || collectionsCount > 0;
}

class SyncResultSummary {
  const SyncResultSummary({
    required this.state,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.message = '',
  });

  final SyncStatusState state;
  final int pushedCount;
  final int pulledCount;
  final String message;
}

enum CloudEntityType { profile, library, collection }

class CloudWriteOp {
  const CloudWriteOp({
    required this.entityType,
    required this.profileId,
    required this.docId,
    required this.clientUpdatedAt,
    required this.data,
  });

  final CloudEntityType entityType;
  final String profileId;
  final String docId;
  final int clientUpdatedAt;
  final Map<String, dynamic> data;
}

class CloudPulledProfile {
  const CloudPulledProfile({
    required this.profile,
    required this.serverSyncedAtMs,
  });

  final UserProfile profile;
  final int serverSyncedAtMs;
}

class CloudPulledLibraryDoc {
  const CloudPulledLibraryDoc({
    required this.docId,
    required this.entry,
    required this.serverSyncedAtMs,
  });

  final String docId;
  final LibraryEntry entry;
  final int serverSyncedAtMs;
}

class CloudPulledCollectionDoc {
  const CloudPulledCollectionDoc({
    required this.collection,
    required this.serverSyncedAtMs,
  });

  final UserCollection collection;
  final int serverSyncedAtMs;
}

abstract interface class CloudSyncBackend {
  Object get serverTimestampSentinel;

  Future<void> ensureUserDoc(String uid);

  Future<void> commitWrites(String uid, List<CloudWriteOp> writes);

  Future<List<CloudPulledProfile>> fetchProfiles(String uid);

  Future<List<CloudPulledLibraryDoc>> fetchLibrarySince(
    String uid,
    String profileId,
    int lastServerCursorMs,
  );

  Future<List<CloudPulledCollectionDoc>> fetchCollectionsSince(
    String uid,
    String profileId,
    int lastServerCursorMs,
  );
}

/// Splits Firestore write batches to stay safely below the hard 500-op Firestore limit.
List<List<T>> chunkOperations<T>(List<T> items, {int chunkSize = 450}) {
  if (chunkSize <= 0 || chunkSize > 450) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'Must be in 1..450');
  }
  final chunks = <List<T>>[];
  for (var i = 0; i < items.length; i += chunkSize) {
    final end = (i + chunkSize < items.length) ? i + chunkSize : items.length;
    chunks.add(items.sublist(i, end));
  }
  return chunks;
}

/// Serializes a compact Firestore library document (~350-450 bytes; no overview/cast/episode fields).
Map<String, dynamic> toFirestoreLibraryDoc(
  LibraryEntry entry, {
  required Object serverTimestampSentinel,
}) {
  return {
    'mediaType': entry.mediaType.wireValue,
    'tmdbId': entry.tmdbId,
    'title': entry.title.length > 200 ? entry.title.substring(0, 200) : entry.title,
    'originalTitle': entry.originalTitle.length > 200
        ? entry.originalTitle.substring(0, 200)
        : entry.originalTitle,
    'year': entry.year,
    'posterPath': entry.posterPath.length > 160
        ? entry.posterPath.substring(0, 160)
        : entry.posterPath,
    'genreIds': entry.genreIds,
    'status': entry.status.wireValue,
    'userRating': entry.userRating,
    'sentiment': entry.sentiment.wireValue,
    'statusChangedAt': entry.statusChangedAt,
    'ratingChangedAt': entry.ratingChangedAt,
    'sentimentChangedAt': entry.sentimentChangedAt,
    'clientUpdatedAt': entry.clientUpdatedAt,
    'serverSyncedAt': serverTimestampSentinel,
    'deletedAt': entry.deletedAt,
    'updatedByDevice': entry.updatedByDevice,
  };
}

LibraryEntry fromFirestoreLibraryDoc({
  required String profileId,
  required Map<String, dynamic> data,
  required int serverSyncedAtMs,
}) {
  final tmdbId = (data['tmdbId'] as num?)?.toInt() ?? 0;
  final mediaType = MediaType.fromWire((data['mediaType'] ?? 'movie').toString());
  return LibraryEntry(
    profileId: profileId,
    mediaType: mediaType,
    tmdbId: tmdbId,
    title: (data['title'] ?? '').toString(),
    originalTitle: (data['originalTitle'] ?? '').toString(),
    year: (data['year'] as num?)?.toInt(),
    posterPath: (data['posterPath'] ?? '').toString(),
    genreIds: (data['genreIds'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList(),
    status: WatchStatus.fromWire(data['status']?.toString()),
    userRating: (data['userRating'] as num?)?.toInt(),
    sentiment: Sentiment.fromWire(data['sentiment']?.toString()),
    statusChangedAt: (data['statusChangedAt'] as num?)?.toInt() ?? 0,
    ratingChangedAt: (data['ratingChangedAt'] as num?)?.toInt() ?? 0,
    sentimentChangedAt: (data['sentimentChangedAt'] as num?)?.toInt() ?? 0,
    clientUpdatedAt: (data['clientUpdatedAt'] as num?)?.toInt() ?? 0,
    serverSyncedAt: serverSyncedAtMs,
    deletedAt: (data['deletedAt'] as num?)?.toInt(),
    updatedByDevice: (data['updatedByDevice'] ?? '').toString(),
  );
}

Map<String, dynamic> toFirestoreProfileDoc(
  UserProfile profile, {
  required Object serverTimestampSentinel,
}) {
  return {
    'name': profile.name,
    'preferences': profile.preferences.toJson(),
    'clientUpdatedAt': profile.clientUpdatedAt,
    'serverSyncedAt': serverTimestampSentinel,
    'deletedAt': profile.deletedAt,
  };
}

Map<String, dynamic> toFirestoreCollectionDoc(
  UserCollection col, {
  required Object serverTimestampSentinel,
}) {
  return {
    'title': col.title.length > 60 ? col.title.substring(0, 60) : col.title,
    'mediaKeys': col.mediaKeys.take(500).toList(),
    'clientUpdatedAt': col.clientUpdatedAt,
    'serverSyncedAt': serverTimestampSentinel,
    'deletedAt': col.deletedAt,
  };
}
