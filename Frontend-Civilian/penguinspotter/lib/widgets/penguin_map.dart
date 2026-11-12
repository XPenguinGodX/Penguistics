import 'package:flutter_map/flutter_map.dart';

/// Zoom limits shared by every map in the app.
/// 12 shows about one whole city; zooming out further loads far more tiles.
const double penguinMinZoom = 12;

/// OpenStreetMap does not draw tiles past zoom 19.
const double penguinMaxZoom = 19;

/// How far a REMOTE report's pin may be from the phone.
/// Must match REMOTE_RADIUS_KM in Backend/scripts/process_report.py, which enforces it.
const double remoteRadiusKm = 12;

/// The OpenStreetMap tile layer, tuned to request as few tiles as possible.
TileLayer penguinTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  // OSM's tile policy asks apps to identify themselves; a placeholder ID can be blocked
  userAgentPackageName: 'com.penguistics.penguinspotter',
  // Past zoom 19, stretch the level-19 tiles instead of requesting ones that don't exist
  maxNativeZoom: penguinMaxZoom.toInt(),
  // Keep fewer off-screen tiles in memory (default 2)
  keepBuffer: 1,
  // Don't preload tiles outside the visible screen (default 1)
  panBuffer: 0,
);
