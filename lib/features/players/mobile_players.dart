import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/media_key.dart';

enum MobilePlayerId {
  stremio('stremio', 'Stremio', 'com.stremio.one'),
  lampa('lampa', 'Lampa', 'top.rootu.lampa'),
  num('num', 'NUM', 'com.num.client'),
  hdrezka('hdrezka', 'HDRezka', 'to.pda.falcofemoralis.hdrezkaapp'),
  vlc('vlc', 'VLC', 'org.videolan.vlc'),
  mxPlayer('mx_player', 'MX Player', 'com.mxtech.videoplayer.ad'),
  kodi('kodi', 'Kodi', 'org.xbmc.kodi'),
  torrServe('torrserve', 'TorrServe', 'ru.yourok.torrserve'),
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
    final searchQuery = title.trim().isNotEmpty ? title.trim() : originalTitle.trim();
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

/// Launches external Android player packages via platform channel with URI/web fallback.
class MobilePlayerLauncher {
  const MobilePlayerLauncher._();

  static const MethodChannel _channel = MethodChannel('app.starfilm.android/launcher');

  static Future<bool> launchAndroidPackage(String packageName) async {
    final trimmed = packageName.trim();
    if (trimmed.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'launchPackage',
        {'packageName': trimmed},
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> launch(
    PlayerLaunchTarget target, {
    Future<bool> Function(Uri uri)? openUri,
    Future<bool> Function(String packageName)? openPackage,
  }) async {
    final uriOpener = openUri ??
        ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
    final pkgOpener = openPackage ?? launchAndroidPackage;

    if (target.deepLinkUri != null) {
      try {
        if (await uriOpener(target.deepLinkUri!)) return true;
      } catch (_) {}
    }
    if (target.packageName != null && target.packageName!.isNotEmpty) {
      if (await pkgOpener(target.packageName!)) return true;
    }
    if (target.fallbackWebUri != null) {
      try {
        return await uriOpener(target.fallbackWebUri!);
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}
