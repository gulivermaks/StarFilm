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
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const String _tmdbKey = 'starfilm.tmdb_api_key';
  static const String _geminiKey = 'starfilm.gemini_api_key';
  static const String _kinopoiskKey = 'starfilm.kinopoisk_api_key';
  static const String _deviceIdKey = 'starfilm.device_id';
  static const String _starTvDevicesKey = 'starfilm.startv_devices';
  static const String _starTvTokenPrefix = 'starfilm.startv_token.';

  Future<String> getTmdbKey() async => (await _storage.read(key: _tmdbKey)) ?? '';
  Future<void> setTmdbKey(String value) =>
      _storage.write(key: _tmdbKey, value: value.trim());

  Future<String> getGeminiKey() async => (await _storage.read(key: _geminiKey)) ?? '';
  Future<void> setGeminiKey(String value) =>
      _storage.write(key: _geminiKey, value: value.trim());

  Future<String> getKinopoiskKey() async {
    try {
      return (await _storage.read(key: _kinopoiskKey)) ?? '';
    } on MissingPluginException {
      return '';
    }
  }

  Future<void> setKinopoiskKey(String value) async {
    try {
      await _storage.write(key: _kinopoiskKey, value: value.trim());
    } on MissingPluginException {
      // Allow legacy test SecretStore fakes to omit Kinopoisk overrides.
    }
  }

  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final hex = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _deviceIdKey, value: hex);
    return hex;
  }

  Future<List<StarTvDevice>> loadStarTvDevices() async {
    final raw = await _storage.read(key: _starTvDevicesKey);
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
    await _storage.write(
      key: _starTvDevicesKey,
      value: jsonEncode(existing.map((d) => d.toJson()).toList()),
    );
    final keySuffix = device.tvId.isNotEmpty ? device.tvId : device.ip;
    await _storage.write(key: '$_starTvTokenPrefix$keySuffix', value: bearerToken);
  }

  Future<String?> getStarTvToken(StarTvDevice device) async {
    final keySuffix = device.tvId.isNotEmpty ? device.tvId : device.ip;
    return _storage.read(key: '$_starTvTokenPrefix$keySuffix');
  }

  Future<void> removeStarTvDevice(StarTvDevice device) async {
    final existing = (await loadStarTvDevices()).toList();
    existing.removeWhere((d) =>
        (device.tvId.isNotEmpty && d.tvId == device.tvId) || d.ip == device.ip);
    await _storage.write(
      key: _starTvDevicesKey,
      value: jsonEncode(existing.map((d) => d.toJson()).toList()),
    );
    final keySuffix = device.tvId.isNotEmpty ? device.tvId : device.ip;
    await _storage.delete(key: '$_starTvTokenPrefix$keySuffix');
  }
}
