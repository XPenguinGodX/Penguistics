import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguincity/pages/city_stats.dart';
import 'package:penguincity/services/city_reports.dart';

void main() {
  testWidgets(
    'stats loads counts, completion time, and daily totals then refreshes',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CityStats(
            loadStats: () {
              calls++;
              if (calls > 1) throw const CityReportsException('Unavailable.');
              return pending.future;
            },
          ),
        ),
      );
      expect(find.text('Loading statistics…'), findsOneWidget);
      pending.complete({
        'city': 'Example',
        'state': 'UT',
        'counts': {'CONFIRMED': 2},
        'average_completion_seconds': 172800,
        'daily': [
          {'day': '2026-11-17', 'count': 2},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Example, UT'), findsOneWidget);
      expect(find.textContaining('2.0 days'), findsOneWidget);
      expect(find.text('2026-11-17'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh statistics'));
      await tester.pumpAndSettle();
      expect(find.text('Unavailable.'), findsOneWidget);
    },
  );
}
