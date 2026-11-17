import 'package:flutter/material.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/services/city_reports.dart';

class ReportQueue extends StatefulWidget {
  const ReportQueue({
    super.key,
    required this.reports,
    required this.onSelect,
    this.selectedId,
  });
  final List<CityReport> reports;
  final String? selectedId;
  final ValueChanged<CityReport> onSelect;
  @override
  State<ReportQueue> createState() => _ReportQueueState();
}

class _ReportQueueState extends State<ReportQueue> {
  int _sortColumn = 2;
  bool _ascending = false;

  int _compare(CityReport a, CityReport b) {
    // Missing dates and confidence stay last in either sort direction.
    if (_sortColumn == 2 || _sortColumn == 3) {
      final aMissing = _sortColumn == 2
          ? a.createdAt == null
          : a.confidence == null;
      final bMissing = _sortColumn == 2
          ? b.createdAt == null
          : b.confidence == null;
      if (aMissing != bMissing) return aMissing ? 1 : -1;
    }
    final result = switch (_sortColumn) {
      0 => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      1 =>
        cityMapStatuses
            .indexOf(a.status)
            .compareTo(cityMapStatuses.indexOf(b.status)),
      2 => (a.createdAt ?? DateTime(1970)).compareTo(
        b.createdAt ?? DateTime(1970),
      ),
      _ => (a.confidence ?? 0).compareTo(b.confidence ?? 0),
    };
    if (result == 0) return a.id.compareTo(b.id);
    return _ascending ? result : -result;
  }

  @override
  Widget build(BuildContext context) {
    final reports = [...widget.reports]..sort(_compare);
    final localizations = MaterialLocalizations.of(context);
    return Material(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Report queue (${reports.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: reports.isEmpty
                ? const Center(
                    child: Text('No reports match the selected filters.'),
                  )
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        sortColumnIndex: _sortColumn,
                        sortAscending: _ascending,
                        columns: [
                          for (final label in [
                            'Title',
                            'Status',
                            'Date',
                            'Confidence',
                          ])
                            DataColumn(
                              label: Text(label),
                              onSort: (column, ascending) => setState(() {
                                _sortColumn = column;
                                _ascending = ascending;
                              }),
                            ),
                        ],
                        rows: reports
                            .map(
                              (report) => DataRow(
                                key: ValueKey('queue-${report.id}'),
                                selected: widget.selectedId == report.id,
                                onSelectChanged: (_) => widget.onSelect(report),
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 180,
                                      child: Text(
                                        report.title.isEmpty
                                            ? 'Road damage'
                                            : report.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(reportStyle(report.status).label),
                                  ),
                                  DataCell(
                                    Text(
                                      report.createdAt == null
                                          ? 'Unavailable'
                                          : localizations.formatMediumDate(
                                              report.createdAt!.toLocal(),
                                            ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      report.confidence == null
                                          ? 'Unavailable'
                                          : '${(report.confidence! * 100).round()}%',
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
