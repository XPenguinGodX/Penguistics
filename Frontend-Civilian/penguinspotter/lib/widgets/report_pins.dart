import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:penguin/services/report_service.dart';
import 'package:penguin/theme/penguin_theme.dart';
import 'package:penguin/widgets/penguin_widgets.dart';

/// How each report status looks: pin color, the icon drawn on it, and its wording.
({Color pin, Color icon, String label, PenguinTone tone}) reportStyle(
  String status,
) => switch (status) {
  'CONFIRMED' => (
    pin: PenguinColors.yellow,
    icon: PenguinColors.black,
    label: 'Confirmed',
    tone: PenguinTone.success,
  ),
  'REJECTED' => (
    pin: PenguinColors.charcoalHigh,
    icon: PenguinColors.muted,
    label: 'Not confirmed',
    tone: PenguinTone.info,
  ),
  _ => (
    pin: PenguinColors.orange,
    icon: PenguinColors.black,
    label: 'Checking',
    tone: PenguinTone.warning,
  ),
};

/// A tappable map pin for one report.
Marker reportMarker(ReportSummary report, VoidCallback onTap) {
  final style = reportStyle(report.status);
  return Marker(
    point: LatLng(report.latitude, report.longitude),
    width: 44,
    height: 44,
    alignment: Alignment.topCenter,
    child: Semantics(
      button: true,
      label: '${style.label} report: ${report.description}',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // A slightly larger black pin behind gives every color a dark outline
            const Icon(Icons.location_on, size: 46, color: PenguinColors.black),
            Icon(Icons.location_on, size: 40, color: style.pin),
            Positioned(
              top: 9,
              child: Icon(
                Icons.construction_rounded,
                size: 15,
                color: style.icon,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bottom sheet with one report's details, opened by tapping its pin.
Future<void> showReportSheet(BuildContext context, ReportSummary report) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      final style = reportStyle(report.status);
      final localizations = MaterialLocalizations.of(sheetContext);
      final created = report.createdAt?.toLocal();
      final confidence = report.confidence;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your report', style: text.titleLarge),
              const SizedBox(height: 12),
              StatusBanner(message: style.label, tone: style.tone),
              const SizedBox(height: 16),
              Text(
                report.description.isEmpty
                    ? 'No description'
                    : report.description,
                style: text.bodyLarge,
              ),
              const SizedBox(height: 16),
              if (confidence != null)
                _DetailRow(
                  icon: Icons.insights_rounded,
                  text: 'AI confidence: ${(confidence * 100).round()}%',
                ),
              if (created != null)
                _DetailRow(
                  icon: Icons.schedule_rounded,
                  text:
                      '${localizations.formatMediumDate(created)}, '
                      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(created))}',
                ),
              _DetailRow(
                icon: Icons.place_rounded,
                text:
                    '${report.latitude.toStringAsFixed(5)}, '
                    '${report.longitude.toStringAsFixed(5)}',
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: PenguinColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: PenguinColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small key explaining the three pin colors.
class ReportPinLegend extends StatelessWidget {
  const ReportPinLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyMedium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PenguinColors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PenguinColors.outline),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          for (final status in ['PENDING', 'CONFIRMED', 'REJECTED'])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: reportStyle(status).pin,
                    border: Border.all(color: PenguinColors.muted),
                  ),
                ),
                const SizedBox(width: 6),
                Text(reportStyle(status).label, style: text),
              ],
            ),
        ],
      ),
    );
  }
}
