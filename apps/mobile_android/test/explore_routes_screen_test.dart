import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show MapControlButton;

import '../lib/explore_viewport.dart' show ExploreSort;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/main.dart' show pendingArmRunWithRoute;
import '../lib/preferences.dart';
import '../lib/routes_views.dart';
import '../lib/screens/explore_routes_screen.dart';
import '../lib/widgets/explore_map_chrome.dart';
import 'pump_until.dart';
import 'supabase_test_init.dart';
import 'worst_case_layout.dart';

// Routes → Explore routes is map first (decisions § 2611): the map is the
// page, a tapped pin opens a card with the whole name, "List · N routes"
// opens the routes in view as a page of their own, and an empty view says so.

const _longName = 'Cherry Creek Trail out-and-back to Confluence Park and '
    'the long way home';

cm.DiscoverableRoutePin _pin(
  String id,
  String name, {
  double lat = 20,
  double lng = 0,
  bool official = false,
  double distanceM = 12500,
  String surface = 'trail',
  int runCount = 0,
}) =>
    cm.DiscoverableRoutePin(
      id: id,
      name: name,
      featured: false,
      distanceM: distanceM,
      elevationM: 80,
      surface: surface,
      runCount: runCount,
      lat: lat,
      lng: lng,
      official: official,
    );

const _line = [
  cm.Waypoint(lat: 20, lng: 0),
  cm.Waypoint(lat: 20.01, lng: 0.01),
];

class _Api extends ApiClient {
  _Api({this.pins = const [], this.signedIn = true});

  List<cm.DiscoverableRoutePin> pins;
  final bool signedIn;
  final bookmarkCalls = <String>[];

  @override
  String? get userId => signedIn ? 'u1' : null;

  @override
  Future<List<String>> fetchPopularRouteTags({int limit = 20}) async =>
      const [];

  @override
  Future<List<cm.Route>> fetchBookmarkedRoutes({int limit = 200}) async =>
      const [];

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
      pins;

  @override
  Future<({cm.Route? route, String? ownerId})> fetchRouteById(
          String routeId) async =>
      (
        route: cm.Route(
          id: routeId,
          name: pins.firstWhere((p) => p.id == routeId).name,
          waypoints: _line,
          distanceMetres: 12500,
        ),
        ownerId: 'someone-else',
      );

  @override
  Future<List<cm.Waypoint>> clipRouteForViewer(String routeId) async => _line;

  @override
  Future<void> bookmarkRoute(String routeId) async =>
      bookmarkCalls.add(routeId);
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Widget _screen(
  ApiClient api,
  Preferences prefs, {
  Future<Position> Function()? locateFn,
}) =>
    ExploreRoutesScreen(
      apiClient: api,
      routeStore: LocalRouteStore(),
      preferences: prefs,
      locateFn: locateFn,
      chrome: RoutesExploreChrome(
        menu: RoutesViewMenu(
          show: RoutesShow.routes,
          onSelected: (_) {},
          floating: true,
        ),
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  ApiClient api, {
  double textScale = 1.0,
  Future<Position> Function()? locateFn,
}) async {
  final prefs = await _prefs();
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: _screen(api, prefs, locateFn: locateFn),
  ));
}

/// Waits for the map's read of the routes in view to land: [count] routes
/// on the List pill, or the empty view when there are none.
Future<void> _settle(WidgetTester tester, int count) => pumpUntil(
      tester,
      () => count == 0
          ? find.byKey(const ValueKey('explore-empty-view')).evaluate().isNotEmpty
          : find
              .text(count == 1 ? 'List · 1 route' : 'List · $count routes')
              .evaluate()
              .isNotEmpty,
      describe: '$count routes in view to load',
    );

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
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // The map reads dotenv for its tile style; empty, it falls back to OSM.
    dotenv.loadFromString(isOptional: true);
    await initializeTestSupabase();
  });

  testWidgets('the map is the page: the view menu, Search and Filters on its '
      'top edge, compact Near me, and the List pill counting the routes in '
      'view', (tester) async {
    await _pump(tester, _Api(pins: [_pin('a', 'Alpha'), _pin('b', 'Bravo', lng: 60)]));
    await _settle(tester, 2);
    expect(find.text('Explore routes'), findsOneWidget);
    expect(find.byTooltip('Filters'), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-search')), findsOneWidget);
    expect(find.text('List · 2 routes'), findsOneWidget);
    expect(
        tester
            .widget<MapControlButton>(
                find.byKey(const ValueKey('explore-near-me')))
            .compact,
        isTrue);
    expect(find.byType(TextField), findsNothing,
        reason: 'no search row: the search is a button on the map');
  });

  testWidgets('a tapped pin opens a card with the whole name at 1.3x, the '
      'Official line off the title, and its actions', (tester) async {
    await _pump(tester, _Api(pins: [_pin('a', _longName, official: true)]),
        textScale: 1.3);
    await _settle(tester, 1);
    await tester.tap(find.byKey(const ValueKey('explore-pin-a')));
    await pumpUntil(tester,
        () => find.byKey(const ValueKey('explore-card-name')).evaluate().isNotEmpty,
        describe: 'the card');
    expect(tester.takeException(), isNull);
    final name = tester.renderObject<RenderParagraph>(find.descendant(
        of: find.byKey(const ValueKey('explore-card-name')),
        matching: find.byType(RichText)));
    expect(name.text.toPlainText(), _longName);
    expect(name.didExceedMaxLines, isFalse, reason: 'the name wraps, never cut');
    expect(find.textContaining('Official course', findRichText: true), findsOneWidget);
    expect(
        tester.getRect(find.textContaining('Official course', findRichText: true)).top,
        greaterThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('explore-card-name'))).bottom),
        reason: 'the Official line sits under the name, not beside it');
    expect(find.text('Run this route'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-list-pill')), findsNothing,
        reason: 'the card takes the pill\'s place');

    await tester.tap(find.byKey(const ValueKey('explore-card-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('explore-card-name')), findsNothing);
    expect(find.byKey(const ValueKey('explore-list-pill')), findsOneWidget);
  });

  testWidgets('Run this route loads the clipped line into the recorder '
      'without starting it, and Save bookmarks by reference', (tester) async {
    addTearDown(() => pendingArmRunWithRoute.value = null);
    final api = _Api(pins: [_pin('a', 'Alpha')]);
    await _pump(tester, api);
    await _settle(tester, 1);
    await tester.tap(find.byKey(const ValueKey('explore-pin-a')));
    await pumpUntil(tester,
        () => find.byKey(const ValueKey('explore-card-run')).evaluate().isNotEmpty,
        describe: 'the card');
    await tester.tap(find.byKey(const ValueKey('explore-card-run')));
    await pumpUntil(tester, () => pendingArmRunWithRoute.value != null,
        describe: 'the route armed');
    expect(pendingArmRunWithRoute.value!.id, 'a');
    expect(pendingArmRunWithRoute.value!.waypoints, _line);

    await tester.tap(find.byKey(const ValueKey('explore-card-save')));
    await pumpUntil(tester, () => api.bookmarkCalls.isNotEmpty,
        describe: 'the bookmark');
    expect(api.bookmarkCalls, ['a']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a tap on overlapping routes asks which route', (tester) async {
    await _pump(tester,
        _Api(pins: [_pin('a', 'Alpha'), _pin('b', 'Bravo', lat: 20.0001)]));
    await _settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('explore-cluster-a')));
    await pumpUntil(tester, () => find.text('Which route?').evaluate().isNotEmpty,
        describe: 'the picker');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('explore-picker-b')));
    await pumpUntil(tester,
        () => find.byKey(const ValueKey('explore-card-name')).evaluate().isNotEmpty,
        describe: 'the card');
    expect(tester.widget<Text>(find.byKey(const ValueKey('explore-card-name'))).data,
        'Bravo');
  });

  testWidgets('List · N opens the routes in view as a page; a card there '
      'returns to the map with that route open', (tester) async {
    await _pump(
        tester,
        _Api(pins: [
          _pin('a', 'Alpha', runCount: 1),
          _pin('b', 'Bravo', lng: 60, runCount: 9),
        ]));
    await _settle(tester, 2);
    await tester.tap(find.text('List · 2 routes'));
    await pumpUntil(tester,
        () => find.byKey(const ValueKey('explore-list-page')).evaluate().isNotEmpty,
        describe: 'the list page');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Routes on the map'), findsWidgets);
    // Most run first while the runner's place is unknown.
    final a = tester.getRect(find.byKey(const ValueKey('explore-list-card-a')));
    final b = tester.getRect(find.byKey(const ValueKey('explore-list-card-b')));
    expect(b.top, lessThan(a.top));
    expect(find.text(exploreSortLabelForTest(ExploreSort.mostRun)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('explore-list-card-a')));
    await pumpUntil(tester,
        () => find.byKey(const ValueKey('explore-card-name')).evaluate().isNotEmpty,
        describe: 'back on the map with the card open');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('explore-list-page')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('explore-card-name'))).data,
        'Alpha');
  });

  testWidgets('a filter narrows the pins and the count; an empty view says '
      'so with Zoom out and Clear filters', (tester) async {
    await _pump(
        tester,
        _Api(pins: [
          _pin('a', 'Alpha', surface: 'road'),
          _pin('b', 'Bravo', lng: 60, surface: 'trail'),
        ]));
    await _settle(tester, 2);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Road'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('List · 1 route'), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-pin-b')), findsNothing);

    await tester.tap(find.byTooltip('Filters, 1 on'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Mixed'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('No routes here'), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-zoom-out')), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets('an empty view says No routes here, with Zoom out', (tester) async {
    await _pump(tester, _Api());
    await _settle(tester, 0);
    expect(find.text('No routes here'), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-zoom-out')), findsOneWidget);
    expect(find.text('List · 0 routes'), findsOneWidget);
  });

  testWidgets('Near me moves the map and makes nearest first the list order',
      (tester) async {
    await _pump(
        tester,
        _Api(pins: [
          _pin('far', 'Far', lng: 60, runCount: 9),
          _pin('near', 'Near', runCount: 1),
        ]),
        locateFn: () async => _fix(20, 0));
    await _settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('explore-near-me')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('explore-list-pill')));
    await pumpUntil(tester,
        () => find.byKey(const ValueKey('explore-list-page')).evaluate().isNotEmpty,
        describe: 'the list page');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nearest first'), findsOneWidget);
  });

  testWidgets('signed out, the map stays and the card is the way to sign in',
      (tester) async {
    await _pump(tester, _Api(signedIn: false));
    await tester.pump();
    expect(find.byKey(const ValueKey('explore-routes-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-list-pill')), findsNothing);
    expect(find.textContaining('Sign in'), findsWidgets);
  });

  worstCaseTestWidgets('Explore routes with a card open', (tester, locale) async {
    final prefs = await _prefs();
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: _screen(_Api(pins: [_pin('a', _longName, official: true)]), prefs),
    ));
    final pin = find.byKey(const ValueKey('explore-pin-a'));
    await pumpUntil(tester, () => pin.evaluate().isNotEmpty,
        describe: 'the pin');
    expectNoOverflow(tester, 'Explore routes at rest');
    // On a 320 dp map at 2x the floating buttons may lie over the pin; the
    // pin's own tap is what is under test.
    tester.widget<GestureDetector>(pin).onTap!();
    await pumpUntil(tester,
        () => find.byKey(const ValueKey('explore-card-name')).evaluate().isNotEmpty,
        describe: 'the card');
    final name = tester.renderObject<RenderParagraph>(find.descendant(
        of: find.byKey(const ValueKey('explore-card-name')),
        matching: find.byType(RichText)));
    expect(name.didExceedMaxLines, isFalse);
  });

  group('ExploreListCard at a raised text size', () {
    test('the shape gives back the room the name grows into', () {
      expect(ExploreListCard.thumbnailSideFor(1), ExploreListCard.thumbnailSize);
      expect(ExploreListCard.thumbnailSideFor(0.85),
          ExploreListCard.thumbnailSize);
      expect(ExploreListCard.thumbnailSideFor(1.3),
          closeTo(ExploreListCard.thumbnailSize / 1.3, 0.001));
      expect(ExploreListCard.thumbnailSideFor(1.9),
          greaterThanOrEqualTo(ExploreListCard.minThumbnailSize));
      expect(ExploreListCard.thumbnailSideFor(2), isNull);
    });

    Future<void> pumpCard(WidgetTester tester, double scale) =>
        tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(320, 640),
                textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SizedBox(
                width: 288,
                child: ExploreListCard(
                  name: 'Pocahontas Lakeview Loop',
                  stats: '21.3 km · 189 m',
                  thumbnail: const SizedBox(key: ValueKey('shape')),
                  onTap: () {},
                  trailing: IconButton(
                    key: const ValueKey('star'),
                    icon: const Icon(Icons.star_border),
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ));

    testWidgets('at 1x the shape and the star sit beside the name',
        (tester) async {
      await pumpCard(tester, 1);
      expect(find.byKey(const ValueKey('shape')), findsOneWidget);
      final name = tester.getRect(find.text('Pocahontas Lakeview Loop'));
      final star = tester.getRect(find.byKey(const ValueKey('star')));
      expect(star.left, greaterThan(name.right));
    });

    testWidgets('at 2x the shape goes and the star moves under the name',
        (tester) async {
      await pumpCard(tester, 2);
      expect(find.byKey(const ValueKey('shape')), findsNothing);
      final name = tester.getRect(find.text('Pocahontas Lakeview Loop'));
      final star = tester.getRect(find.byKey(const ValueKey('star')));
      expect(star.top, greaterThanOrEqualTo(name.bottom));
    });
  });
}

/// The sort chip's English label, as the list page shows it.
String exploreSortLabelForTest(ExploreSort sort) =>
    exploreSortLabel(lookupAppLocalizations(const Locale('en')), sort);
