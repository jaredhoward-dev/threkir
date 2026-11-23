import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/park_map.dart';

/// The Dart reader of `fixtures/park_map_cases.json`, the case table the
/// `park_map` pair shares with web's `park_map.test.ts`.
final Map<String, dynamic> _fixture =
    jsonDecode(File('../../fixtures/park_map_cases.json').readAsStringSync())
        as Map<String, dynamic>;

({double? lat, double? lng}) _pt(Map<String, dynamic> p) => (
  lat: (p['lat'] as num?)?.toDouble(),
  lng: (p['lng'] as num?)?.toDouble(),
);

ParkMapPoint? _point(Object? p) {
  if (p == null) return null;
  final m = p as Map<String, dynamic>;
  return (lat: (m['lat'] as num).toDouble(), lng: (m['lng'] as num).toDouble());
}

void main() {
  for (final c in (_fixture['markerCases'] as List).cast<Map<String, dynamic>>()) {
    test('marker: ${c['name']}', () {
      final centroid = c['centroid'] as Map<String, dynamic>?;
      final got = parkMarkerPoint(
        centroid == null ? null : _pt(centroid),
        [
          for (final line in c['lines'] as List)
            [for (final p in line as List) _pt(p as Map<String, dynamic>)],
        ],
      );
      final want = _point(c['point']);
      if (want == null) {
        expect(got, isNull);
        return;
      }
      expect(got, isNotNull);
      expect((got!.lat - want.lat).abs(), lessThan(1e-9));
      expect((got.lng - want.lng).abs(), lessThan(1e-9));
    });
  }

  for (final c in (_fixture['viewCases'] as List).cast<Map<String, dynamic>>()) {
    test('view: ${c['name']}', () {
      final b = c['bounds'] as Map<String, dynamic>;
      final ParkMapBounds view = (
        south: (b['south'] as num).toDouble(),
        west: (b['west'] as num).toDouble(),
        north: (b['north'] as num).toDouble(),
        east: (b['east'] as num).toDouble(),
      );
      final points = [for (final p in c['points'] as List) _point(p)];
      final want = (c['inView'] as List).cast<bool>();
      expect([for (final p in points) pointInView(p, view)], want);
      expect(countInView(points, view), want.where((v) => v).length);
    });
  }
}
