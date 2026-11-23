import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:ui_kit/ui_kit.dart'
    show
        AppSearchField,
        AppSpace,
        AppTheme,
        HubPrimaryActions,
        HubTabScope,
        PageHeading;
import '../lib/fab_clearance.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/routes_views.dart';
import '../lib/screens/explore_routes_screen.dart';
import 'supabase_test_init.dart';
import 'worst_case_layout.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // The map reads dotenv for its tile style; empty, it falls back to OSM.
  dotenv.loadFromString(isOptional: true);
  await initializeTestSupabase();
  _supabaseReady = true;
}

Future<({Preferences prefs, LocalRouteStore routeStore})> _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (prefs: prefs, routeStore: LocalRouteStore());
}

cm.Route _route(String id, String name) => cm.Route(
      id: id,
      name: name,
      waypoints: const [],
      distanceMetres: 5000,
    );

/// A signed-in viewer with one public route in the results. A held [gate]
/// keeps a bookmark request in flight; [failWith] makes it fail.
class _BookmarkApi extends ApiClient {
  _BookmarkApi({List<cm.Route> bookmarked = const []}) : _bookmarked = bookmarked;

  final List<cm.Route> _bookmarked;
  final bookmarkCalls = <String>[];
  final unbookmarkCalls = <String>[];
  Completer<void>? gate;
  Object? failWith;

  @override
  String? get userId => 'u1';

  @override
  Future<cm.KeysetPage<cm.Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    List<Object?>? after,
  }) async =>
      after == null
          ? cm.KeysetPage([_route('r1', 'Morning loop')], null)
          : const cm.KeysetPage(<cm.Route>[], null);

  @override
  Future<List<String>> fetchPopularRouteTags({int limit = 20}) async =>
      const [];

  @override
  Future<List<cm.Route>> fetchBookmarkedRoutes({int limit = 200}) async =>
      _bookmarked;

  @override
  Future<void> bookmarkRoute(String routeId) async {
    bookmarkCalls.add(routeId);
    await gate?.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> unbookmarkRoute(String routeId) async {
    unbookmarkCalls.add(routeId);
    await gate?.future;
    if (failWith != null) throw failWith!;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  required LocalRouteStore routeStore,
  ApiClient? api,
  Future<Position> Function()? locateFn,
  RoutesExploreChrome? chrome,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ExploreRoutesScreen(
        apiClient: api,
        routeStore: routeStore,
        preferences: prefs,
        locateFn: locateFn,
        chrome: chrome,
      ),
    ),
  );
}

class _NearbyApi extends _BookmarkApi {
  final nearbyCalls = <(double, double)>[];

  @override
  Future<List<cm.Route>> nearbyPublicRoutes({
    required double lat,
    required double lng,
    double radiusM = 50000,
    int limit = 50,
  }) async {
    nearbyCalls.add((lat, lng));
    return [_route('n1', 'Riverside 10K')];
  }
}

Position _fix(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 1, 1),
      accuracy: 50,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  setUpAll(_ensureSupabase);
  _mapFirstTests();
  _layoutTests();

  group('ExploreRoutesScreen — initial render', () {
    testWidgets('renders the Explore Routes app-bar title', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      expect(find.widgetWithText(PageHeading, 'Explore Routes'), findsOneWidget);
    });

    testWidgets('Featured is in the Filters sheet and shows as a removable '
        'chip once on', (tester) async {
      // Reason: Featured is the entry point into curated routes —
      // its absence would mean users can't surface non-personal
      // content from the Explore tab. It moved into the Filters sheet with
      // the bar's other filters (issue #1374), so on, it shows on the line.
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-bar-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Featured'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Featured'), findsOneWidget);
      expect(find.byTooltip('Remove filter: Featured'), findsOneWidget);
    });

    testWidgets('one search field, with clear, and Near me as the quick chip',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      expect(find.byType(AppSearchField), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Near Me'), findsOneWidget);
    });

    // Under the Routes tab (issue #1374, decisions § 2490) the tab hands this
    // body its Mine · Explore row and its Routes · Segments chips; both must
    // sit above the results, the chips leading the body's own.
    testWidgets('a chrome puts the view row and its chips above the list',
        (tester) async {
      final s = await _makeStores();
      await _pump(
        tester,
        prefs: s.prefs,
        routeStore: s.routeStore,
        api: _BookmarkApi(),
        chrome: RoutesExploreChrome(
          viewBar: const SizedBox(key: Key('test-view-bar'), height: 40),
          chips: [
            FilterChip(
              key: const Key('test-chip-routes'),
              label: const Text('Routes'),
              selected: true,
              onSelected: (_) {},
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      final viewBar = find.byKey(const Key('test-view-bar'));
      final chip = find.byKey(const Key('test-chip-routes'));
      final nearMe = find.widgetWithText(FilterChip, 'Near Me');
      final row = find.text('Morning loop');
      expect(viewBar, findsOneWidget);
      expect(chip, findsOneWidget);
      expect(row, findsOneWidget);
      expect(tester.getTopLeft(viewBar).dy,
          lessThan(tester.getTopLeft(chip).dy));
      expect(tester.getTopLeft(chip).dy, lessThan(tester.getTopLeft(row).dy));
      expect(tester.getTopLeft(chip).dx, lessThan(tester.getTopLeft(nearMe).dx),
          reason: 'the view chips lead the body\'s own');
    });
  });

  // Saving a public route is a `saved_routes` reference that a second tap
  // removes (decisions § 30). The row used to clone the route into the local
  // store and never rebuild, so the bookmark stayed unfilled after a save.
  group('ExploreRoutesScreen — the bookmark toggle', () {
    Finder filled() => find.byIcon(Icons.bookmark);
    Finder empty() => find.byIcon(Icons.bookmark_border);

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a tap fills the bookmark at once and saves by reference',
        (tester) async {
      final s = await _makeStores();
      final api = _BookmarkApi()..gate = Completer<void>();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore, api: api);
      await settle(tester);
      expect(empty(), findsOneWidget);

      await tester.tap(empty());
      await tester.pump();
      expect(filled(), findsOneWidget,
          reason: 'the tap must visibly land before the request returns');
      expect(api.bookmarkCalls, ['r1']);

      await tester.tap(filled());
      await tester.pump();
      expect(api.bookmarkCalls, ['r1'],
          reason: 'a tap during the request must not fire a second one');
      expect(api.unbookmarkCalls, isEmpty);

      api.gate!.complete();
      await settle(tester);
      expect(filled(), findsOneWidget);
      expect(find.text('Saved "Morning loop" to your library'), findsOneWidget);
      expect(s.routeStore.routes, isEmpty,
          reason: 'a bookmark is a reference, not a private copy');
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('a bookmarked route shows filled, and a tap removes it',
        (tester) async {
      final s = await _makeStores();
      final api = _BookmarkApi(bookmarked: [_route('r1', 'Morning loop')]);
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore, api: api);
      await settle(tester);
      expect(filled(), findsOneWidget);
      expect(find.byTooltip('Remove from your library'), findsOneWidget);

      await tester.tap(filled());
      await settle(tester);
      expect(api.unbookmarkCalls, ['r1']);
      expect(empty(), findsOneWidget);
      expect(find.text('Removed "Morning loop" from your library'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('a failed save puts the bookmark back and says so',
        (tester) async {
      final s = await _makeStores();
      final api = _BookmarkApi()..failWith = Exception('offline');
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore, api: api);
      await settle(tester);

      await tester.tap(empty());
      await settle(tester);
      expect(empty(), findsOneWidget,
          reason: 'the icon must not claim a save that did not happen');
      expect(find.textContaining('Bookmark failed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('a library route that only shares the name is not this one',
        (tester) async {
      final s = await _makeStores();
      // ignore: invalid_use_of_visible_for_testing_member
      s.routeStore.debugSeed([_route('mine-1', 'Morning loop')]);
      final api = _BookmarkApi();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore, api: api);
      await settle(tester);

      expect(empty(), findsOneWidget,
          reason: 'saved-ness is by id; a name match marked unrelated routes '
              'saved and disabled their button');
      await tester.tap(empty());
      await settle(tester);
      expect(api.bookmarkCalls, ['r1']);
      await tester.pump(const Duration(seconds: 8));
    });
  });

  group('ExploreRoutesScreen — Near me', () {
    testWidgets('searches around the browse fix', (tester) async {
      final s = await _makeStores();
      final api = _NearbyApi();
      await _pump(tester,
          prefs: s.prefs,
          routeStore: s.routeStore,
          api: api,
          locateFn: () async => _fix(37.54, -77.43));
      await tester.pump();
      await tester.tap(find.text('Near Me'));
      await tester.pump();
      await tester.pump();
      expect(api.nearbyCalls, [(37.54, -77.43)]);
      expect(find.text('Riverside 10K'), findsOneWidget);
    });

    testWidgets('a refused permission says why instead of a generic failure',
        (tester) async {
      final s = await _makeStores();
      final api = _NearbyApi();
      await _pump(tester,
          prefs: s.prefs,
          routeStore: s.routeStore,
          api: api,
          locateFn: () async =>
              throw const PermissionDeniedException('denied'));
      await tester.pump();
      await tester.tap(find.text('Near Me'));
      await tester.pump();
      await tester.pump();
      expect(api.nearbyCalls, isEmpty);
      expect(
          find.text('Location permission required to find nearby routes'),
          findsOneWidget);
    });

    testWidgets('location switched off says so, not a generic failure',
        (tester) async {
      final s = await _makeStores();
      final api = _NearbyApi();
      await _pump(tester,
          prefs: s.prefs,
          routeStore: s.routeStore,
          api: api,
          locateFn: () async =>
              throw const LocationServiceDisabledException());
      await tester.pump();
      await tester.tap(find.text('Near Me'));
      await tester.pump();
      await tester.pump();
      expect(api.nearbyCalls, isEmpty);
      expect(
          find.text(
              'Location unavailable: location is turned off on this device'),
          findsOneWidget);
    });

    testWidgets('a fix that never arrives is not called a network timeout',
        (tester) async {
      final s = await _makeStores();
      final api = _NearbyApi();
      await _pump(tester,
          prefs: s.prefs,
          routeStore: s.routeStore,
          api: api,
          locateFn: () async => throw TimeoutException('no fix'));
      await tester.pump();
      await tester.tap(find.text('Near Me'));
      await tester.pump();
      await tester.pump();
      expect(api.nearbyCalls, isEmpty);
      expect(
          find.text(
              'Location unavailable: no position yet, try again in a moment'),
          findsOneWidget);
      expect(find.textContaining('Connection timed out'), findsNothing);
    });
  });

  testWidgets('a result card reads elevation in the reader\'s unit',
      (tester) async {
    SharedPreferences.setMockInitialValues({'use_miles': true});
    final prefs = Preferences();
    await prefs.init();
    await _pump(tester,
        prefs: prefs, routeStore: LocalRouteStore(), api: _ClimbApi());
    await tester.pump();
    await tester.pump();
    expect(find.text('Hill loop'), findsOneWidget);
    expect(find.textContaining(RegExp(r'751\sft')), findsOneWidget);
    expect(find.textContaining('229'), findsNothing);
  });
}

class _ClimbApi extends _BookmarkApi {
  @override
  Future<cm.KeysetPage<cm.Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    List<Object?>? after,
  }) async =>
      after == null
          ? cm.KeysetPage([
              cm.Route(
                id: 'h1',
                name: 'Hill loop',
                waypoints: const [],
                distanceMetres: 5000,
                elevationGainMetres: 229,
              ),
            ], null)
          : const cm.KeysetPage(<cm.Route>[], null);
}

/// Many public routes, and one discoverable pin in any viewport.
class _MapApi extends _BookmarkApi {
  @override
  Future<cm.KeysetPage<cm.Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    List<Object?>? after,
  }) async =>
      after == null
          ? cm.KeysetPage([
              for (var i = 0; i < 12; i++) _route('r$i', 'Public loop $i'),
            ], null)
          : const cm.KeysetPage(<cm.Route>[], null);

  @override
  Future<List<cm.DiscoverableRoutePin>> fetchDiscoverableRoutesInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
    String filter = 'popular',
    List<double>? distMin,
    List<double?>? distMax,
  }) async =>
      [
        const cm.DiscoverableRoutePin(
          id: 'p1',
          name: 'Pinned loop',
          featured: false,
          distanceM: 5000,
          surface: 'road',
          runCount: 3,
          lat: 10,
          lng: 10,
        ),
      ];
}

Future<void> _setView(WidgetTester tester, Size size, FakeViewPadding bar,
    {double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = bar;
  tester.view.viewPadding = bar;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void _mapFirstTests() {
  // Explore → Routes is a MapFirstPage: the public routes in view on a
  // full-bleed map, the search results in its sheet (issue #1374).
  group('ExploreRoutesScreen — map-first', () {
    testWidgets('the map carries the pins in view; the list is the sheet',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester,
          prefs: s.prefs, routeStore: s.routeStore, api: _MapApi());
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('explore-routes-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('explore-pin-p1')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('map-first-sheet')),
              matching: find.text('Public loop 0')),
          findsOneWidget);
    });

    testWidgets('320 dp, 2x text, 3-button bar: the last result scrolls clear '
        'of the bar', (tester) async {
      await _setView(tester, const Size(320, 640),
          const FakeViewPadding(bottom: 48),
          textScale: 2);
      final s = await _makeStores();
      await _pump(tester,
          prefs: s.prefs, routeStore: s.routeStore, api: _MapApi());
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final last = find.text('Public loop 11');
      await tester.dragUntilVisible(last,
          find.byType(CustomScrollView).last, const Offset(0, -200));
      await tester.drag(
          find.byType(CustomScrollView).last, const Offset(0, -2000));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(640 - 48));
    });

    testWidgets('landscape: the results clear a side nav bar',
        (tester) async {
      await _setView(tester, const Size(780, 360),
          const FakeViewPadding(right: 48));
      final s = await _makeStores();
      await _pump(tester,
          prefs: s.prefs, routeStore: s.routeStore, api: _MapApi());
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final card = find.ancestor(
          of: find.text('Public loop 0'), matching: find.byType(Card));
      expect(tester.getRect(card).right, lessThanOrEqualTo(780 - 48));
    });

    // Explore sits in the Fitness hub's swiping pages. A drag that starts on
    // the map pans the map; one that starts on the list switches the page.
    testWidgets('inside a swiping hub the map keeps its drags and the sheet '
        'swipes', (tester) async {
      final s = await _makeStores();
      final tabs = TabController(length: 2, vsync: const TestVSync());
      addTearDown(tabs.dispose);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TabBarView(
            controller: tabs,
            children: [
              ExploreRoutesScreen(
                apiClient: _MapApi(),
                routeStore: s.routeStore,
                preferences: s.prefs,
              ),
              const Center(child: Text('next tab')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final before = map.mapController!.camera.center;
      final mapBox = tester.getRect(find.byType(FlutterMap));
      // Above the sheet, which covers the lower half.
      await tester.flingFrom(Offset(mapBox.center.dx, mapBox.top + 40),
          const Offset(-400, 0), 1500);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(tabs.index, 0, reason: 'a drag on the map switched the page');
      expect(map.mapController!.camera.center, isNot(before),
          reason: 'the map did not pan');

      await tester.fling(
          find.text('Public loop 0'), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(tabs.index, 1, reason: 'a drag on the list did not swipe');
    });
  });
}

/// A dozen public routes with long names, and nothing on the map.
class _LayoutApi extends _BookmarkApi {
  @override
  Future<cm.KeysetPage<cm.Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    List<Object?>? after,
  }) async =>
      after == null
          ? cm.KeysetPage([
              for (var i = 0; i < 12; i++)
                cm.Route(
                  id: 'L$i',
                  name: 'Pocahontas Lakeview $i',
                  waypoints: const [],
                  distanceMetres: 8050,
                  elevationGainMetres: 189,
                  surface: 'trail',
                  runCount: 14,
                ),
            ], null)
          : const cm.KeysetPage(<cm.Route>[], null);

  @override
  Future<List<cm.DiscoverableRoutePin>> fetchDiscoverableRoutesInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
    String filter = 'popular',
    List<double>? distMin,
    List<double?>? distMax,
  }) async =>
      const [];
}

/// Explore as the Routes tab hosts it inside the phone shell: the hub's
/// scope, the docked centre button over a bottom bar and the inset the shell
/// publishes for it, a view row above the controls and the heatmaps.
Widget _hostedExplore({
  required Preferences prefs,
  required LocalRouteStore routeStore,
  required HubPrimaryActions actions,
  required AppLocalizations l10n,
  Locale? locale,
  double textScale = 1,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DockedFabInset(
          height: kDockedFabOverhang,
          child: HubTabScope(
            tab: 'routes',
            actions: actions,
            child: ExploreRoutesScreen(
              apiClient: _LayoutApi(),
              routeStore: routeStore,
              preferences: prefs,
              chrome: RoutesExploreChrome(
                viewBar: const SizedBox(height: 56),
                chips: [
                  FilterChip(
                    label: Text(l10n.fitnessRunsRoutes),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: Text(l10n.runSurfaceTabSegments),
                    selected: false,
                    onSelected: (_) {},
                  ),
                ],
              ),
              maps: Wrap(
                key: const Key('test-maps'),
                spacing: AppSpace.sm,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.local_fire_department),
                    label: Text(l10n.routesHeatmapTooltip),
                    onPressed: () {},
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_pin_circle_outlined),
                    label: Text(l10n.runHeatmapTooltip),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          key: const ValueKey('centre-button'),
          onPressed: () {},
          child: const Icon(Icons.play_arrow),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: NavigationBar(
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.route), label: 'Training'),
            NavigationDestination(icon: SizedBox.shrink(), label: 'Run'),
            NavigationDestination(icon: Icon(Icons.public), label: 'Social'),
            NavigationDestination(icon: Icon(Icons.person), label: 'You'),
          ],
        ),
      ),
    );

Rect _sheetRect(WidgetTester tester) => tester.getRect(find
    .descendant(
        of: find.byKey(const ValueKey('map-first-sheet')),
        matching: find.byType(Material))
    .first);

void _layoutTests() {
  // Owner report from a phone (Routes → Explore, "way too compact"): the
  // heatmap tiles headed the sheet, the card's thumbnail slot cut the name,
  // and one route showed, its facts under the docked centre button
  // (decisions § 2609).
  group('ExploreRoutesScreen — routes first', () {
    testWidgets('on a phone the sheet opens on several whole routes, the '
        'heatmaps float on the map, and a name keeps the card\'s width',
        (tester) async {
      await _setView(tester, const Size(412, 915),
          const FakeViewPadding(top: 24, bottom: 24));
      final s = await _makeStores();
      final actions = HubPrimaryActions();
      addTearDown(actions.dispose);
      await tester.pumpWidget(_hostedExplore(
        prefs: s.prefs,
        routeStore: s.routeStore,
        actions: actions,
        l10n: lookupAppLocalizations(const Locale('en')),
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      final sheet = _sheetRect(tester);
      final centre = tester.getRect(find.byKey(const ValueKey('centre-button')));
      final whole = [
        for (final card in find.byType(Card).evaluate())
          tester.getRect(find.byWidget(card.widget)),
      ].where((r) => r.top >= sheet.top && r.bottom <= centre.top);
      expect(whole.length, greaterThanOrEqualTo(2),
          reason: 'at rest the sheet shows at least two whole routes above '
              'the docked centre button');

      final maps = find.byKey(const Key('test-maps'));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('map-first-sheet')),
              matching: maps),
          findsNothing,
          reason: 'the heatmaps are not the head of the list');
      expect(tester.getRect(maps).bottom, lessThanOrEqualTo(sheet.top));

      final title = find.text('Pocahontas Lakeview 0');
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.didExceedMaxLines, isFalse,
          reason: 'the route\'s name is cut');
      final card = find.ancestor(of: title, matching: find.byType(Card));
      expect(tester.getRect(title).left - tester.getRect(card).left,
          AppSpace.md,
          reason: 'no thumbnail slot ahead of the name');
      expect(find.textContaining(RegExp(r'14\sruns')), findsWidgets,
          reason: 'the run count is said in words, not a bare number');
    });
  });

  // PR #1467 review: the Official badge, wrapped onto the line under the
  // name, started about 8 dp in from the name and the facts line.
  testWidgets('an Official badge on its own line sits flush with the name',
      (tester) async {
    await _setView(tester, const Size(360, 780), FakeViewPadding.zero);
    final s = await _makeStores();
    // In the test font this name fills its line and the badge wraps.
    const name = 'Loop MMMMMMMMMM';
    await _pump(tester,
        prefs: s.prefs, routeStore: s.routeStore, api: _OfficialApi(name));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final title = tester.getRect(find.text(name));
    final badge =
        tester.getRect(find.byKey(const Key('provenance-badge-official')));
    expect(badge.top, greaterThan(title.top + 16),
        reason: 'the case under test: the badge starts the second line');
    expect(badge.left, moreOrLessEquals(title.left, epsilon: 0.5));
  });

  worstCaseTestWidgets('Routes → Explore scrolled to its last route',
      (tester, locale) async {
    final s = await _makeStores();
    final actions = HubPrimaryActions();
    addTearDown(actions.dispose);
    await tester.pumpWidget(_hostedExplore(
      prefs: s.prefs,
      routeStore: s.routeStore,
      actions: actions,
      l10n: l10nFor(locale),
      locale: locale,
      textScale: kWorstCaseTextScale,
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expectNoOverflow(tester, 'Explore at rest');

    final list = find.byType(CustomScrollView).last;
    final last = find.text('Pocahontas Lakeview 11');
    await tester.dragUntilVisible(last, list, const Offset(0, -200));
    await tester.drag(list, const Offset(0, -3000));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expectNoOverflow(tester, 'Explore at its end');

    final card = find.ancestor(of: last, matching: find.byType(Card));
    final bookmark = find.descendant(
        of: card,
        matching: find.byWidgetPredicate((w) => w is IconButton));
    for (final target in [card, bookmark]) {
      final rect = tester.getRect(target);
      for (final fab in find.byType(FloatingActionButton).evaluate()) {
        final fabRect = tester.getRect(find.byWidget(fab.widget));
        expect(fabRect.overlaps(rect), isFalse,
            reason: 'the last route at $rect sits under a floating button '
                'at $fabRect');
      }
    }
    final hit = tester.hitTestOnBinding(tester.getCenter(bookmark));
    expect(hit.path.any((e) => e.target == tester.renderObject(bookmark)),
        isTrue,
        reason: 'a tap on the last route\'s bookmark lands on something '
            'drawn over it');
  });
}

/// One official route named [name]; it is not a park course's.
class _OfficialApi extends _BookmarkApi {
  _OfficialApi(this.name);

  final String name;

  @override
  Future<cm.KeysetPage<cm.Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    List<Object?>? after,
  }) async =>
      after == null
          ? cm.KeysetPage([
              cm.Route(
                id: 'o1',
                name: name,
                waypoints: const [],
                distanceMetres: 42195,
                official: true,
              ),
            ], null)
          : const cm.KeysetPage(<cm.Route>[], null);

  @override
  Future<Set<String>> fetchParkCourseRouteIds(Iterable<String> ids) async =>
      {};
}
