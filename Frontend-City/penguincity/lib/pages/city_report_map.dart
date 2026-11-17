import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/services/city_reports.dart';

/// Fits every report, including cities whose reports span more than zoom 12.
CameraFit? reportCameraFit(List<CityReport> reports) => reports.isEmpty
    ? null
    : CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(
          reports.map((r) => LatLng(r.latitude, r.longitude)).toList(),
        ),
        padding: const EdgeInsets.all(56),
        maxZoom: 16,
      );

class CityReportMap extends StatefulWidget {
  const CityReportMap({super.key, required this.reports});
  final List<CityReport> reports;
  @override
  State<CityReportMap> createState() => _CityReportMapState();
}

class _CityReportMapState extends State<CityReportMap> {
  final _controller = MapController();
  String? _selectedId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fit() {
    final fit = reportCameraFit(widget.reports);
    if (fit != null) _controller.fitCamera(fit);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.reports
        .where((r) => r.id == _selectedId)
        .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth < 700
            ? constraints.maxWidth * .48
            : 340.0;
        return Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _controller,
                    options: MapOptions(
                      initialCenter: const LatLng(39.5, -98.35),
                      initialZoom: 4,
                      initialCameraFit: reportCameraFit(widget.reports),
                      minZoom: 3,
                      maxZoom: penguinMaxZoom,
                    ),
                    children: [
                      penguinTileLayer(appId: 'com.penguistics.penguincity'),
                      MarkerLayer(
                        markers: widget.reports.map((report) {
                          final style = reportStyle(report.status);
                          return Marker(
                            point: LatLng(report.latitude, report.longitude),
                            width: 44,
                            height: 46,
                            alignment: Alignment.topCenter,
                            child: Tooltip(
                              message: '${report.title} — ${style.label}',
                              child: Semantics(
                                button: true,
                                selected: selected?.id == report.id,
                                label: 'Open report: ${report.title}',
                                child: InkWell(
                                  key: ValueKey('report-${report.id}'),
                                  onTap: () =>
                                      setState(() => _selectedId = report.id),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        size: 46,
                                        color: selected?.id == report.id
                                            ? PenguinColors.blue
                                            : PenguinColors.black,
                                      ),
                                      Icon(
                                        Icons.location_on,
                                        size: 40,
                                        color: style.pin,
                                      ),
                                      Positioned(
                                        top: 9,
                                        child: Icon(
                                          style.symbol,
                                          size: 15,
                                          color: style.icon,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SimpleAttributionWidget(
                        source: Text('OpenStreetMap contributors'),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: FilledButton.icon(
                      onPressed: widget.reports.isEmpty ? null : _fit,
                      icon: const Icon(Icons.fit_screen),
                      label: const Text('Fit all reports'),
                    ),
                  ),
                ],
              ),
            ),
            if (selected != null)
              SizedBox(
                width: panelWidth,
                child: ReportDetailsPanel(
                  report: selected,
                  onClose: () => setState(() => _selectedId = null),
                ),
              ),
          ],
        );
      },
    );
  }
}

class ReportDetailsPanel extends StatelessWidget {
  const ReportDetailsPanel({
    super.key,
    required this.report,
    required this.onClose,
  });
  final CityReport report;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final style = reportStyle(report.status);
    final created = report.createdAt?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    return Material(
      elevation: 4,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close report',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ),
            Text(
              report.title.isEmpty ? 'Road damage' : report.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            StatusBanner(message: style.label, tone: style.tone),
            const SizedBox(height: 16),
            Text(
              report.description.isEmpty
                  ? 'No description provided.'
                  : report.description,
            ),
            const SizedBox(height: 16),
            Text(
              created == null
                  ? 'Report date unavailable'
                  : 'Reported: ${localizations.formatMediumDate(created)}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(created))}',
            ),
            const SizedBox(height: 12),
            Text(
              report.confidence == null
                  ? 'AI confidence unavailable'
                  : 'AI confidence: ${(report.confidence! * 100).round()}%',
            ),
            const SizedBox(height: 12),
            Text(
              report.locationSource == 'REMOTE'
                  ? 'Placed remotely on the map'
                  : 'Reported on site',
            ),
            const SizedBox(height: 12),
            SelectableText(
              'Coordinates: ${report.latitude.toStringAsFixed(5)}, ${report.longitude.toStringAsFixed(5)}',
            ),
          ],
        ),
      ),
    );
  }
}
