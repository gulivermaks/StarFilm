import 'dart:convert';

import 'package:http/http.dart' as http;

import '../security/log_sanitizer.dart';
import 'lan_guard.dart';

class HttpResult {
  const HttpResult({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get isOk => statusCode >= 200 && statusCode < 300;
}

class StarFilmHttpClient {
  StarFilmHttpClient({
    http.Client? client,
    DiagnosticsLog? log,
    this.defaultTimeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _log = log;

  final http.Client _client;
  final DiagnosticsLog? _log;
  final Duration defaultTimeout;

  Future<HttpResult> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    LanGuard.requireAllowedUri(uri);
    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(timeout ?? defaultTimeout);
      return HttpResult(
        statusCode: response.statusCode,
        body: utf8.decode(response.bodyBytes, allowMalformed: true),
        headers: response.headers,
      );
    } catch (e) {
      _log?.warn('GET ${uri.host}${uri.path} failed: $e');
      rethrow;
    }
  }

  Future<HttpResult> postJson(
    Uri uri,
    Object body, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    LanGuard.requireAllowedUri(uri);
    try {
      final mergedHeaders = {
        'Content-Type': 'application/json; charset=utf-8',
        ...?headers,
      };
      final response = await _client
          .post(uri, headers: mergedHeaders, body: jsonEncode(body))
          .timeout(timeout ?? defaultTimeout);
      return HttpResult(
        statusCode: response.statusCode,
        body: utf8.decode(response.bodyBytes, allowMalformed: true),
        headers: response.headers,
      );
    } catch (e) {
      _log?.warn('POST ${uri.host}${uri.path} failed: $e');
      rethrow;
    }
  }

  Future<HttpResult> postForm(
    Uri uri,
    Map<String, String> fields, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    LanGuard.requireAllowedUri(uri);
    try {
      final mergedHeaders = {
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        ...?headers,
      };
      final response = await _client
          .post(uri, headers: mergedHeaders, body: fields)
          .timeout(timeout ?? defaultTimeout);
      return HttpResult(
        statusCode: response.statusCode,
        body: utf8.decode(response.bodyBytes, allowMalformed: true),
        headers: response.headers,
      );
    } catch (e) {
      _log?.warn('POST form ${uri.host}${uri.path} failed: $e');
      rethrow;
    }
  }
}
