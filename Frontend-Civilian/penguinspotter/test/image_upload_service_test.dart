import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:penguin/services/image_upload_service.dart';

void main() {
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]);
  final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);
  final webp = Uint8List.fromList(ascii.encode('RIFF1234WEBP'));

  test('uploads each supported type and returns the backend key', () async {
    for (final entry in {
      'image/jpeg': jpeg,
      'image/png': png,
      'image/webp': webp,
    }.entries) {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          expect(request.url.path, '/dev/upload');
          expect(request.url.queryParameters['contentType'], entry.key);
          expect(request.headers['Authorization'], 'Bearer test-token');
          return http.Response(
            jsonEncode({
              'url':
                  'https://test-bucket.s3.amazonaws.com/image?signature=test',
              'key': 'PenguinAlbum/Potholes/test-image',
              'method': 'PUT',
              'headers': {'Content-Type': entry.key},
              'expiresIn': 300,
            }),
            200,
          );
        }
        expect(request.method, 'PUT');
        expect(request.headers['Content-Type'], entry.key);
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.bodyBytes, orderedEquals(entry.value));
        return http.Response('', 200);
      });
      final service = ImageUploadService(
        baseUrl: 'https://api.example.com/dev/',
        client: client,
      );
      addTearDown(service.close);
      expect(
        await service.upload(entry.value, accessToken: 'test-token'),
        'PenguinAlbum/Potholes/test-image',
      );
      expect(requests, hasLength(2));
    }
  });

  test('rejected authorization stops before an S3 request', () async {
    var calls = 0;
    final service = ImageUploadService(
      baseUrl: 'http://127.0.0.1:3000',
      client: MockClient((_) async {
        calls++;
        return http.Response('not JSON', 401);
      }),
    );
    addTearDown(service.close);
    await expectLater(
      service.upload(jpeg, accessToken: 'expired'),
      throwsException,
    );
    expect(calls, 1);
  });

  test('mismatched signed image type is rejected before upload', () async {
    var calls = 0;
    final service = ImageUploadService(
      baseUrl: 'https://api.example.com',
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'url': 'https://test-bucket.s3.amazonaws.com/image',
            'key': 'test-image',
            'method': 'PUT',
            'headers': {'Content-Type': 'image/png'},
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    await expectLater(
      service.upload(jpeg, accessToken: 'token'),
      throwsFormatException,
    );
    expect(calls, 1);
  });

  test('S3 failure does not return a successful image key', () async {
    final service = ImageUploadService(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async {
        if (request.method == 'PUT') return http.Response('AccessDenied', 403);
        return http.Response(
          jsonEncode({
            'url': 'https://test-bucket.s3.amazonaws.com/image',
            'key': 'test-image',
            'method': 'PUT',
            'headers': {'Content-Type': 'image/jpeg'},
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    await expectLater(
      service.upload(jpeg, accessToken: 'token'),
      throwsException,
    );
  });

  test('invalid file, absent URL, and absent token make no requests', () async {
    final client = MockClient((_) async => fail('No request should be sent'));
    final missingUrl = ImageUploadService(baseUrl: '', client: client);
    final service = ImageUploadService(
      baseUrl: 'https://api.example.com',
      client: client,
    );
    addTearDown(client.close);
    await expectLater(
      service.upload(Uint8List(0), accessToken: 'token'),
      throwsException,
    );
    await expectLater(
      missingUrl.upload(jpeg, accessToken: 'token'),
      throwsException,
    );
    await expectLater(service.upload(jpeg, accessToken: ''), throwsException);
  });
}
