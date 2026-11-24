import 'package:core_models/core_models.dart' show Run, finiteWaypoints;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_run_store.dart';

/// A browse map's camera: its centre and zoom.
typedef MapView = ({double lat, double lng, double zoom});

/// Where a browse map can open, weakest first. A map opens on the strongest
/// one it has and moves up when a stronger one arrives, until the runner
/// touches it (decisions § 2613).
enum MapOpening {
  /// Nothing better is known.
  world,

  /// The start of the runner's newest recorded run with a track: on this
  /// phone already, and needs no location permission.
  lastRun,

  /// Where the runner last left this map.
  remembered,

  /// A quiet fix of where the runner is now.
  here,
}

/// Whether a map that opened on [current] moves to [next]: only to a stronger
/// opening, and never once the runner has moved it themselves.
bool opensOn(MapOpening current, MapOpening next, {required bool touched}) =>
    !touched && next.index > current.index;

/// How many of the newest runs [lastRunStart] looks through for one with a
/// track: an imported or hand-added run has none.
const int kLastRunScan = 20;

/// Where the newest of [store]'s runs that has a track started, or null.
/// Reads the resident runs only, so it never loads a track from disk.
LatLng? lastRunStart(LocalRunStore? store) =>
    store == null ? null : newestRunStart(store.recentWindow(kLastRunScan));

/// The start of the first of [newestFirst] with a usable track point.
LatLng? newestRunStart(Iterable<Run> newestFirst) {
  for (final run in newestFirst) {
    final points = finiteWaypoints(run.track);
    if (points.isNotEmpty) return LatLng(points.first.lat, points.first.lng);
  }
  return null;
}

/// The least zoom worth remembering: the world view a map opens on when it
/// knows nothing is not a place the runner chose.
const double kRememberedMinZoom = 4;

/// Where a browse map was last left, kept on this phone only. A failed read
/// or write is logged and ignored: the map still opens, on a weaker view.
class MapViewMemory {
  const MapViewMemory(this.key, {this.prefs = SharedPreferences.getInstance});

  /// The preferences key, one per map.
  final String key;

  /// Test seam.
  final Future<SharedPreferences> Function() prefs;

  Future<MapView?> load() async {
    try {
      final raw = (await prefs()).getString(key);
      return raw == null ? null : decodeMapView(raw);
    } catch (e) {
      debugPrint('map view memory: read failed: $e');
      return null;
    }
  }

  Future<void> save(MapView view) async {
    if (view.zoom < kRememberedMinZoom) return;
    try {
      await (await prefs()).setString(key, encodeMapView(view));
    } catch (e) {
      debugPrint('map view memory: write failed: $e');
    }
  }
}

String encodeMapView(MapView v) => '${v.lat},${v.lng},${v.zoom}';

/// Null for anything that is not three finite numbers with the centre on the
/// globe, so a corrupt value opens the map on a weaker view.
MapView? decodeMapView(String raw) {
  final parts = raw.split(',');
  if (parts.length != 3) return null;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  final zoom = double.tryParse(parts[2]);
  if (lat == null || lng == null || zoom == null) return null;
  if (!lat.isFinite || !lng.isFinite || !zoom.isFinite) return null;
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return (lat: lat, lng: lng, zoom: zoom);
}
