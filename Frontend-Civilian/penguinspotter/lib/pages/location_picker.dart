import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:penguin/theme/penguin_theme.dart';
import 'package:penguin/widgets/penguin_map.dart';

/// Full-screen map for placing a REMOTE report's pin.
/// The pin stays fixed in the middle of the screen and the map moves underneath it.
/// Returns the chosen spot with Navigator.pop, or null if the user backs out.
class LocationPicker extends StatefulWidget {
  const LocationPicker({super.key, required this.device, this.initial});

  /// Where the phone really is; the pin must stay within [remoteRadiusKm] of it.
  final LatLng device;

  /// A spot picked earlier, so "Move pin" starts where the user left it.
  final LatLng? initial;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final MapController _mapController = MapController();
  // Haversine matches the formula the backend uses to check the same limit
  static const _distance = Distance(roundResult: false, calculator: Haversine());
  late LatLng _center = widget.initial ?? widget.device;

  double get _distanceKm =>
      _distance.as(LengthUnit.Kilometer, widget.device, _center);

  bool get _inRange => _distanceKm <= remoteRadiusKm;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Where is the damage?')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              minZoom: penguinMinZoom,
              maxZoom: penguinMaxZoom,
              // Every pan or zoom moves the spot under the fixed center pin
              onPositionChanged: (camera, hasGesture) {
                setState(() => _center = camera.center);
              },
            ),
            children: [
              penguinTileLayer(),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: widget.device,
                    // useRadiusInMeter makes the circle a real distance on the ground,
                    // so it grows and shrinks as the user zooms
                    radius: remoteRadiusKm * 1000,
                    useRadiusInMeter: true,
                    color: PenguinColors.blue.withValues(alpha: 0.08),
                    borderColor: PenguinColors.blue,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // A small dot for where the user is standing
                  Marker(
                    point: widget.device,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: PenguinColors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: PenguinColors.white, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
          // The fixed pin. IgnorePointer lets drags pass through it to the map.
          // The bottom padding lifts the icon so its tip, not its middle, marks the center.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 48),
                child: Icon(
                  Icons.location_on,
                  size: 52,
                  color: PenguinColors.orange,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PenguinColors.charcoal,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: PenguinColors.outline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _inRange
                        ? '${_distanceKm.toStringAsFixed(1)} km from you'
                        : 'Too far: remote reports must be within '
                              '${remoteRadiusKm.toStringAsFixed(0)} km of you',
                    style: text.bodyLarge?.copyWith(
                      color: _inRange
                          ? PenguinColors.white
                          : PenguinColors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            _mapController.move(widget.device, 15),
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Me'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _inRange
                              ? () => Navigator.pop(context, _center)
                              : null,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Use this spot'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
