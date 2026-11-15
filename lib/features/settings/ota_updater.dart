import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/models/version_comparator.dart';
import '../../core/network/starfilm_http_client.dart';

class ReleaseAssetInfo {
  const ReleaseAssetInfo({
    required this.versionName,
    required this.downloadUrl,
    required this.expectedSize,
    required this.expectedSha256,
    required this.releaseNotes,
  });

  final String versionName;
  final String downloadUrl;
  final int expectedSize;
  final String? expectedSha256;
  final String releaseNotes;
}

class OtaDownloadException implements Exception {
  const OtaDownloadException(this.code, [this.details = '']);

  final String code;
  final String details;

  @override
  String toString() => details.isEmpty ? code : '$code: $details';
}

class OtaApkInstaller {
  static const MethodChannel _channel =
      MethodChannel('app.starfilm.android/launcher');

  /// Verifies APK signing certificate against the installed app and opens Android's installer.
  static Future<String> verifyAndInstall(String apkPath) async {
    try {
      final res = await _channel.invokeMethod<String>('verifyAndInstallApk', {
        'apkPath': apkPath,
      });
      return res ?? 'error:null';
    } on PlatformException catch (e) {
      return 'error:${e.message ?? e.code}';
    } on MissingPluginException {
      return 'error:unsupported';
    }
  }
}

class OtaUpdater {
  OtaUpdater(this._http);

  final StarFilmHttpClient _http;

  static const String githubRepo = 'gulivermaks/StarFilm';
  static const String expectedApkName = 'StarFilm.apk';

  Future<ReleaseAssetInfo?> checkLatest({required String currentVersion}) async {
    final uri = Uri.https('api.github.com', '/repos/$githubRepo/releases/latest');
    final res = await _http.get(uri, headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'StarFilm-Android',
    });
    if (!res.isOk) return null;

    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) return null;
    final tag = (data['tag_name'] ?? '').toString().trim();
    if (tag.isEmpty) return null;

    if (!VersionComparator.isNewer(candidate: tag, current: currentVersion)) {
      return null;
    }

    final assets = data['assets'] as List<dynamic>? ?? const [];
    Map<String, dynamic>? apkAsset;
    for (final item in assets) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] ?? '').toString();
      if (name == expectedApkName || (name.startsWith('StarFilm') && name.endsWith('.apk'))) {
        apkAsset = item;
        break;
      }
    }
    if (apkAsset == null) return null;

    final url = (apkAsset['browser_download_url'] ?? '').toString();
    final size = (apkAsset['size'] is num) ? (apkAsset['size'] as num).toInt() : 0;
    if (url.isEmpty || size <= 0) return null;

    String? sha;
    final digest = (apkAsset['digest'] ?? '').toString();
    if (digest.startsWith('sha256:')) {
      sha = digest.substring('sha256:'.length).toLowerCase();
    }

    return ReleaseAssetInfo(
      versionName: tag.startsWith('v') ? tag.substring(1) : tag,
      downloadUrl: url,
      expectedSize: size,
      expectedSha256: sha,
      releaseNotes: (data['body'] ?? '').toString(),
    );
  }

  /// Downloads the release APK into [updatesDir], verifies byte size + SHA-256, and returns it.
  Future<File> downloadAndVerifyApk({
    required ReleaseAssetInfo release,
    required Directory updatesDir,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    final safeVer = release.versionName.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final targetFile = File('${updatesDir.path}/StarFilm-$safeVer.apk');
    final tempFile = File('${targetFile.path}.part');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final req = http.Request('GET', Uri.parse(release.downloadUrl))
      ..headers['User-Agent'] = 'StarFilm-Android';
    final response = await _http.sendStream(
      req,
      timeout: const Duration(minutes: 4),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OtaDownloadException('http_${response.statusCode}');
    }

    final totalBytes =
        (response.contentLength ?? 0) > 0 ? response.contentLength! : release.expectedSize;
    var received = 0;
    final sink = tempFile.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, totalBytes);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final verified = await verifyDownloadedApk(
      file: tempFile,
      expectedSize: release.expectedSize,
      expectedSha256: release.expectedSha256,
    );
    if (!verified) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      throw const OtaDownloadException('checksum_mismatch');
    }

    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    return tempFile.rename(targetFile.path);
  }

  static Future<bool> verifyDownloadedApk({
    required File file,
    required int expectedSize,
    String? expectedSha256,
  }) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length != expectedSize) return false;
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != expectedSha256.toLowerCase()) {
        return false;
      }
    }
    return true;
  }
}
