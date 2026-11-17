import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/services/city_reports.dart';
import 'package:penguincity/pages/report_status_actions.dart';
import 'package:penguincity/pages/report_photo.dart';
import 'package:penguincity/pages/report_queue.dart';

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
  const CityReportMap({
    super.key,
    required this.reports,
    this.onChangeStatus,
    this.loadPhoto,
  });
  final Future<String> Function(String)? loadPhoto;
  final List<CityReport> reports;
  final Future<void> Function(CityReport, String)? onChangeStatus;
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

  void _selectReport(CityReport report) {
    setState(() => _selectedId = report.id);
    // Wait for the side panel to take its width before centering the pin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.move(
          LatLng(report.latitude, report.longitude),
          penguinMaxZoom,
        );
      }
    });
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
              child: Column(
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
                            penguinTileLayer(
                              appId: 'com.penguistics.penguincity',
                            ),
                            MarkerClusterLayerWidget(
                              key: ValueKey(
                                Object.hash(
                                  widget.reports
                                      .map((r) => '${r.id}:${r.status}')
                                      .join(','),
                                  selected?.id,
                                ),
                              ),
                              options: MarkerClusterLayerOptions(
                                maxClusterRadius: 55,
                                size: const Size(44, 44),
                                maxZoom: penguinMaxZoom,
                                disableClusteringAtZoom: 19,
                                padding: const EdgeInsets.all(56),
                                showPolygon: false,
                                markerChildBehavior: true,
                                builder: (context, markers) => Semantics(
                                  button: true,
                                  label:
                                      '${markers.length} reports. Zoom in to explore.',
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: PenguinColors.blue,
                                      border: Border.all(
                                        color: PenguinColors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: Text(
                                      '${markers.length}',
                                      style: const TextStyle(
                                        color: PenguinColors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                markers: widget.reports
                                    .where((r) => r.id != selected?.id)
                                    .map((report) {
                                      final style = reportStyle(report.status);
                                      return Marker(
                                        point: LatLng(
                                          report.latitude,
                                          report.longitude,
                                        ),
                                        width: 44,
                                        height: 46,
                                        alignment: Alignment.topCenter,
                                        child: Tooltip(
                                          message:
                                              '${report.title} — ${style.label}',
                                          child: Semantics(
                                            button: true,
                                            selected: selected?.id == report.id,
                                            label:
                                                'Open report: ${report.title}',
                                            child: InkWell(
                                              key: ValueKey(
                                                'report-${report.id}',
                                              ),
                                              onTap: () => setState(
                                                () => _selectedId = report.id,
                                              ),
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.location_on,
                                                    size: 46,
                                                    color:
                                                        selected?.id ==
                                                            report.id
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
                                    })
                                    .toList(),
                              ),
                            ),
                            if (selected != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                      selected.latitude,
                                      selected.longitude,
                                    ),
                                    width: 44,
                                    height: 46,
                                    alignment: Alignment.topCenter,
                                    child: Tooltip(
                                      message: selected.title,
                                      child: InkWell(
                                        key: ValueKey('report-${selected.id}'),
                                        onTap: () => _selectReport(selected),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            const Icon(
                                              Icons.location_on,
                                              size: 46,
                                              color: PenguinColors.blue,
                                            ),
                                            Icon(
                                              Icons.location_on,
                                              size: 40,
                                              color: reportStyle(
                                                selected.status,
                                              ).pin,
                                            ),
                                            Positioned(
                                              top: 9,
                                              child: Icon(
                                                reportStyle(
                                                  selected.status,
                                                ).symbol,
                                                size: 15,
                                                color: reportStyle(
                                                  selected.status,
                                                ).icon,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const Align(
                              alignment: Alignment.bottomRight,
                              child: SizedBox(
                                width: 180,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'OpenStreetMap contributors',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
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
                  SizedBox(
                    height: constraints.maxHeight * .35,
                    child: ReportQueue(
                      reports: widget.reports,
                      selectedId: selected?.id,
                      onSelect: _selectReport,
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
                  onChangeStatus: widget.onChangeStatus,
                  loadPhoto: widget.loadPhoto,
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
    this.onChangeStatus,
    this.loadPhoto,
  });
  final CityReport report;
  final VoidCallback onClose;
  final Future<String> Function(String)? loadPhoto;
  final Future<void> Function(CityReport, String)? onChangeStatus;

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
            if (loadPhoto != null) ...[
              const SizedBox(height: 16),
              ReportPhoto(
                key: ValueKey('photo-${report.id}'),
                loadUrl: () => loadPhoto!(report.id),
              ),
            ],
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
            if (onChangeStatus != null) ...[
              const SizedBox(height: 20),
              ReportStatusActions(
                key: ValueKey(report.id),
                report: report,
                onChange: onChangeStatus!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
