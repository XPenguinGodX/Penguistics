import 'package:flutter/material.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguincity/pages/city_report_map.dart';
import 'package:penguincity/services/city_reports.dart';

void main() {
  testWidgets(
    'nearby pins cluster, queue selection reveals pins, and filtered pins still open',
    (tester) async {
      const first = CityReport(
        'one',
        'First damage',
        'CONFIRMED',
        40.76,
        -111.89,
      );
      const second = CityReport(
        'two',
        'Second damage',
        'ACTIVE',
        40.76001,
        -111.89001,
      );
      Future<void> show(List<CityReport> reports) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: CityReportMap(reports: reports)),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show([first, second]);
      expect(find.byType(MarkerClusterLayerWidget), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // The queue remains usable even when its corresponding marker is clustered.
      await tester.tap(find.text('First damage'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportDetailsPanel), findsOneWidget);
      expect(find.byKey(const ValueKey('report-one')), findsOneWidget);
      await tester.tap(find.byTooltip('Close report'));
      await tester.pumpAndSettle();
      // Home supplies only reports matching the status filters.
      await show([second]);
      expect(find.text('2'), findsNothing);
      expect(find.byKey(const ValueKey('report-one')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('report-two')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportDetailsPanel), findsOneWidget);
    },
  );
}
