import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:penguincity/pages/report_photo.dart';
import 'package:penguincity/services/city_reports.dart';

void main() {
  testWidgets('photo opens an enlarged viewer and closes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportPhoto(
            loadUrl: () async => 'https://photos.example.test/signed',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enlarge photo'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
  test('photo URL request includes staff token', () async {
    final service = CityReportService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        expect(request.url.path, '/city/reports/one/photo');
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response(
          '{"url":"https://photos.example.test/signed","expiresIn":300}',
          200,
        );
      }),
    );
    addTearDown(service.close);
    expect(
      await service.photoUrl('one', 'token'),
      'https://photos.example.test/signed',
    );
  });

  test('missing photo and invalid URL are errors', () async {
    var status = 404;
    final service = CityReportService(
      baseUrl: 'https://api.example.test',
      client: MockClient(
        (_) async =>
            http.Response('{"url":"http://unsafe.example.test"}', status),
      ),
    );
    addTearDown(service.close);
    await expectLater(
      service.photoUrl('one', 'token'),
      throwsA(isA<CityReportsException>()),
    );
    status = 200;
    await expectLater(
      service.photoUrl('one', 'token'),
      throwsA(isA<FormatException>()),
    );
  });

  testWidgets('photo loading, failure, and retry fetch a fresh URL', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportPhoto(
            loadUrl: () {
              calls++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(const CityReportsException('No photo is available.'));
    await tester.pumpAndSettle();
    expect(find.text('No photo is available.'), findsOneWidget);
    await tester.tap(find.text('Retry photo'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
