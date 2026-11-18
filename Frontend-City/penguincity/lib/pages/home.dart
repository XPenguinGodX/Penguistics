import 'package:flutter/material.dart';
import 'package:penguincity/pages/city_stats.dart';
import 'package:penguincity/pages/city_report_map.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/services/auth_session.dart';
import 'package:penguincity/services/city_reports.dart';

class Home extends StatefulWidget {
  const Home({super.key, this.loadReports});

  /// Supplies data without Cognito or AWS in widget tests.
  final Future<CityReports> Function()? loadReports;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _service = CityReportService();
  final _selected = cityMapStatuses.toSet();
  CityReports? _data;
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

  Future<CityReports> _loadReports() async =>
      _service.load(await accessToken());

  Future<String> _photoUrl(String id) async =>
      _service.photoUrl(id, await accessToken());

  Future<void> _changeStatus(CityReport report, String status) async {
    final updated = await _service.changeStatus(
      report.id,
      status,
      await accessToken(),
    );
    if (!mounted || _data == null) return;
    setState(() {
      final data = _data!;
      _data = CityReports(data.city, data.state, [
        for (final current in data.reports)
          if (current.id != updated.id)
            current
          else if (updated.status != 'DISMISSED')
            updated,
      ]);
    });
    showPenguinSnack(
      context,
      status == 'DISMISSED' ? 'Report dismissed.' : 'Report status updated.',
      tone: PenguinTone.success,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.loadReports?.call() ?? _loadReports());
      if (mounted) setState(() => _data = data);
    } on CityReportsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load city reports. Check your connection and refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final visible =
        data?.reports.where((r) => _selected.contains(r.status)).toList() ??
        <CityReport>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Penguistics City'),
        actions: [
          IconButton(
            tooltip: 'City statistics',
            icon: const Icon(Icons.insights),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const CityStats()),
            ),
          ),
          TextButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
          TextButton.icon(
            onPressed: () => signOut(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data == null ? 'City reports' : '${data.city}, ${data.state}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in cityMapStatuses)
                      FilterChip(
                        avatar: Icon(
                          reportStyle(status).symbol,
                          color: reportStyle(status).pin,
                          size: 18,
                        ),
                        label: Text(switch (status) {
                          'ACTIVE' => 'Active',
                          'COMPLETED' => 'Completed',
                          _ => 'Confirmed',
                        }),
                        tooltip: reportStyle(status).label,
                        selected: _selected.contains(status),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _selected.add(status);
                          } else {
                            _selected.remove(status);
                          }
                        }),
                      ),
                  ],
                ),
                if (data != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${visible.length} of ${data.reports.length} reports shown',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  StatusBanner(
                    message: data == null
                        ? _error!
                        : 'Showing previously loaded reports. $_error',
                    tone: PenguinTone.warning,
                  ),
                ],
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: data == null
                ? Center(
                    child: Text(
                      _loading
                          ? 'Loading city reports…'
                          : 'Reports could not be loaded. Use Refresh to try again.',
                    ),
                  )
                : data.reports.isEmpty
                ? const Center(
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'No confirmed, active, or completed reports in your city yet.',
                          ),
                        ),
                        Expanded(child: CityReportMap(reports: [])),
                      ],
                    ),
                  )
                : visible.isEmpty
                ? const Center(
                    child: Text(
                      'No reports match the selected filters. Select a status to show reports.',
                    ),
                  )
                : CityReportMap(
                    reports: visible,
                    onChangeStatus: _changeStatus,
                    loadPhoto: _photoUrl,
                  ),
          ),
        ],
      ),
    );
  }
}
