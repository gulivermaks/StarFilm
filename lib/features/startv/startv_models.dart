import '../../core/network/lan_guard.dart';

enum StarTvTrustMode {
  home('home'),
  guest('guest');

  const StarTvTrustMode(this.wireValue);
  final String wireValue;

  static StarTvTrustMode fromWire(String? value) {
    return value == 'home' ? StarTvTrustMode.home : StarTvTrustMode.guest;
  }
}

class StarTvDevice {
  const StarTvDevice({
    required this.tvId,
    required this.ip,
    required this.port,
    required this.deviceName,
    required this.trustMode,
    this.installedPlayers = const ['auto'],
    this.syncApiVersion = 0,
  });

  final String tvId;
  final String ip;
  final int port;
  final String deviceName;
  final StarTvTrustMode trustMode;
  final List<String> installedPlayers;
  final int syncApiVersion;

  bool get canSyncLibrary => trustMode == StarTvTrustMode.home;
  bool get canTransferKeys => trustMode == StarTvTrustMode.home;

  Uri get baseUri {
    final uri = Uri(scheme: 'http', host: ip, port: port);
    return LanGuard.requireAllowedUri(uri);
  }

  Map<String, dynamic> toJson() => {
        'tvId': tvId,
        'ip': ip,
        'port': port,
        'deviceName': deviceName,
        'trustMode': trustMode.wireValue,
        'installedPlayers': installedPlayers,
        'syncApiVersion': syncApiVersion,
      };

  factory StarTvDevice.fromJson(Map<String, dynamic> json) {
    return StarTvDevice(
      tvId: (json['tvId'] ?? '').toString(),
      ip: (json['ip'] ?? '').toString(),
      port: (json['port'] is num) ? (json['port'] as num).toInt() : 8088,
      deviceName: (json['deviceName'] ?? 'StarTV').toString(),
      trustMode: StarTvTrustMode.fromWire(json['trustMode']?.toString()),
      installedPlayers: (json['installedPlayers'] as List<dynamic>? ?? const ['auto'])
          .map((e) => e.toString())
          .toList(),
      syncApiVersion: (json['syncApiVersion'] is num)
          ? (json['syncApiVersion'] as num).toInt()
          : 0,
    );
  }
}

class StarTvQrPayload {
  const StarTvQrPayload({
    required this.ip,
    required this.port,
    required this.pin,
  });

  final String ip;
  final int port;
  final String pin;

  static StarTvQrPayload? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !LanGuard.isAllowedUri(uri) || uri.scheme != 'http') {
      return null;
    }
    final pin = uri.queryParameters['pin']?.trim() ?? '';
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      return null;
    }
    return StarTvQrPayload(
      ip: uri.host,
      port: uri.hasPort ? uri.port : 8088,
      pin: pin,
    );
  }

  static ({String ip, int port})? tryParseHostPort(
    String raw, {
    int defaultPort = 8088,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('://')) {
      final parsed = Uri.tryParse(trimmed);
      if (parsed == null || parsed.scheme != 'http' || parsed.host.isEmpty) {
        return null;
      }
      final port = parsed.hasPort ? parsed.port : defaultPort;
      if (port < 1 || port > 65535) return null;
      final normalized = Uri(scheme: 'http', host: parsed.host, port: port);
      if (!LanGuard.isAllowedUri(normalized)) return null;
      return (ip: parsed.host, port: port);
    }
    var host = trimmed;
    var port = defaultPort;
    final colonIdx = trimmed.indexOf(':');
    if (colonIdx != -1) {
      if (trimmed.indexOf(':', colonIdx + 1) != -1) return null;
      host = trimmed.substring(0, colonIdx).trim();
      final portStr = trimmed.substring(colonIdx + 1).trim();
      final parsedPort = int.tryParse(portStr);
      if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
        return null;
      }
      port = parsedPort;
    }
    if (host.isEmpty || !LanGuard.isPrivateRfc1918Ipv4(host)) return null;
    final normalized = Uri(scheme: 'http', host: host, port: port);
    if (!LanGuard.isAllowedUri(normalized)) return null;
    return (ip: host, port: port);
  }
}
