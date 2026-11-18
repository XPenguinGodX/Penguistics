import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/config.dart';
import 'package:penguincity/services/auth_session.dart';
import 'package:penguincity/services/city_reports.dart';

class CityStats extends StatefulWidget {
  const CityStats({super.key, this.loadStats});
  final Future<Map<String, dynamic>> Function()? loadStats;
  @override
  State<CityStats> createState() => _CityStatsState();
}

class _CityStatsState extends State<CityStats> {
  final _client = http.Client();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    if (penApi.isEmpty) {
      throw const CityReportsException('PEN_API is not configured.');
    }
    final response = await _client
        .get(
          Uri.parse('${penApi.replaceFirst(RegExp(r'/+$'), '')}/city/stats'),
          headers: {'Authorization': 'Bearer ${await accessToken()}'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw CityReportsException(switch (response.statusCode) {
        401 => 'Your session expired. Sign out and log in again.',
        403 => 'This account cannot view city statistics.',
        _ => 'City statistics are temporarily unavailable.',
      });
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        data['counts'] is! Map ||
        data['daily'] is! List ||
        data['city'] is! String ||
        data['state'] is! String) {
      throw const FormatException('Invalid stats response.');
    }
    return data;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.loadStats?.call() ?? _load());
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is CityReportsException
              ? e.message
              : 'Could not load city statistics. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final counts = data?['counts'] as Map? ?? {};
    final daily = data?['daily'] as List? ?? [];
    final average = data?['average_completion_seconds'] as num?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('City statistics'),
        actions: [
          IconButton(
            tooltip: 'Refresh statistics',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    StatusBanner(message: _error!, tone: PenguinTone.warning),
                  if (data != null) ...[
                    Text(
                      '${data['city']}, ${data['state']}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final status in [...cityMapStatuses, 'DISMISSED'])
                          SizedBox(
                            width: 180,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Text(reportStyle(status).label),
                                    Text(
                                      '${counts[status] ?? 0}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      average == null
                          ? 'Average submission-to-completion time: no completed reports yet.'
                          : 'Average submission-to-completion time: ${(average / 86400).toStringAsFixed(1)} days',
                    ),
                    const Text(
                      'Uses submission date and the completed report’s last update. Confirmation time is not recorded.',
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Reports submitted over the last 30 days (UTC)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Confirmed, active, completed, and dismissed reports. Dates with no reports are omitted.',
                    ),
                    if (daily.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No reports in the last 30 days.'),
                      ),
                    for (final row in daily)
                      ListTile(
                        title: Text('${row['day']}'),
                        trailing: Text('${row['count']} reports'),
                      ),
                  ] else if (_loading)
                    const Text('Loading statistics…'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
