import 'package:flutter_test/flutter_test.dart';
import 'package:starfilm/core/models/media_key.dart';
import 'package:starfilm/features/players/mobile_players.dart';

void main() {
  group('PlayerLaunchPlanner', () {
    test('uses localized title in clipboardText and falls back to originalTitle', () {
      final localized = PlayerLaunchPlanner.plan(
        player: MobilePlayerId.hdrezka,
        mediaType: MediaType.movie,
        title: 'Початок',
        originalTitle: 'Inception',
        year: 2010,
      );

      expect(localized.clipboardText, 'Початок 2010');
      expect(localized.packageName, 'to.pda.falcofemoralis.hdrezkaapp');
      expect(localized.fallbackWebUri?.queryParameters['q'], 'Початок 2010 дивитися онлайн');

      final fallback = PlayerLaunchPlanner.plan(
        player: MobilePlayerId.lampa,
        mediaType: MediaType.movie,
        title: '   ',
        originalTitle: 'Inception',
        year: 2010,
      );
      expect(fallback.clipboardText, 'Inception 2010');
      expect(fallback.packageName, 'top.rootu.lampa');
    });

    test('builds Stremio deep link when imdbId is available', () {
      final target = PlayerLaunchPlanner.plan(
        player: MobilePlayerId.stremio,
        mediaType: MediaType.tv,
        title: 'Пуститися берега',
        originalTitle: 'Breaking Bad',
        year: 2008,
        imdbId: 'tt0903747',
      );

      expect(target.deepLinkUri, Uri.parse('stremio:///detail/series/tt0903747'));
      expect(target.packageName, 'com.stremio.one');
      expect(target.clipboardText, 'Пуститися берега 2008');
    });
  });

  group('MobilePlayerLauncher', () {
    test('tries deep link, then package launcher, then web fallback', () async {
      final events = <String>[];
      final target = PlayerLaunchPlanner.plan(
        player: MobilePlayerId.hdrezka,
        mediaType: MediaType.movie,
        title: 'Дюна',
        originalTitle: 'Dune',
        year: 2021,
      );

      final openedPackage = await MobilePlayerLauncher.launch(
        target,
        openUri: (uri) async {
          events.add('uri:$uri');
          return true;
        },
        openPackage: (pkg) async {
          events.add('pkg:$pkg');
          return true;
        },
      );

      expect(openedPackage, isTrue);
      expect(events, ['pkg:to.pda.falcofemoralis.hdrezkaapp']);

      events.clear();
      final openedWebFallback = await MobilePlayerLauncher.launch(
        target,
        openUri: (uri) async {
          events.add('uri:${uri.host}');
          return true;
        },
        openPackage: (pkg) async {
          events.add('pkg:$pkg');
          return false;
        },
      );

      expect(openedWebFallback, isTrue);
      expect(events, ['pkg:to.pda.falcofemoralis.hdrezkaapp', 'uri:www.google.com']);
    });
  });
}
