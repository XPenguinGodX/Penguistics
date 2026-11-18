import 'package:flutter/material.dart';
import 'package:penguin/services/auth_session.dart';
import 'package:penguin/services/report_service.dart';
import 'package:penguin/widgets/report_pins.dart';
import 'package:penguin_shared/penguin_shared.dart';

class MyReports extends StatefulWidget {
  const MyReports({super.key, this.loadReports});
  final Future<List<ReportSummary>> Function()? loadReports;
  @override
  State<MyReports> createState() => _MyReportsState();
}

class _MyReportsState extends State<MyReports> {
  final _service = ReportService();
  List<ReportSummary>? _reports;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<List<ReportSummary>> _load() async =>
      _service.listMine(accessToken: await accessToken());

  Future<void> _refresh() async {
    if (_loading && _reports != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = await (widget.loadReports?.call() ?? _load());
      if (mounted) setState(() => _reports = reports);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _reports == null
              ? 'Could not load your reports. Check your connection and try again.'
              : 'Could not refresh. Showing previously loaded reports.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    final localizations = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: StatusBanner(message: _error!, tone: PenguinTone.warning),
            ),
          Expanded(
            child: reports == null
                ? Center(
                    child: Text(
                      _loading
                          ? 'Loading your reports…'
                          : 'Use Refresh to try again.',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: reports.isEmpty ? 1 : reports.length,
                      itemBuilder: (context, index) {
                        if (reports.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: Text(
                                'You have not submitted any reports yet.',
                              ),
                            ),
                          );
                        }
                        final report = reports[index];
                        final style = reportStyle(report.status);
                        final date = report.createdAt?.toLocal();
                        return Card(
                          child: ListTile(
                            key: ValueKey('my-report-${report.id}'),
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: style.pin,
                              child: Icon(style.symbol, color: style.icon),
                            ),
                            title: Text(
                              report.title.isEmpty
                                  ? 'Road damage report'
                                  : report.title,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${style.label} · ${date == null ? 'Date unavailable' : localizations.formatMediumDate(date)}',
                                ),
                                if (report.description.isNotEmpty)
                                  Text(
                                    report.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showReportSheet(context, report),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
