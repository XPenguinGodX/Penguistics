import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguincity/pages/report_queue.dart';
import 'package:penguincity/services/city_reports.dart';

void main() {
  testWidgets('queue sorts dates and titles and selects the report', (
    tester,
  ) async {
    CityReport? selected;
    final reports = [
      CityReport(
        'b',
        'Beta',
        'ACTIVE',
        40,
        -111,
        confidence: .9,
        createdAt: DateTime(2026, 11, 17),
      ),
      CityReport(
        'a',
        'Alpha',
        'CONFIRMED',
        41,
        -112,
        confidence: .7,
        createdAt: DateTime(2026, 11, 16),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportQueue(
            reports: reports,
            selectedId: 'a',
            onSelect: (report) => selected = report,
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
    await tester.tap(find.text('Alpha'));
    expect(selected?.id, 'a');
    expect(
      tester.widget<DataTable>(find.byType(DataTable)).rows.first.selected,
      isTrue,
    );
    expect(
      reports.first.id,
      'b',
    ); // Sorting must not reorder the map's input list.
  });

  testWidgets('queue handles missing values and filtered input', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportQueue(
            reports: const [CityReport('one', '', 'COMPLETED', 40, -111)],
            onSelect: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Road damage'), findsOneWidget);
    expect(find.text('Unavailable'), findsNWidgets(2));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportQueue(reports: const [], onSelect: (_) {}),
        ),
      ),
    );
    expect(find.text('Report queue (0)'), findsOneWidget);
    expect(find.text('No reports match the selected filters.'), findsOneWidget);
  });
}
