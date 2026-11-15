/// Validates outbound URLs so plain `http://` is permitted ONLY for private
/// RFC1918 IPv4 LAN addresses (StarTV boxes), while all external requests require `https://`.
class LanGuard {
  const LanGuard._();

  static bool isPrivateRfc1918Ipv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }
    final a = octets[0];
    final b = octets[1];
    // 10.0.0.0/8
    if (a == 10) return true;
    // 172.16.0.0/12
    if (a == 172 && b >= 16 && b <= 31) return true;
    // 192.168.0.0/16
    if (a == 192 && b == 168) return true;
    return false;
  }

  static bool isAllowedUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return uri.host.isNotEmpty;
    if (scheme == 'http') {
      return isPrivateRfc1918Ipv4(uri.host);
    }
    return false;
  }

  static Uri requireAllowedUri(Uri uri) {
    if (!isAllowedUri(uri)) {
      throw LanGuardException(
        'Blocked non-HTTPS request outside RFC1918 LAN: ${uri.scheme}://${uri.host}',
      );
    }
    return uri;
  }
}

class LanGuardException implements Exception {
  LanGuardException(this.message);
  final String message;

  @override
  String toString() => 'LanGuardException: $message';
}
