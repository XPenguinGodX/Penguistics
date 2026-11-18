import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguin/pages/my_reports.dart';
import 'package:penguin/services/report_service.dart';

void main() {
  testWidgets(
    'loads reports, opens existing details, and preserves list on refresh failure',
    (tester) async {
      final pending = Completer<List<ReportSummary>>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MyReports(
            loadReports: () {
              calls++;
              if (calls > 1) throw Exception('offline');
              return pending.future;
            },
          ),
        ),
      );
      expect(find.text('Loading your reports…'), findsOneWidget);
      pending.complete([
        ReportSummary(
          id: 'one',
          status: 'ACTIVE',
          title: 'Main Street pothole',
          description: 'Near the crossing',
          latitude: 40,
          longitude: -111,
          createdAt: DateTime(2026, 11, 17),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Being repaired'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my-report-one')));
      await tester.pumpAndSettle();
      expect(find.text('Main Street pothole'), findsNWidgets(2));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh reports'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Showing previously loaded reports.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('my-report-one')), findsOneWidget);
    },
  );

  testWidgets('initial failure can retry to an empty list', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MyReports(
          loadReports: () async {
            if (++calls == 1) throw Exception('offline');
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load your reports.'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh reports'));
    await tester.pumpAndSettle();
    expect(
      find.text('You have not submitted any reports yet.'),
      findsOneWidget,
    );
  });
}
