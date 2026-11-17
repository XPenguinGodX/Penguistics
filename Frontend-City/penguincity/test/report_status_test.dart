import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:penguincity/pages/report_status_actions.dart';
import 'package:penguincity/services/city_reports.dart';

void main() {
  test(
    'status request is authenticated and accepts a dismissed response',
    () async {
      final service = CityReportService(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/city/reports/one/status');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {'status': 'DISMISSED'});
          return http.Response(
            '{"report":{"id":"one","status":"DISMISSED","lat":40,"long":-111}}',
            200,
          );
        }),
      );
      addTearDown(service.close);
      expect(
        (await service.changeStatus('one', 'DISMISSED', 'token')).status,
        'DISMISSED',
      );
    },
  );

  test('conflicting changes ask the user to refresh', () async {
    final service = CityReportService(
      baseUrl: 'https://example.test',
      client: MockClient((_) async => http.Response('{}', 409)),
    );
    addTearDown(service.close);
    await expectLater(
      service.changeStatus('one', 'ACTIVE', 'token'),
      throwsA(
        isA<CityReportsException>().having(
          (e) => e.message,
          'message',
          contains('Refresh'),
        ),
      ),
    );
  });

  testWidgets('valid actions, busy state, and failure message', (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportStatusActions(
            report: const CityReport('one', 'Damage', 'CONFIRMED', 40, -111),
            onChange: (report, status) {
              expect(status, 'ACTIVE');
              return pending.future;
            },
          ),
        ),
      ),
    );
    expect(find.text('Mark fixed'), findsNothing);
    await tester.tap(find.text('Start repair'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.completeError(const CityReportsException('Refresh first.'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh first.'), findsOneWidget);
  });

  testWidgets('dismiss requires confirmation and completed has no actions', (
    tester,
  ) async {
    var calls = 0;
    Future<void> show(String status) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportStatusActions(
            report: CityReport('one', 'Damage', status, 40, -111),
            onChange: (_, next) async {
              expect(next, 'DISMISSED');
              calls++;
            },
          ),
        ),
      ),
    );
    await show('ACTIVE');
    expect(find.text('Mark fixed'), findsOneWidget);
    expect(find.text('Start repair'), findsNothing);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await show('COMPLETED');
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
  });
}
