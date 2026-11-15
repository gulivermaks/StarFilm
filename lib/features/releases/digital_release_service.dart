import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/library_entry.dart';
import '../../core/models/media_key.dart';
import '../search/tmdb_client.dart';

class DigitalReleaseMatch {
  const DigitalReleaseMatch({
    required this.entry,
    required this.releaseDate,
  });

  final LibraryEntry entry;
  final DateTime releaseDate;
}

/// Checks Watchlist MOVIES ONLY (never series/episodes) for recent TMDB digital
/// releases (`type == 4`) and records notified items to avoid repeat alerts.
class DigitalReleaseService {
  DigitalReleaseService(this._tmdb);

  final TmdbClient _tmdb;

  static const String _prefNotifiedIds = 'starfilm.notified_digital_releases';
  static const int maxEntriesPerCheck = 20;
  static const int recentWindowDays = 60;

  Future<List<DigitalReleaseMatch>> findNewlyReleasedMovies({
    required String tmdbApiKey,
    required List<LibraryEntry> entries,
    DateTime? now,
    bool markNotified = true,
  }) async {
    if (tmdbApiKey.trim().isEmpty) return const [];

    final current = now ?? DateTime.now();
    final watchlistMovies = entries
        .where(
          (e) =>
              !e.isDeleted &&
              e.mediaType == MediaType.movie &&
              e.status == WatchStatus.watchlist,
        )
        .take(maxEntriesPerCheck)
        .toList();
    if (watchlistMovies.isEmpty) return const [];

    final prefs = await SharedPreferences.getInstance();
    final alreadyNotified =
        (prefs.getStringList(_prefNotifiedIds) ?? const <String>[]).toSet();

    final matches = <DigitalReleaseMatch>[];
    for (final entry in watchlistMovies) {
      if (alreadyNotified.contains(entry.keyString)) continue;
      final digitalDate = await _tmdb.fetchMovieDigitalReleaseDate(
        apiKey: tmdbApiKey,
        tmdbId: entry.tmdbId,
      );
      if (digitalDate == null) continue;
      if (digitalDate.isAfter(current)) continue;
      if (current.difference(digitalDate).inDays > recentWindowDays) continue;

      matches.add(DigitalReleaseMatch(entry: entry, releaseDate: digitalDate));
      alreadyNotified.add(entry.keyString);
    }

    if (markNotified && matches.isNotEmpty) {
      await prefs.setStringList(_prefNotifiedIds, alreadyNotified.toList());
    }
    return matches;
  }
}
