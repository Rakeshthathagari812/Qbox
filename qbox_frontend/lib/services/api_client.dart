import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// An error to show the user. [message] is already written for shopkeepers.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status = 0});

  final String code;
  final String message;
  final int status;

  bool get isUnauthorized => status == 401;

  /// True when the server could not be reached at all.
  bool get isNetwork => code == 'NETWORK';

  @override
  String toString() => 'ApiException($code, $message)';
}

/// Sends requests to the QBOX backend and turns every failure into an
/// [ApiException] with a friendly message. Shared by all features.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client, this.token})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Reads the saved login token, for endpoints that need login.
  final Future<String?> Function()? token;

  static const _timeout = Duration(seconds: 15);

  Future<Object?> get(String path, {bool auth = true}) =>
      _send('GET', path, auth: auth);

  Future<Object?> post(String path, Object body, {bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);

  Future<Object?> put(String path, Object body, {bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<Object?> delete(String path, {bool auth = true}) =>
      _send('DELETE', path, auth: auth);

  /// GET with an explicit token (used to check a saved login at startup).
  Future<Object?> getWithToken(String path, String accessToken) =>
      _send('GET', path, accessToken: accessToken);

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    bool auth = false,
    String? accessToken,
  }) async {
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
    };
    final bearer = accessToken ?? (auth ? await token?.call() : null);
    if (bearer != null && bearer.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearer';
    }

    final http.Response response;
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'NETWORK',
        'The QBOX server is taking too long. Please try again.',
      );
    } catch (_) {
      throw const ApiException(
        'NETWORK',
        'Cannot reach the QBOX server. Check your internet connection.',
      );
    }

    final decoded = response.body.isEmpty ? null : _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    if (decoded is Map<String, dynamic> && decoded['message'] is String) {
      throw ApiException(
        decoded['code'] as String? ?? 'ERROR',
        decoded['message'] as String,
        status: response.statusCode,
      );
    }
    throw ApiException(
      'ERROR',
      'Something went wrong. Please try again.',
      status: response.statusCode,
    );
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
