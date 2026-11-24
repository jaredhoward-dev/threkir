import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/map_view_memory.dart';
import '../lib/widgets/explore_routes_map.dart';
import 'pump_until.dart';

Run _run(String id, DateTime at, List<Waypoint> track) => Run(
      id: id,
      startedAt: at,
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      track: track,
      source: RunSource.app,
    );

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 11, 24),
      accuracy: 20,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

const _key = 'test_map_view';

/// Records every save, so a test can wait on one landing.
class _RecordingMemory extends MapViewMemory {
  _RecordingMemory() : super(_key);
  final List<MapView> saved = [];

  @override
  Future<void> save(MapView view) async => saved.add(view);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('decodeMapView', () {
    test('round-trips what encodeMapView writes', () {
      const view = (lat: 37.5407, lng: -77.436, zoom: 12.5);
      expect(decodeMapView(encodeMapView(view)), view);
    });

    test('refuses anything that is not three finite numbers on the globe', () {
      for (final raw in [
        '',
        '1,2',
        '1,2,3,4',
        'a,2,3',
        '1,,3',
        'NaN,2,3',
        '1,Infinity,3',
        '91,0,5',
        '0,181,5',
      ]) {
        expect(decodeMapView(raw), isNull, reason: raw);
      }
    });
  });

  test('a map moves only to a stronger opening, and never once touched', () {
    expect(opensOn(MapOpening.world, MapOpening.lastRun, touched: false),
        isTrue);
    expect(opensOn(MapOpening.lastRun, MapOpening.remembered, touched: false),
        isTrue);
    expect(opensOn(MapOpening.remembered, MapOpening.here, touched: false),
        isTrue);
    expect(opensOn(MapOpening.here, MapOpening.remembered, touched: false),
        isFalse);
    expect(opensOn(MapOpening.lastRun, MapOpening.lastRun, touched: false),
        isFalse);
    expect(opensOn(MapOpening.world, MapOpening.here, touched: true), isFalse);
  });

  group('newestRunStart', () {
    test('is the first point of the newest run that has a track', () {
      final start = newestRunStart([
        _run('manual', DateTime.utc(2026, 11, 23), const []),
        _run('recorded', DateTime.utc(2026, 11, 22), const [
          Waypoint(lat: 37.5, lng: -77.4),
          Waypoint(lat: 37.6, lng: -77.5),
        ]),
        _run('older', DateTime.utc(2026, 11, 1), const [
          Waypoint(lat: 10, lng: 10),
        ]),
      ]);
      expect(start, const LatLng(37.5, -77.4));
    });

    test('skips a track with no usable point, and is null with none', () {
      expect(
        newestRunStart([
          _run('bad', DateTime.utc(2026, 11, 23), const [
            Waypoint(lat: double.nan, lng: 1),
          ]),
          _run('good', DateTime.utc(2026, 11, 20), const [
            Waypoint(lat: 1, lng: 2),
          ]),
        ]),
        const LatLng(1, 2),
      );
      expect(newestRunStart(const []), isNull);
      expect(lastRunStart(null), isNull);
    });
  });

  group('MapViewMemory', () {
    test('keeps a chosen view and forgets nothing it was not given', () async {
      const memory = MapViewMemory(_key);
      expect(await memory.load(), isNull);
      await memory.save((lat: 37.5, lng: -77.4, zoom: 12));
      expect(await memory.load(), (lat: 37.5, lng: -77.4, zoom: 12.0));
    });

    test('does not remember the world view', () async {
      const memory = MapViewMemory(_key);
      await memory.save((lat: 20, lng: 0, zoom: 2));
      expect(await memory.load(), isNull);
    });

    test('reads a corrupt value as nothing', () async {
      SharedPreferences.setMockInitialValues({_key: 'not a view'});
      expect(await const MapViewMemory(_key).load(), isNull);
    });

    test('a storage failure opens on a weaker view, not an error', () async {
      final memory = MapViewMemory(_key, prefs: () => Future.error('no store'));
      expect(await memory.load(), isNull);
      await memory.save((lat: 1, lng: 2, zoom: 10));
    });
  });

  group('ExploreRoutesMap opening view', () {
    Future<MapController> pump(
      WidgetTester tester, {
      Stream<Position> Function()? fixes,
      LatLng? lastRun,
      MapViewMemory memory = const MapViewMemory(_key),
    }) async {
      final controller = MapController();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExploreRoutesMap(
            api: null,
            controller: controller,
            onPins: (_, _, _) {},
            onTap: (_) {},
            quietFixes: fixes ?? () => const Stream.empty(),
            lastRunStart: lastRun,
            memory: memory,
          ),
        ),
      ));
      await tester.pump();
      return controller;
    }

    Future<void> settleOn(
        WidgetTester tester, MapController map, LatLng at, double zoom) =>
        pumpUntil(
          tester,
          () {
            final c = map.camera;
            return (c.center.latitude - at.latitude).abs() < 1e-6 &&
                (c.center.longitude - at.longitude).abs() < 1e-6 &&
                (c.zoom - zoom).abs() < 1e-6;
          },
          describe: 'the map to open on $at at $zoom',
        );

    testWidgets('with nothing known it opens on the world', (tester) async {
      final map = await pump(tester);
      final state =
          tester.state<ExploreRoutesMapState>(find.byType(ExploreRoutesMap));
      await pumpUntil(tester, () => state.recalled,
          describe: 'the remembered view to be read');
      await tester.pump();
      expect(map.camera.zoom, 2);
    });

    testWidgets('opens on the newest run when that is all it knows',
        (tester) async {
      final map = await pump(tester, lastRun: const LatLng(37.5, -77.4));
      await settleOn(tester, map, const LatLng(37.5, -77.4), 12);
    });

    testWidgets('where it was last left beats the newest run', (tester) async {
      SharedPreferences.setMockInitialValues({_key: '51.5,-0.12,10'});
      final map = await pump(tester, lastRun: const LatLng(37.5, -77.4));
      await settleOn(tester, map, const LatLng(51.5, -0.12), 10);
    });

    testWidgets('a quiet fix beats where it was last left', (tester) async {
      SharedPreferences.setMockInitialValues({_key: '51.5,-0.12,10'});
      final fixes = StreamController<Position>();
      addTearDown(fixes.close);
      final map = await pump(tester,
          fixes: () => fixes.stream, lastRun: const LatLng(37.5, -77.4));
      await settleOn(tester, map, const LatLng(51.5, -0.12), 10);
      fixes.add(_pos(40.7, -74.0));
      await settleOn(tester, map, const LatLng(40.7, -74.0), 12);
    });

    testWidgets('a move the page claims for the runner stops a late fix',
        (tester) async {
      final fixes = StreamController<Position>();
      addTearDown(fixes.close);
      final map = await pump(tester, fixes: () => fixes.stream);
      final state =
          tester.state<ExploreRoutesMapState>(find.byType(ExploreRoutesMap));
      state.claim();
      map.move(const LatLng(48.85, 2.35), 13);
      await tester.pump();
      fixes.add(_pos(40.7, -74.0));
      await tester.pump();
      expect(map.camera.center.latitude, closeTo(48.85, 1e-6));
    });

    testWidgets('remembers where the runner left it', (tester) async {
      final memory = _RecordingMemory();
      final map = await pump(tester, memory: memory);
      final state =
          tester.state<ExploreRoutesMapState>(find.byType(ExploreRoutesMap));
      await pumpUntil(tester, () => state.recalled,
          describe: 'the remembered view to be read');
      map.move(const LatLng(35.0, 139.0), 11);
      // The save rides the 300 ms settle debounce, a fake-clock timer that
      // pumpUntil never advances.
      await tester.pump(const Duration(milliseconds: 300));
      expect(memory.saved, isNotEmpty);
      final last = memory.saved.last;
      expect(last.lat, closeTo(35.0, 1e-6));
      expect(last.lng, closeTo(139.0, 1e-6));
      expect(last.zoom, 11);
    });
  });
}
