import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
