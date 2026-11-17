import 'package:flutter/material.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/services/city_reports.dart';

class ReportStatusActions extends StatefulWidget {
  const ReportStatusActions({
    super.key,
    required this.report,
    required this.onChange,
  });
  final CityReport report;
  final Future<void> Function(CityReport, String) onChange;
  @override
  State<ReportStatusActions> createState() => _ReportStatusActionsState();
}

class _ReportStatusActionsState extends State<ReportStatusActions> {
  bool _busy = false;
  String? _error;

  Future<void> _change(String status) async {
    final report = widget.report;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (status == 'DISMISSED') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Dismiss report?'),
            content: const Text(
              'This closes the report without a repair and removes it from the default city map.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await widget.onChange(report, status);
    } on CityReportsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not update the report. Refresh to check its status before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.report.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == 'CONFIRMED' || status == 'ACTIVE') ...[
          FilledButton(
            onPressed: _busy
                ? null
                : () => _change(status == 'CONFIRMED' ? 'ACTIVE' : 'COMPLETED'),
            child: Text(status == 'CONFIRMED' ? 'Start repair' : 'Mark fixed'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _change('DISMISSED'),
            child: const Text('Dismiss'),
          ),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          StatusBanner(message: _error!, tone: PenguinTone.warning),
      ],
    );
  }
}
