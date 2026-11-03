import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:penguin/services/auth_session.dart';
import 'package:penguin/services/report_service.dart';
import 'package:penguin/theme/penguin_theme.dart';
import 'package:penguin/widgets/penguin_menu.dart';
import 'package:penguin/widgets/penguin_widgets.dart';
import 'package:penguin/widgets/report_pins.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(37.7744, -122.4194);
  bool _isLocating = true;
  Offset _buttonPosition = const Offset(20, 100);
  // Roughly the size of the "Report Damage" button, used to keep it on screen
  static const _reportButtonSize = Size(200, 56);
  final ReportService _reports = ReportService();
  List<ReportSummary> _myReports = const [];

  @override
  void initState() {
    super.initState();
    _loadUserLocation();
    _loadMyReports();
  }

  @override
  void dispose() {
    _reports.close();
    super.dispose();
  }

  Future<void> _loadMyReports() async {
    try {
      final reports = await _reports.listMine(accessToken: await accessToken());
      if (mounted) setState(() => _myReports = reports);
    } catch (_) {
      // The map still works without pins, so this is a gentle note, not an error
      if (mounted) {
        showPenguinSnack(context, 'Could not load your reports right now.');
      }
    }
  }

  Future<void> _openReportForm() async {
    await Navigator.pushNamed(context, '/report');
    // Coming back from the form: refresh so a new report shows up as a pin
    if (mounted) _loadMyReports();
  }

  Future<void> _loadUserLocation() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          showPenguinSnack(
            context,
            'Location services are disabled.',
            tone: PenguinTone.warning,
          );
        }
        setState(() => _isLocating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            showPenguinSnack(
              context,
              'Location permission denied.',
              tone: PenguinTone.warning,
            );
          }
          setState(() => _isLocating = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          showPenguinSnack(
            context,
            'Location permissions are permanently denied. Please enable them in settings.',
            tone: PenguinTone.warning,
          );
        }
        setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final userLatLng = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _currentLocation = userLatLng;
          _isLocating = false;
        });
        _mapController.move(userLatLng, 17.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLocating = false);
        showPenguinSnack(
          context,
          'Could not find your location. Check that GPS is on.',
          tone: PenguinTone.warning,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // An endDrawer makes the AppBar show a hamburger button on the right
      endDrawer: const PenguinMenu(),
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            PenguinLogo(size: 34),
            SizedBox(width: 10),
            PenguinWordmark(fontSize: 22),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _isLocating
              ? const LinearProgressIndicator(
                  minHeight: 4,
                  color: PenguinColors.yellow,
                  backgroundColor: PenguinColors.black,
                )
              : Container(height: 4, color: PenguinColors.yellow),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadUserLocation,
        tooltip: 'Center on my location',
        backgroundColor: PenguinColors.blue,
        foregroundColor: PenguinColors.white,
        child: const Icon(Icons.my_location_rounded),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.penguin',
              ),
              MarkerLayer(
                markers: [
                  for (final report in _myReports)
                    reportMarker(
                      report,
                      () => showReportSheet(context, report),
                    ),
                  // Listed last so the user's own marker is drawn on top
                  Marker(
                    point: _currentLocation,
                    width: 56,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: const Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 52,
                          color: PenguinColors.blue,
                        ),
                        Positioned(
                          top: 9,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: PenguinColors.yellow,
                            child: CircleAvatar(
                              radius: 6,
                              backgroundColor: PenguinColors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
          if (_myReports.isNotEmpty)
            const Positioned(left: 12, bottom: 12, child: ReportPinLegend()),
          Positioned(
            left: _buttonPosition.dx,
            top: _buttonPosition.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                // Keep the whole button on screen, however far it's dragged
                final next = _buttonPosition + details.delta;
                setState(() {
                  _buttonPosition = Offset(
                    next.dx.clamp(
                      0,
                      max(0, constraints.maxWidth - _reportButtonSize.width),
                    ),
                    next.dy.clamp(
                      0,
                      max(0, constraints.maxHeight - _reportButtonSize.height),
                    ),
                  );
                });
              },
              child: FloatingActionButton.extended(
                heroTag: 'report_fab',
                onPressed: _openReportForm,
                shape: const StadiumBorder(
                  side: BorderSide(color: PenguinColors.black, width: 2),
                ),
                icon: const Icon(Icons.add_road_rounded),
                label: const Text(
                  'Report Damage',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
