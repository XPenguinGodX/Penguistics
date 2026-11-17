import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguincity/pages/city_report_map.dart';
import 'package:penguincity/services/city_reports.dart';

void main() {
  test('parses the backend detail fields', () {
    final report = CityReport.tryParse({
      'id': 'one',
      'title': 'Pothole',
      'status': 'CONFIRMED',
      'lat': 40,
      'long': -111,
      'description': 'Near the crossing',
      'confidence': .93,
      'created_at': '2026-11-16T12:00:00Z',
      'location_source': 'REMOTE',
    })!;
    expect(report.description, 'Near the crossing');
    expect(report.confidence, .93);
    expect(report.createdAt, DateTime.utc(2026, 11, 16, 12));
    expect(report.locationSource, 'REMOTE');
    expect(reportCameraFit([]), isNull);
    expect(reportCameraFit([report]), isNotNull);
  });

  testWidgets('details show report fields, switch reports, and close', (
    tester,
  ) async {
    var closed = false;
    Future<void> show(CityReport report) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportDetailsPanel(
            report: report,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await show(
      CityReport(
        'one',
        'Pothole',
        'CONFIRMED',
        40,
        -111,
        description: 'Near the crossing',
        confidence: .93,
        createdAt: DateTime.utc(2026, 11, 16, 12),
        locationSource: 'REMOTE',
      ),
    );
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('Near the crossing'), findsOneWidget);
    expect(find.text('AI confidence: 93%'), findsOneWidget);
    expect(find.text('Placed remotely on the map'), findsOneWidget);
    expect(find.textContaining('Reported:'), findsOneWidget);
    expect(find.text('Coordinates: 40.00000, -111.00000'), findsOneWidget);
    await show(const CityReport('two', 'Other damage', 'ACTIVE', 41, -112));
    expect(find.text('Pothole'), findsNothing);
    expect(find.text('Other damage'), findsOneWidget);
    expect(find.text('AI confidence unavailable'), findsOneWidget);
    await tester.tap(find.byTooltip('Close report'));
    expect(closed, isTrue);
  });
}
