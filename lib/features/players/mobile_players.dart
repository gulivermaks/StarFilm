import '../../core/models/media_key.dart';

enum MobilePlayerId {
  stremio('stremio', 'Stremio', 'com.stremio.one'),
  lampa('lampa', 'Lampa', 'top.rootu.lampa'),
  num('num', 'NUM', 'com.num.client'),
  hdrezka('hdrezka', 'HDRezka', 'com.hdrezka.client'),
  webSearch('web_search', 'Browser Search', '');

  const MobilePlayerId(this.id, this.label, this.androidPackage);

  final String id;
  final String label;
  final String androidPackage;

  static MobilePlayerId fromId(String? raw) {
    for (final p in MobilePlayerId.values) {
      if (p.id == raw) return p;
    }
    return MobilePlayerId.stremio;
  }
}

class PlayerLaunchTarget {
  const PlayerLaunchTarget({
    required this.player,
    required this.clipboardText,
    this.deepLinkUri,
    this.fallbackWebUri,
    this.packageName,
  });

  final MobilePlayerId player;
  final String clipboardText;
  final Uri? deepLinkUri;
  final Uri? fallbackWebUri;
  final String? packageName;
}

/// Builds Android Intents / Deep Links and clipboard fallback targets for external players.
class PlayerLaunchPlanner {
  const PlayerLaunchPlanner._();

  static PlayerLaunchTarget plan({
    required MobilePlayerId player,
    required MediaType mediaType,
    required String title,
    String originalTitle = '',
    int? year,
    String? imdbId,
  }) {
    final searchQuery = originalTitle.trim().isNotEmpty ? originalTitle.trim() : title.trim();
    final copyText = year != null && year > 0 ? '$searchQuery $year' : searchQuery;
    final webUri = Uri.https('www.google.com', '/search', {'q': '$copyText дивитися онлайн'});

    if (player == MobilePlayerId.stremio && imdbId != null && imdbId.startsWith('tt')) {
      final kind = mediaType == MediaType.tv ? 'series' : 'movie';
      return PlayerLaunchTarget(
        player: player,
        clipboardText: copyText,
        deepLinkUri: Uri.parse('stremio:///detail/$kind/$imdbId'),
        fallbackWebUri: webUri,
        packageName: player.androidPackage,
      );
    }

    if (player == MobilePlayerId.webSearch) {
      return PlayerLaunchTarget(
        player: player,
        clipboardText: copyText,
        deepLinkUri: webUri,
        fallbackWebUri: webUri,
      );
    }

    // For Lampa / NUM / HDRezka where direct deep links vary across APK builds,
    // copy title to clipboard and launch the installed app (or browser search fallback).
    return PlayerLaunchTarget(
      player: player,
      clipboardText: copyText,
      packageName: player.androidPackage.isEmpty ? null : player.androidPackage,
      fallbackWebUri: webUri,
    );
  }

  static Uri? youtubeTrailerUri(String? youtubeKey, {required String title, int? year}) {
    if (youtubeKey != null && youtubeKey.trim().isNotEmpty) {
      return Uri.https('www.youtube.com', '/watch', {'v': youtubeKey.trim()});
    }
    final q = year != null && year > 0 ? '$title $year trailer' : '$title trailer';
    return Uri.https('www.youtube.com', '/results', {'search_query': q});
  }
}
