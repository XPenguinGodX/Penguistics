import 'package:flutter_map/flutter_map.dart';

/// Zoom limits shared by every map in both apps.
/// 12 shows about one whole city; zooming out further loads far more tiles.
const double penguinMinZoom = 12;

/// OpenStreetMap does not draw tiles past zoom 19.
const double penguinMaxZoom = 19;

/// The OpenStreetMap tile layer, tuned to request as few tiles as possible.
///
/// [appId] identifies the app to OpenStreetMap, whose tile policy asks for it
/// (a placeholder ID can be blocked). Each app passes its own.
TileLayer penguinTileLayer({String appId = 'com.penguistics.penguinspotter'}) => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: appId,
  // Past zoom 19, stretch the level-19 tiles instead of requesting ones that don't exist
  maxNativeZoom: penguinMaxZoom.toInt(),
  // Keep fewer off-screen tiles in memory (default 2)
  keepBuffer: 1,
  // Don't preload tiles outside the visible screen (default 1)
  panBuffer: 0,
);
