import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:penguin/services/api_client.dart';

class ImageUploadService {
  ImageUploadService({
    this.baseUrl = const String.fromEnvironment('PEN_API'),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<String> upload(Uint8List bytes, {required String accessToken}) async {
    final contentType = _contentType(bytes);
    final endpoint = apiEndpoint(
      baseUrl,
      '/upload',
      queryParameters: {'contentType': contentType},
    );
    if (accessToken.isEmpty) {
      throw const ApiException('Please log in before uploading an image.');
    }
    final instructions = await _client
        .get(endpoint, headers: {'Authorization': 'Bearer $accessToken'})
        .timeout(const Duration(seconds: 20));
    if (instructions.statusCode != 200) {
      throw ApiException(
        apiErrorMessage(instructions, 'Could not request an upload URL'),
      );
    }

    final decoded = decodeJsonObject(instructions);
    final url = decoded['url'];
    final key = decoded['key'];
    final headers = decoded['headers'];
    if (url is! String ||
        key is! String ||
        key.isEmpty ||
        decoded['method'] != 'PUT' ||
        headers is! Map<String, dynamic> ||
        headers['Content-Type'] != contentType ||
        headers.values.any((value) => value is! String)) {
      throw const FormatException('Incomplete upload instructions.');
    }
    final uploadUrl = Uri.tryParse(url);
    if (uploadUrl == null ||
        uploadUrl.scheme != 'https' ||
        !uploadUrl.hasAuthority) {
      throw const FormatException('Invalid S3 upload URL.');
    }
    final result = await _client
        .put(uploadUrl, headers: Map<String, String>.from(headers), body: bytes)
        .timeout(const Duration(seconds: 60));
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw ApiException(
        'The photo upload failed (HTTP ${result.statusCode}). Please retry.',
      );
    }
    return key;
  }

  // Inspect file signatures instead of trusting a filename or browser MIME label.
  String _contentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length >= png.length &&
        List.generate(
          png.length,
          (i) => bytes[i] == png[i],
        ).every((match) => match)) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'image/webp';
    }
    throw const ApiException('Choose a JPEG, PNG, or WebP image.');
  }

  void close() => _client.close();
}
