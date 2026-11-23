// What Routes → Explore lists: the routes (or segments) inside the map's
// current view, narrowed by the Filters sheet and ordered by the list page's
// sort chip (decisions § 2611). Pure, so the phone and the web order and count
// the same rows; the TS twin is `apps/web/src/lib/routes/explore_viewport.ts`.

import 'catalogue_browse.dart' show compareFoldedNames;
import 'run_stats.dart' show haversineMetres;

/// One thing on the map: a route's start pin, or a segment's start.
class ExplorePin {
  const ExplorePin({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.distanceM = 0,
    this.surface = '',
    this.featured = false,
    this.runCount = 0,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final double distanceM;
  final String surface;
  final bool featured;
  final int runCount;
}

class LatLngPoint {
  const LatLngPoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

class ViewBounds {
  const ViewBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });
  final double west;
  final double south;
  final double east;
  final double north;
}

enum ExploreSort { nearest, mostRun, name }

enum DistanceBucket { any, short, medium, long, ultra }

class ViewportFilter {
  const ViewportFilter({
    this.distance = DistanceBucket.any,
    this.useMiles = false,
    this.surface,
    this.featuredOnly = false,
  });

  final DistanceBucket distance;
  final bool useMiles;

  /// Null for any surface.
  final String? surface;
  final bool featuredOnly;

  bool get active =>
      distance != DistanceBucket.any || surface != null || featuredOnly;
}

const double _metresPerMile = 1609.344;

/// A bucket's bounds in metres, min inclusive and max exclusive. The ladder
/// is the race ladder of the reader's unit: 5 / 10 / 21 km, or 3 / 6 / 13 mi.
({double? min, double? max}) distanceBucketBounds(
    DistanceBucket bucket, bool useMiles) {
  final a = useMiles ? 3 * _metresPerMile : 5000.0;
  final b = useMiles ? 6 * _metresPerMile : 10000.0;
  final c = useMiles ? 13 * _metresPerMile : 21000.0;
  return switch (bucket) {
    DistanceBucket.any => (min: null, max: null),
    DistanceBucket.short => (min: null, max: a),
    DistanceBucket.medium => (min: a, max: b),
    DistanceBucket.long => (min: b, max: c),
    DistanceBucket.ultra => (min: c, max: null),
  };
}

List<T> filterViewport<T extends ExplorePin>(
    Iterable<T> pins, ViewportFilter f) {
  final bounds = distanceBucketBounds(f.distance, f.useMiles);
  final min = bounds.min;
  final max = bounds.max;
  return [
    for (final p in pins)
      if ((min == null || p.distanceM >= min) &&
          (max == null || p.distanceM < max) &&
          (f.surface == null || p.surface == f.surface) &&
          (!f.featuredOnly || p.featured))
        p,
  ];
}

/// Nearest first only means something once the reader's place is known.
ExploreSort defaultSort(LatLngPoint? origin) =>
    origin != null ? ExploreSort.nearest : ExploreSort.mostRun;

/// The list page's order. Every branch ends on the folded name and then the
/// id, so the order never depends on sort stability. Nearest with no origin
/// falls back to most run.
List<T> sortViewport<T extends ExplorePin>(
    Iterable<T> pins, ExploreSort sort, LatLngPoint? origin) {
  int byName(T a, T b) => compareFoldedNames(a.name, a.id, b.name, b.id);
  final out = pins.toList();
  if (sort == ExploreSort.nearest && origin != null) {
    final d = {
      for (final p in out)
        p.id: haversineMetres(origin.lat, origin.lng, p.lat, p.lng),
    };
    out.sort((a, b) {
      final c = d[a.id]!.compareTo(d[b.id]!);
      return c != 0 ? c : byName(a, b);
    });
  } else if (sort == ExploreSort.name) {
    out.sort(byName);
  } else {
    out.sort((a, b) {
      final c = b.runCount.compareTo(a.runCount);
      return c != 0 ? c : byName(a, b);
    });
  }
  return out;
}

/// Whether a point is in view, across the antimeridian too.
bool inBounds(double lat, double lng, ViewBounds b) {
  if (lat < b.south || lat > b.north) return false;
  return b.west <= b.east
      ? lng >= b.west && lng <= b.east
      : lng >= b.west || lng <= b.east;
}

/// The pin closest to [center], for the empty view's way back.
T? nearestTo<T extends ExplorePin>(Iterable<T> pins, LatLngPoint center) {
  T? best;
  var bestD = double.infinity;
  for (final p in pins) {
    final d = haversineMetres(center.lat, center.lng, p.lat, p.lng);
    if (d < bestD ||
        (d == bestD &&
            best != null &&
            compareFoldedNames(p.name, p.id, best.name, best.id) < 0)) {
      best = p;
      bestD = d;
    }
  }
  return best;
}
