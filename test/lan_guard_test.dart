import 'package:flutter_test/flutter_test.dart';
import 'package:starfilm/core/network/lan_guard.dart';
import 'package:starfilm/core/security/log_sanitizer.dart';

void main() {
  test('LanGuard allows http only for RFC1918 private IPv4 and requires https externally', () {
    expect(LanGuard.isAllowedUri(Uri.parse('http://192.168.1.50:8088/api/status')), isTrue);
    expect(LanGuard.isAllowedUri(Uri.parse('http://10.0.0.12:8088/api/auth')), isTrue);
    expect(LanGuard.isAllowedUri(Uri.parse('http://172.16.5.2:8088/api/status')), isTrue);
    expect(LanGuard.isAllowedUri(Uri.parse('http://172.31.255.1:8088/api/status')), isTrue);

    expect(LanGuard.isAllowedUri(Uri.parse('http://172.32.0.1:8088/api/status')), isFalse);
    expect(LanGuard.isAllowedUri(Uri.parse('http://8.8.8.8/test')), isFalse);
    expect(LanGuard.isAllowedUri(Uri.parse('http://example.com/api')), isFalse);
    expect(LanGuard.isAllowedUri(Uri.parse('https://api.tmdb.org/3/configuration')), isTrue);

    expect(
      () => LanGuard.requireAllowedUri(Uri.parse('http://evil.example.com/steal')),
      throwsA(isA<LanGuardException>()),
    );
  });

  test('LogSanitizer masks API keys, Bearer tokens, and PIN parameters', () {
    const raw =
        'POST https://generativelanguage.googleapis.com/v1beta?key=AIzaSyDummySecretKey1234567890 '
        'Authorization: Bearer abcdef1234567890abcdef1234567890 http://192.168.1.2:8088/?pin=123456';
    final masked = LogSanitizer.mask(raw);
    expect(masked, isNot(contains('AIzaSyDummySecretKey')));
    expect(masked, isNot(contains('abcdef1234567890abcdef1234567890')));
    expect(masked, isNot(contains('123456')));
  });
}
