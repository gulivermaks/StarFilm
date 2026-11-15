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

  test('downloadAndVerifyApk downloads stream, verifies SHA-256, and deletes invalid downloads',
      () async {
    final payload = utf8.encode('fake-apk-binary-payload');
    final digest = sha256.convert(payload).toString();
    var returnCorrupt = false;
    var statusCode = 200;

    final mockHttp = MockClient((req) async {
      if (statusCode != 200) {
        return http.Response('err', statusCode);
      }
      return http.Response.bytes(
        returnCorrupt ? utf8.encode('corrupted-payload-bytes') : payload,
        200,
        headers: {'content-length': '${payload.length}'},
      );
    });

    final updater = OtaUpdater(StarFilmHttpClient(client: mockHttp));
    final tmpDir = await Directory.systemTemp.createTemp('starfilm_ota_dl_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final validRelease = ReleaseAssetInfo(
      versionName: '0.06',
      downloadUrl: 'https://github.com/gulivermaks/StarFilm/releases/download/v0.06/StarFilm.apk',
      expectedSize: payload.length,
      expectedSha256: digest,
      releaseNotes: 'OTA test',
    );

    final progressEvents = <int>[];
    final file = await updater.downloadAndVerifyApk(
      release: validRelease,
      updatesDir: tmpDir,
      onProgress: (received, total) => progressEvents.add(received),
    );
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), payload);
    expect(progressEvents.last, payload.length);

    returnCorrupt = true;
    await file.delete();
    await expectLater(
      updater.downloadAndVerifyApk(release: validRelease, updatesDir: tmpDir),
      throwsA(
        isA<OtaDownloadException>().having((e) => e.code, 'code', 'checksum_mismatch'),
      ),
    );
    expect(await file.exists(), isFalse);
    expect(await File('${file.path}.part').exists(), isFalse);

    returnCorrupt = false;
    statusCode = 404;
    await expectLater(
      updater.downloadAndVerifyApk(release: validRelease, updatesDir: tmpDir),
      throwsA(
        isA<OtaDownloadException>().having((e) => e.code, 'code', 'http_404'),
      ),
    );
  });
}
