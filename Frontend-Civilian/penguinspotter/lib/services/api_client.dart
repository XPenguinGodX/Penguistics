import 'dart:convert';

import 'package:http/http.dart' as http;

/// An error whose message is safe to show the user as-is.
///
/// Unlike `Exception('...')`, printing it gives just the message, without an
/// "Exception: " prefix.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Joins [path] onto the PEN_API [baseUrl], refusing anything that isn't a plain http(s) URL.
Uri apiEndpoint(
  String baseUrl,
  String path, {
  Map<String, String>? queryParameters,
}) {
  final base = Uri.tryParse(baseUrl);
  if (base == null ||
      !base.hasAuthority ||
      (base.scheme != 'https' && base.scheme != 'http') ||
      base.hasQuery ||
      base.hasFragment) {
    throw const ApiException('Set PEN_API to your API base URL.');
  }
  return base.replace(
    path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}$path',
    queryParameters: queryParameters,
  );
}

/// Decodes a JSON object body, or throws if the server sent anything else.
Map<String, dynamic> decodeJsonObject(http.Response response) {
  final Object? decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Unexpected response from the server.');
  }
  return decoded;
}

/// A readable message for a failed response: the server's own `message` when it sent one.
String apiErrorMessage(http.Response response, String fallback) {
  if (response.statusCode == 401 || response.statusCode == 403) {
    return 'Your session has expired. Please log in again.';
  }
  try {
    final message = decodeJsonObject(response)['message'];
    if (message is String && message.isNotEmpty) return message;
  } catch (_) {}
  return '$fallback (HTTP ${response.statusCode}).';
}
