import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:penguincity/pages/home.dart';
import 'package:penguincity/services/city_reports.dart';

void main() {
  test(
    'loads the staff endpoint with a bearer token and skips invalid pins',
    () async {
      final service = CityReportService(
        baseUrl: 'https://example.test/',
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://example.test/city/reports');
          expect(request.headers['Authorization'], 'Bearer test-token');
          return http.Response(
            '{"city":"Example","state":"UT","reports":['
            '{"id":"one","title":"Damage","status":"ACTIVE","lat":40,"long":-111},'
            '{"id":"bad","status":"ACTIVE","lat":100,"long":0}]}',
            200,
          );
        }),
      );
      addTearDown(service.close);
      final data = await service.load('test-token');
      expect(data.city, 'Example');
      expect(data.reports.single.id, 'one');
    },
  );

  test('denied access produces an actionable error', () async {
    final service = CityReportService(
      baseUrl: 'https://example.test',
      client: MockClient((_) async => http.Response('{}', 403)),
    );
    addTearDown(service.close);
    await expectLater(
      service.load('token'),
      throwsA(isA<CityReportsException>()),
    );
  });

  testWidgets('loading, empty city, refresh error, and retry are visible', (
    tester,
  ) async {
    final pending = Completer<CityReports>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Home(
          loadReports: () {
            calls++;
            if (calls == 1) return pending.future;
            if (calls == 2) {
              throw const CityReportsException('Try again later.');
            }
            return Future.value(const CityReports('Example', 'UT', []));
          },
        ),
      ),
    );
    expect(find.text('Loading city reports…'), findsOneWidget);
    pending.complete(const CityReports('Example', 'UT', []));
    await tester.pumpAndSettle();
    expect(find.text('Example, UT'), findsOneWidget);
    expect(find.textContaining('No confirmed, active'), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Showing previously loaded reports.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Showing previously loaded reports.'),
      findsNothing,
    );
    expect(calls, 3);
  });

  testWidgets(
    'deselecting statuses distinguishes hidden reports from an empty city',
    (tester) async {
      final pending = Completer<CityReports>();
      await tester.pumpWidget(
        MaterialApp(home: Home(loadReports: () => pending.future)),
      );
      for (final label in ['Confirmed', 'Active', 'Completed']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      pending.complete(
        const CityReports('Example', 'UT', [
          CityReport('one', 'Damage', 'ACTIVE', 40, -111),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 of 1 reports shown'), findsOneWidget);
      expect(find.textContaining('No reports match'), findsOneWidget);
    },
  );
}
