import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:penguin/services/api_client.dart';
import 'package:penguin/services/report_service.dart';

void main() {
  test('listMine sends the token and parses every report', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.example.com/dev/reports');
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.Response(
        jsonEncode({
          'reports': [
            {
              'id': 'r1',
              'status': 'CONFIRMED',
              'description': 'Deep pothole',
              'lat': 40.76,
              'long': -111.89,
              'confidence': 0.93,
              'created_at': '2026-11-02T12:00:00+00:00',
            },
            {
              'id': 'r2',
              'status': 'PENDING',
              'description': 'Cracked lane',
              'lat': 40,
              'long': -111,
              'confidence': null,
              'created_at': null,
            },
          ],
        }),
        200,
      );
    });
    final service = ReportService(
      baseUrl: 'https://api.example.com/dev',
      client: client,
    );

    final reports = await service.listMine(accessToken: 'test-token');

    expect(reports.map((r) => r.id), ['r1', 'r2']);
    expect(reports.first.confidence, 0.93);
    expect(reports.first.createdAt, DateTime.utc(2026, 11, 2, 12));
    // Whole-number JSON coordinates still become doubles
    expect(reports.last.latitude, 40.0);
    expect(reports.last.confidence, isNull);
    expect(reports.last.createdAt, isNull);
  });

  test('entries missing an id or coordinates are skipped, not fatal', () async {
    final service = ReportService(
      baseUrl: 'https://api.example.com',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'reports': [
              {'id': 'good', 'lat': 1, 'long': 2},
              {'id': 'no-coordinates'},
              {'lat': 1, 'long': 2},
              'not an object',
            ],
          }),
          200,
        ),
      ),
    );

    final reports = await service.listMine(accessToken: 't');

    expect(reports.map((r) => r.id), ['good']);
    expect(reports.single.status, 'PENDING');
  });

  test('a failed listing becomes a readable error', () async {
    final service = ReportService(
      baseUrl: 'https://api.example.com',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'message': 'Reports are temporarily unavailable.'}),
          503,
        ),
      ),
    );

    await expectLater(
      service.listMine(accessToken: 't'),
      throwsA(
        isA<ApiException>().having(
          (e) => '$e',
          'message',
          'Reports are temporarily unavailable.',
        ),
      ),
    );
  });
}
