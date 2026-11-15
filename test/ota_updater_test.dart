import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starfilm/core/network/starfilm_http_client.dart';
import 'package:starfilm/features/settings/ota_updater.dart';

void main() {
  test('OtaUpdater detects newer +0.01 release and verifies file size + sha256', () async {
    final mockHttp = MockClient((req) async {
      if (req.url.host == 'api.github.com') {
        return http.Response(
          jsonEncode({
            'tag_name': 'v0.70',
            'body': 'Release 0.70',
            'assets': [
              {
                'name': 'StarFilm.apk',
                'browser_download_url': 'https://github.com/gulivermaks/StarFilm/releases/download/v0.70/StarFilm.apk',
                'size': 5,
                'digest': 'sha256:${sha256.convert(utf8.encode('hello'))}',
              }
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final updater = OtaUpdater(StarFilmHttpClient(client: mockHttp));
    final info = await updater.checkLatest(currentVersion: '0.69');
    expect(info, isNotNull);
    expect(info!.versionName, '0.70');

    final sameOrOlder = await updater.checkLatest(currentVersion: '0.70');
    expect(sameOrOlder, isNull);

    final tmpDir = await Directory.systemTemp.createTemp('starfilm_ota_');
    addTearDown(() => tmpDir.delete(recursive: true));
    final apkFile = File('${tmpDir.path}/StarFilm.apk');
    await apkFile.writeAsString('hello');

    expect(
      await OtaUpdater.verifyDownloadedApk(
        file: apkFile,
        expectedSize: info.expectedSize,
        expectedSha256: info.expectedSha256,
      ),
      isTrue,
    );
    expect(
      await OtaUpdater.verifyDownloadedApk(
        file: apkFile,
        expectedSize: 999,
        expectedSha256: info.expectedSha256,
      ),
      isFalse,
    );
  });
}
