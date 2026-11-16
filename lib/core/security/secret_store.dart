import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/startv/startv_models.dart';

/// Stores sensitive user credentials strictly on-device in Android Keystore / SecureStorage.
/// Never uploaded to Firebase or written to logs/backups.
class SecretStore {
  SecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _tmdbKey = 'starfilm.tmdb_api_key';
  static const String _geminiKey = 'starfilm.gemini_api_key';
  static const String _kinopoiskKey = 'starfilm.kinopoisk_api_key';
  static const String _deviceIdKey = 'starfilm.device_id';
  static const String _starTvDevicesKey = 'starfilm.startv_devices';
  static const String _starTvTokenPrefix = 'starfilm.startv_token.';

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // EncryptedSharedPreferences can fail after device migration or keystore reset;
      // discard only the unreadable entry so app startup never blocks.
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on MissingPluginException {
      // Allow test fakes without full channel support.
    } on PlatformException {
      try {
        await _storage.delete(key: key);
        await _storage.write(key: key, value: value);
      } catch (_) {}
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      // No-op in headless tests.
    } on PlatformException {
      // Ignore delete failures on corrupted keystore entries.
    }
  }

  Future<String> getTmdbKey() async => (await _safeRead(_tmdbKey)) ?? '';
  Future<void> setTmdbKey(String value) => _safeWrite(_tmdbKey, value.trim());

  Future<String> getGeminiKey() async => (await _safeRead(_geminiKey)) ?? '';
  Future<void> setGeminiKey(String value) => _safeWrite(_geminiKey, value.trim());

  Future<String> getKinopoiskKey() async => (await _safeRead(_kinopoiskKey)) ?? '';
  Future<void> setKinopoiskKey(String value) =>
      _safeWrite(_kinopoiskKey, value.trim());

  Future<String> getOrCreateDeviceId() async {
    final existing = await _safeRead(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final hex = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    await _safeWrite(_deviceIdKey, hex);
    return hex;
  }

  Future<List<StarTvDevice>> loadStarTvDevices() async {
    final raw = await _safeRead(_starTvDevicesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(StarTvDevice.fromJson)
          .where((d) => d.tvId.isNotEmpty || d.ip.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveStarTvDevice(StarTvDevice device, String bearerToken) async {
    final existing = (await loadStarTvDevices()).toList();
    existing.removeWhere((d) =>
        (device.tvId.isNotEmpty && d.tvId == device.tvId) || d.ip == device.ip);
    existing.insert(0, device);
    await _safeWrite(
      _starTvDevicesKey,
      jsonEncode(existing.map((d) => d.toJson()).toList()),
    );
    final keySuffix = device.tvId.isNotEmpty ? device.tvId : device.ip;
    await _safeWrite('$_starTvTokenPrefix$keySuffix', bearerToken);
  }

  Future<String?> getStarTvToken(StarTvDevice device) async {
    final keySuffix = device.tvId.isNotEmpty ? device.tvId : device.ip;
    return _safeRead('$_starTvTokenPrefix$keySuffix');
  }

  Future<void> removeStarTvDevice(StarTvDevice device) async {
    final existing = (await loadStarTvDevices()).toList();
    existing.removeWhere((d) =>
        (device.tvId.isNotEmpty && d.tvId == device.tvId) || d.ip == device.ip);
    await _safeWrite(
      _starTvDevicesKey,
      jsonEncode(existing.map((d) => d.toJson()).toList()),
    );
    final keySuffix = device.tvId.isNotEmpty ? device.tvId : device.ip;
    await _safeDelete('$_starTvTokenPrefix$keySuffix');
  }
}
