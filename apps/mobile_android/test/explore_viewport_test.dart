import 'package:flutter_test/flutter_test.dart';

import '../lib/explore_viewport.dart';

ExplorePin pin(
  String id,
  String name, {
  double lat = 0,
  double lng = 0,
  double distanceM = 5000,
  String surface = 'road',
  bool featured = false,
  int runCount = 0,
}) =>
    ExplorePin(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      distanceM: distanceM,
      surface: surface,
      featured: featured,
      runCount: runCount,
    );

void main() {
  test('distance buckets follow the race ladder of the reader unit', () {
    expect(distanceBucketBounds(DistanceBucket.any, false),
        (min: null, max: null));
    expect(distanceBucketBounds(DistanceBucket.short, false),
        (min: null, max: 5000.0));
    expect(distanceBucketBounds(DistanceBucket.long, false),
        (min: 10000.0, max: 21000.0));
    expect(distanceBucketBounds(DistanceBucket.ultra, true),
        (min: 13 * 1609.344, max: null));
    expect(distanceBucketBounds(DistanceBucket.medium, true),
        (min: 3 * 1609.344, max: 6 * 1609.344));
  });

  test('filterViewport narrows by distance, surface and featured, min '
      'inclusive and max exclusive', () {
    final pins = [
      pin('a', 'A', distanceM: 4999),
      pin('b', 'B', distanceM: 5000, surface: 'trail'),
      pin('c', 'C', distanceM: 9999, featured: true),
      pin('d', 'D', distanceM: 10000),
    ];
    List<String> ids(ViewportFilter f) =>
        filterViewport(pins, f).map((p) => p.id).toList();
    expect(ids(const ViewportFilter(distance: DistanceBucket.medium)),
        ['b', 'c']);
    expect(ids(const ViewportFilter(surface: 'trail')), ['b']);
    expect(ids(const ViewportFilter(featuredOnly: true)), ['c']);
    expect(ids(const ViewportFilter(distance: DistanceBucket.short)), ['a']);
  });

  test('filterActive is false only for the default filter', () {
    expect(const ViewportFilter().active, isFalse);
    expect(const ViewportFilter(distance: DistanceBucket.long).active, isTrue);
    expect(const ViewportFilter(surface: 'road').active, isTrue);
    expect(const ViewportFilter(featuredOnly: true).active, isTrue);
  });

  test('defaultSort is nearest only once the reader place is known', () {
    expect(defaultSort(null), ExploreSort.mostRun);
    expect(defaultSort(const LatLngPoint(1, 2)), ExploreSort.nearest);
  });

  test('sortViewport nearest orders by distance from the origin, ties by '
      'folded name', () {
    final pins = [
      pin('far', 'Far', lat: 1),
      pin('z', 'Zed', lat: 0.1),
      pin('e', 'Éa', lat: 0.1),
    ];
    expect(
        sortViewport(pins, ExploreSort.nearest, const LatLngPoint(0, 0))
            .map((p) => p.id),
        ['e', 'z', 'far']);
  });

  test('sortViewport most run puts the busiest first, and nearest with no '
      'origin falls back to it', () {
    final pins = [
      pin('a', 'B', runCount: 2),
      pin('b', 'A', runCount: 9),
      pin('c', 'A', runCount: 2),
    ];
    expect(sortViewport(pins, ExploreSort.mostRun, null).map((p) => p.id),
        ['b', 'c', 'a']);
    expect(sortViewport(pins, ExploreSort.nearest, null).map((p) => p.id),
        ['b', 'c', 'a']);
  });

  test('sortViewport name folds accents and breaks ties on id, leaving the '
      'input alone', () {
    final pins = [pin('2', 'zurich'), pin('1', 'Zürich'), pin('3', 'Alpha')];
    expect(sortViewport(pins, ExploreSort.name, null).map((p) => p.id),
        ['3', '1', '2']);
    expect(pins.map((p) => p.id), ['2', '1', '3']);
  });

  test('inBounds handles a view across the antimeridian', () {
    const plain = ViewBounds(west: -10, south: -10, east: 10, north: 10);
    expect(inBounds(0, 0, plain), isTrue);
    expect(inBounds(11, 0, plain), isFalse);
    expect(inBounds(0, -11, plain), isFalse);
    const wrapped = ViewBounds(west: 170, south: -10, east: -170, north: 10);
    expect(inBounds(0, 175, wrapped), isTrue);
    expect(inBounds(0, -175, wrapped), isTrue);
    expect(inBounds(0, 0, wrapped), isFalse);
  });

  test('nearestTo picks the closest pin, and null with none', () {
    expect(nearestTo(<ExplorePin>[], const LatLngPoint(0, 0)), isNull);
    final pins = [
      pin('far', 'Far', lat: 5, lng: 5),
      pin('near', 'Near', lat: 1, lng: 1),
    ];
    expect(nearestTo(pins, const LatLngPoint(0, 0))?.id, 'near');
  });
}
