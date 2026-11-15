import 'media_key.dart';

/// Canonical library entry shared by Drift, Firestore mini-slice, and StarTV sync.
/// Intentionally excludes any episode/season user progress fields.
class LibraryEntry {
  const LibraryEntry({
    required this.profileId,
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    this.originalTitle = '',
    this.year,
    this.posterPath = '',
    this.genreIds = const [],
    this.tmdbRating,
    this.runtimeMinutes,
    this.status = WatchStatus.none,
    this.userRating,
    this.sentiment = Sentiment.neutral,
    this.statusChangedAt = 0,
    this.ratingChangedAt = 0,
    this.sentimentChangedAt = 0,
    this.clientUpdatedAt = 0,
    this.serverSyncedAt = 0,
    this.deletedAt,
    this.updatedByDevice = '',
  });

  final String profileId;
  final MediaType mediaType;
  final int tmdbId;
  final String title;
  final String originalTitle;
  final int? year;
  final String posterPath;
  final List<int> genreIds;
  final double? tmdbRating;
  final int? runtimeMinutes;
  final WatchStatus status;
  final int? userRating;
  final Sentiment sentiment;
  final int statusChangedAt;
  final int ratingChangedAt;
  final int sentimentChangedAt;
  final int clientUpdatedAt;
  final int serverSyncedAt;
  final int? deletedAt;
  final String updatedByDevice;

  MediaKey get mediaKey => MediaKey(mediaType, tmdbId);
  String get keyString => mediaKey.value;
  String get firestoreId => mediaKey.firestoreId;
  bool get isDeleted => deletedAt != null && deletedAt! > 0;

  bool get isExcludedFromRecommendations =>
      !isDeleted &&
      (status == WatchStatus.watched ||
          status == WatchStatus.watching ||
          status == WatchStatus.watchlist ||
          status == WatchStatus.dismissed ||
          sentiment == Sentiment.disliked);

  /// Enforces domain invariants from spec section 6:
  /// - `userRating` (1..10) is allowed only for `watched` and `watching`.
  /// - Setting a rating on `none` or `watchlist` auto-transitions status to `watched`.
  /// - Setting `dismissed` clears `liked`, `watchlist`, and `watching`.
  LibraryEntry normalized({required int nowMs, String? deviceId}) {
    var nextStatus = status;
    var nextSentiment = sentiment;
    int? nextRating = userRating;

    if (nextRating != null && (nextRating < 1 || nextRating > 10)) {
      nextRating = null;
    }

    if (nextStatus == WatchStatus.dismissed) {
      if (nextSentiment == Sentiment.liked) {
        nextSentiment = Sentiment.neutral;
      }
      nextRating = null;
    } else if (nextRating != null) {
      if (nextStatus == WatchStatus.none || nextStatus == WatchStatus.watchlist) {
        nextStatus = WatchStatus.watched;
      }
    }

    return LibraryEntry(
      profileId: profileId,
      mediaType: mediaType,
      tmdbId: tmdbId,
      title: title.trim(),
      originalTitle: originalTitle.trim(),
      year: year,
      posterPath: posterPath.trim(),
      genreIds: genreIds.toSet().toList(),
      tmdbRating: tmdbRating,
      runtimeMinutes: runtimeMinutes,
      status: nextStatus,
      userRating: nextRating,
      sentiment: nextSentiment,
      statusChangedAt: statusChangedAt > 0 ? statusChangedAt : nowMs,
      ratingChangedAt: ratingChangedAt > 0 ? ratingChangedAt : nowMs,
      sentimentChangedAt: sentimentChangedAt > 0 ? sentimentChangedAt : nowMs,
      clientUpdatedAt: clientUpdatedAt > 0 ? clientUpdatedAt : nowMs,
      serverSyncedAt: serverSyncedAt,
      deletedAt: deletedAt,
      updatedByDevice: deviceId ?? updatedByDevice,
    );
  }

  /// Per-field timestamp merge so rating on phone and status on TV never overwrite each other.
  static LibraryEntry merge(LibraryEntry local, LibraryEntry remote) {
    final localDeleted = local.deletedAt ?? 0;
    final remoteDeleted = remote.deletedAt ?? 0;

    final maxLocalTouch = [
      local.clientUpdatedAt,
      local.statusChangedAt,
      local.ratingChangedAt,
      local.sentimentChangedAt,
    ].reduce((a, b) => a > b ? a : b);

    final maxRemoteTouch = [
      remote.clientUpdatedAt,
      remote.statusChangedAt,
      remote.ratingChangedAt,
      remote.sentimentChangedAt,
    ].reduce((a, b) => a > b ? a : b);

    // Handle tombstones first.
    if (localDeleted > 0 || remoteDeleted > 0) {
      final latestDelete = localDeleted >= remoteDeleted ? localDeleted : remoteDeleted;
      final latestLive = maxLocalTouch >= maxRemoteTouch ? maxLocalTouch : maxRemoteTouch;
      if (latestDelete >= latestLive) {
        final winner = localDeleted >= remoteDeleted ? local : remote;
        return LibraryEntry(
          profileId: local.profileId,
          mediaType: local.mediaType,
          tmdbId: local.tmdbId,
          title: winner.title.isNotEmpty ? winner.title : local.title,
          originalTitle: winner.originalTitle.isNotEmpty ? winner.originalTitle : local.originalTitle,
          year: winner.year ?? local.year,
          posterPath: winner.posterPath.isNotEmpty ? winner.posterPath : local.posterPath,
          genreIds: winner.genreIds.isNotEmpty ? winner.genreIds : local.genreIds,
          tmdbRating: winner.tmdbRating ?? local.tmdbRating,
          runtimeMinutes: winner.runtimeMinutes ?? local.runtimeMinutes,
          status: WatchStatus.none,
          userRating: null,
          sentiment: Sentiment.neutral,
          statusChangedAt: latestDelete,
          ratingChangedAt: latestDelete,
          sentimentChangedAt: latestDelete,
          clientUpdatedAt: latestDelete,
          serverSyncedAt: remote.serverSyncedAt > local.serverSyncedAt
              ? remote.serverSyncedAt
              : local.serverSyncedAt,
          deletedAt: latestDelete,
          updatedByDevice: winner.updatedByDevice,
        );
      }
    }

    final useRemoteStatus = remote.statusChangedAt > local.statusChangedAt ||
        (remote.statusChangedAt == local.statusChangedAt &&
            remote.clientUpdatedAt > local.clientUpdatedAt);
    final useRemoteRating = remote.ratingChangedAt > local.ratingChangedAt ||
        (remote.ratingChangedAt == local.ratingChangedAt &&
            remote.clientUpdatedAt > local.clientUpdatedAt);
    final useRemoteSentiment = remote.sentimentChangedAt > local.sentimentChangedAt ||
        (remote.sentimentChangedAt == local.sentimentChangedAt &&
            remote.clientUpdatedAt > local.clientUpdatedAt);

    final mergedStatus = useRemoteStatus ? remote.status : local.status;
    var mergedRating = useRemoteRating ? remote.userRating : local.userRating;
    var mergedSentiment = useRemoteSentiment ? remote.sentiment : local.sentiment;

    // Re-apply invariants after combining independent fields.
    if (mergedStatus == WatchStatus.dismissed) {
      if (mergedSentiment == Sentiment.liked) mergedSentiment = Sentiment.neutral;
      mergedRating = null;
    }

    final newerMeta = remote.clientUpdatedAt >= local.clientUpdatedAt ? remote : local;
    final olderMeta = identical(newerMeta, remote) ? local : remote;

    return LibraryEntry(
      profileId: local.profileId,
      mediaType: local.mediaType,
      tmdbId: local.tmdbId,
      title: newerMeta.title.isNotEmpty ? newerMeta.title : olderMeta.title,
      originalTitle: newerMeta.originalTitle.isNotEmpty
          ? newerMeta.originalTitle
          : olderMeta.originalTitle,
      year: newerMeta.year ?? olderMeta.year,
      posterPath: newerMeta.posterPath.isNotEmpty ? newerMeta.posterPath : olderMeta.posterPath,
      genreIds: newerMeta.genreIds.isNotEmpty ? newerMeta.genreIds : olderMeta.genreIds,
      tmdbRating: newerMeta.tmdbRating ?? olderMeta.tmdbRating,
      runtimeMinutes: newerMeta.runtimeMinutes ?? olderMeta.runtimeMinutes,
      status: mergedStatus,
      userRating: mergedRating,
      sentiment: mergedSentiment,
      statusChangedAt: useRemoteStatus ? remote.statusChangedAt : local.statusChangedAt,
      ratingChangedAt: useRemoteRating ? remote.ratingChangedAt : local.ratingChangedAt,
      sentimentChangedAt:
          useRemoteSentiment ? remote.sentimentChangedAt : local.sentimentChangedAt,
      clientUpdatedAt: maxRemoteTouch > maxLocalTouch ? maxRemoteTouch : maxLocalTouch,
      serverSyncedAt: remote.serverSyncedAt > local.serverSyncedAt
          ? remote.serverSyncedAt
          : local.serverSyncedAt,
      deletedAt: null,
      updatedByDevice: newerMeta.updatedByDevice.isNotEmpty
          ? newerMeta.updatedByDevice
          : olderMeta.updatedByDevice,
    );
  }
}
