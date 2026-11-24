// Parks on a map: where each park's marker sits and which markers a map view
// holds, for the parks index's "List · N parks". Pure.
//
// Parity pair with apps/web/src/lib/parks/park_map.ts. Both read
// fixtures/park_map_cases.json.

import 'dart:math' as math;

typedef ParkMapPoint = ({double lat, double lng});

typedef ParkMapBounds = ({
  double south,
  double west,
  double north,
  double east,
});

bool _usable(double? lat, double? lng) =>
    lat != null &&
    lng != null &&
    lat.isFinite &&
    lng.isFinite &&
    lat.abs() <= 90 &&
    lng.abs() <= 180;

/// Where a park's marker goes: its stored centroid, else the middle of the box
/// round every course line (most catalogue parks carry no centroid), else
/// nowhere.
ParkMapPoint? parkMarkerPoint(
  ({double? lat, double? lng})? centroid,
  List<List<({double? lat, double? lng})>> lines,
) {
  if (centroid != null && _usable(centroid.lat, centroid.lng)) {
    return (lat: centroid.lat!, lng: centroid.lng!);
  }
  var south = double.infinity;
  var north = double.negativeInfinity;
  var west = double.infinity;
  var east = double.negativeInfinity;
  for (final line in lines) {
    for (final p in line) {
      if (!_usable(p.lat, p.lng)) continue;
      south = math.min(south, p.lat!);
      north = math.max(north, p.lat!);
      west = math.min(west, p.lng!);
      east = math.max(east, p.lng!);
    }
  }
  if (south == double.infinity) return null;
  return (lat: (south + north) / 2, lng: (west + east) / 2);
}

/// Whether a marker is inside a map view, edges included; a view whose west
/// is east of its east crosses the antimeridian.
bool pointInView(ParkMapPoint? point, ParkMapBounds view) {
  if (point == null) return false;
  if (point.lat < view.south || point.lat > view.north) return false;
  return view.west <= view.east
      ? point.lng >= view.west && point.lng <= view.east
      : point.lng >= view.west || point.lng <= view.east;
}

/// How many of the markers a map view holds.
int countInView(Iterable<ParkMapPoint?> points, ParkMapBounds view) =>
    points.where((p) => pointInView(p, view)).length;
