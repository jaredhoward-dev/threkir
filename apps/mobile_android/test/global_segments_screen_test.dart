import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import 'package:ui_kit/ui_kit.dart' show EmptyState, PageHeading;

import '../lib/fitness_surface_requests.dart';
import '../lib/screens/global_segments_screen.dart';
import '../lib/screens/park_courses_screen.dart';
import '../lib/screens/parks_screen.dart';
import '../lib/screens/races_screen.dart';
import '../lib/routes_views.dart';
import 'pump_until.dart';
import 'supabase_test_init.dart';
import 'worst_case_layout.dart';

GlobalSegmentRow _segment({
  required String id,
  required String name,
  String surface = 'road',
  String? region,
  double distanceM = 1200,
  double? elevationM = 12,
  String? description,
  List<Map<String, dynamic>> waypoints = const [],
}) =>
    GlobalSegmentRow(
      id: id,
      name: name,
      description: description,
      waypoints: waypoints,
      distanceM: distanceM,
      elevationM: elevationM,
      surface: surface,
      region: region,
      isActive: true,
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    );

final _catalogue = [
  _segment(
    id: 'a',
    name: 'Champs-Élysées Sprint',
    region: 'Paris, FR',
    distanceM: 2135,
    elevationM: 0,
    waypoints: const [
      {'lat': 48.8698, 'lng': 2.3075},
      {'lat': 48.8738, 'lng': 2.2950},
    ],
  ),
  _segment(
    id: 'b',
    name: 'Harlem Hill',
    region: 'New York, US',
    surface: 'trail',
    distanceM: 857,
    elevationM: 18,
    waypoints: const [
      {'lat': 40.7967, 'lng': -73.9530},
      {'lat': 40.7990, 'lng': -73.9555},
    ],
  ),
];

class _CatalogueApi extends ApiClient {
  _CatalogueApi(
    this.segments, {
    this.viewer = 'viewer-1',
    this.credit,
    this.parkCourse = false,
  });

  final List<GlobalSegmentRow> segments;
  final String? viewer;

  /// The park course credit (`park_courses.attribution`) every segment
  /// reads as; null for a segment no park course is built on.
  final String? credit;

  /// The park course every segment is built on, carrying [credit]; null for
  /// none.
  final bool parkCourse;

  @override
  Future<({ParkListing park, ParkCourseListing course})?>
      fetchParkCourseForSegment(String segmentId) async {
    if (!parkCourse && credit == null) return null;
    final segment = segments.firstWhere((s) => s.id == segmentId);
    final created = DateTime.parse('2026-01-01T00:00:00Z');
    return (
      park: ParkListing(
        park: ParkRow(
          id: 'p1',
          slug: 'beaver-lake',
          name: 'Beaver Lake Park',
          kind: 'park',
          agency: 'state',
          regionCode: 'US-VA',
          countryCode: 'US',
          timezone: 'America/New_York',
          isActive: true,
          createdAt: created,
        ),
        season: 2026,
        month: 11,
      ),
      course: ParkCourseListing(
        course: ParkCourseRow(
          id: 'c1',
          parkId: 'p1',
          globalSegmentId: segmentId,
          slug: 'loop',
          courseShape: 'loop',
          status: 'open',
          geometrySource: 'osm',
          checkpoints: const [],
          attribution: credit,
          createdAt: created,
        ),
        segment: segment,
      ),
    );
  }

  @override
  String? get userId => viewer;

  @override
  Future<List<GlobalSegmentRow>> fetchGlobalSegments({
    int limit = kGlobalSegmentCatalogueLimit,
  }) async =>
      segments;

  @override
  Future<GlobalSegmentRow?> fetchGlobalSegment(String id) async =>
      segments.where((s) => s.id == id).firstOrNull;

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int? season,
    int? month,
    int limit = 50,
  }) async =>
      const [];
}

class _NoParksApi extends _CatalogueApi {
  _NoParksApi() : super(const []);

  @override
  Future<List<ParkListing>> fetchParks() async => const [];
}

class _ThrowingCatalogueApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';

  @override
  Future<List<GlobalSegmentRow>> fetchGlobalSegments({
    int limit = kGlobalSegmentCatalogueLimit,
  }) async =>
      throw StateError('catalogue network down');
}

class _BoardApi extends _CatalogueApi {
  _BoardApi(super.segments, this.board);

  final List<GlobalSegmentLeaderboardEntry> board;

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int? season,
    int? month,
    int limit = 50,
  }) async =>
      board;
}

class _ZoneNoteApi extends _CatalogueApi {
  _ZoneNoteApi(super.segments, {required this.hasZone});

  final bool hasZone;
  int asked = 0;

  @override
  Future<bool> globalSegmentHasZoneEfforts(String segmentId) async {
    asked++;
    return hasZone;
  }
}

GlobalSegmentRow _gatedSegment(String id) => GlobalSegmentRow(
      id: id,
      name: 'Harlem Hill',
      waypoints: const [],
      distanceM: 857,
      surface: 'road',
      isActive: true,
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      startGateLat: 40.79,
      startGateLng: -73.95,
      startGateBearingDeg: 0,
      startGateHalfWidthM: 15,
      startGateSource: 'derived',
      endGateLat: 40.8,
      endGateLng: -73.95,
      endGateBearingDeg: 0,
      endGateHalfWidthM: 15,
      endGateSource: 'derived',
    );

const _oldMatchNote = 'Some older efforts were measured the old way, by '
    'passing near the start and finish rather than crossing the lines. Each is '
    're-measured the next time its runner opens the run.';

class _ThrowingBoardApi extends _CatalogueApi {
  _ThrowingBoardApi(super.segments);

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int? season,
    int? month,
    int limit = 50,
  }) async =>
      throw StateError('leaderboard network down');
}

GlobalSegmentLeaderboardEntry _entry(String userId, String name, int rank) =>
    GlobalSegmentLeaderboardEntry(
      effort: GlobalSegmentEffortRow(
        id: 'e-$userId',
        globalSegmentId: 'a',
        runId: 'r-$userId',
        userId: userId,
        timeSeconds: 300.0 + rank,
        startedAt: DateTime.parse('2026-02-01T00:00:00Z'),
        createdAt: DateTime.parse('2026-02-01T00:00:00Z'),
        matchedBy: 'zone',
      ),
      athlete: PublicProfile(id: userId, displayName: name),
      rank: rank,
    );

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

bool _supabaseReady = false;

Future<void> _ensureEnvironment() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  dotenv.loadFromString(envString: '', isOptional: true);
  dotenv.env.clear();
  await initializeTestSupabase();
  _supabaseReady = true;
}

void main() {
  setUpAll(_ensureEnvironment);

  // Explore segments is map first (decisions § 2611): every segment on the
  // map with its start pin, a tapped one as a card, the segments in view as
  // a list page of their own.
  group('GlobalSegmentsScreen — browse', () {
    Future<void> settle(WidgetTester tester) => pumpUntil(
          tester,
          () => find.byKey(const ValueKey('explore-segment-pin-a')).evaluate().isNotEmpty,
          describe: 'the catalogue on the map',
        );

    Future<void> openList(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('explore-list-pill')));
      await pumpUntil(tester,
          () => find.byKey(const ValueKey('explore-list-page')).evaluate().isNotEmpty,
          describe: 'the list page');
      await tester.pump(const Duration(milliseconds: 500));
    }

    worstCaseTestWidgets('a segment card on the map', (tester, locale) async {
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: GlobalSegmentsScreen(api: _CatalogueApi(_catalogue)),
      ));
      await settle(tester);
      expectNoOverflow(tester, 'Explore segments at rest');
      tester
          .widget<GestureDetector>(
              find.byKey(const ValueKey('explore-segment-pin-a')))
          .onTap!();
      await tester.pump();
      expect(find.byKey(const ValueKey('explore-card-name')), findsOneWidget);
    });

    worstCaseTestWidgets('the list of segments in view', (tester, locale) async {
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: GlobalSegmentsScreen(api: _CatalogueApi(_catalogue)),
      ));
      await settle(tester);
      await openList(tester);
      expect(find.byKey(const ValueKey('segment-list-card-a')), findsOneWidget);
    });

    testWidgets('the map draws every segment; List counts them and its page '
        'shows one card per segment with its region', (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await settle(tester);
      expect(find.byKey(const ValueKey('explore-segment-pin-b')), findsOneWidget);
      expect(find.text('List · 2 segments'), findsOneWidget);
      await openList(tester);
      expect(find.text('Segments on the map'), findsWidgets);
      expect(find.text('Champs-Élysées Sprint'), findsOneWidget);
      expect(find.text('Paris, FR'), findsOneWidget);
      expect(find.text('Harlem Hill'), findsOneWidget);
    });

    testWidgets('the list search folds accents and says when nothing matches',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await settle(tester);
      await openList(tester);
      await tester.enterText(find.byType(TextField), 'elysees');
      await tester.pump();
      expect(find.text('Champs-Élysées Sprint'), findsOneWidget);
      expect(find.text('Harlem Hill'), findsNothing);
      await tester.enterText(find.byType(TextField), 'nowhere at all');
      await tester.pump();
      expect(find.text('No segments here'), findsOneWidget);
    });

    testWidgets('a tapped pin opens a card; Details opens the segment',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('explore-segment-pin-b')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('explore-card-name'))).data,
          'Harlem Hill');
      expect(find.text('New York, US'), findsOneWidget);
      expect(find.byKey(const ValueKey('explore-list-pill')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('explore-card-details')));
      await pumpUntil(tester,
          () => find.text('Elevation gain').evaluate().isNotEmpty,
          describe: 'the segment page');
      expect(find.byType(GlobalSegmentDetailScreen), findsOneWidget);
    });

    testWidgets('a list card returns to the map with that segment open',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await settle(tester);
      await openList(tester);
      await tester.tap(find.byKey(const ValueKey('segment-list-card-a')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('explore-list-page')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('explore-card-name'))).data,
          'Champs-Élysées Sprint');
    });

    testWidgets('the surface filter narrows the map and the count',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await settle(tester);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Trail'));
      await tester.pump();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Trail')).selected,
          isTrue);
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('explore-segment-pin-a')), findsNothing);
      expect(find.byKey(const ValueKey('explore-segment-pin-b')), findsOneWidget);
    });

    testWidgets('a failed catalogue load offers a retry over the map',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _ThrowingCatalogueApi())));
      await pumpUntil(tester, () => find.text('Retry').evaluate().isNotEmpty,
          describe: 'the retry');
      expect(find.byKey(const ValueKey('explore-segments-map')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('a chrome puts the view menu on the map', (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(
        api: _CatalogueApi(_catalogue),
        chrome: const RoutesExploreChrome(menu: Text('Explore segments')),
      )));
      await settle(tester);
      expect(find.text('Explore segments'), findsOneWidget);
    });

    testWidgets('the empty catalogue points to the Courses view of Races & '
        'courses', (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _NoParksApi())));
      await pumpUntil(tester, () => find.byType(EmptyState).evaluate().isNotEmpty,
          describe: 'the empty state');
      await tester.tap(find.descendant(
          of: find.byType(EmptyState), matching: find.text('Park courses')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ParksScreen), findsNothing);
      expect(tester.widget<RacesScreen>(find.byType(RacesScreen)).initialShow,
          RacesShow.courses);
    });

    testWidgets('with a shell listening, Park courses asks it for Races & '
        'courses on Courses and pushes nothing', (tester) async {
      final drained = <FitnessSurfaceRequest?>[];
      void shell() => drained.add(fitnessSurfaceRequests.take());
      fitnessSurfaceRequests.addListener(shell);
      addTearDown(() => fitnessSurfaceRequests.removeListener(shell));
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _NoParksApi())));
      await tester.pump();
      await tester.tap(find.byKey(const Key('segments-parks-link')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(drained, [
        (tab: FitnessTab.races, racesShow: RacesShow.courses, routesShow: null),
      ]);
      expect(find.byType(RacesScreen), findsNothing);
    });

    testWidgets('a signed-out viewer still browses the world-readable catalogue',
        (tester) async {
      await tester.pumpWidget(
        _host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue, viewer: null))),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('explore-segment-pin-b')), findsOneWidget);
    });
  });

  group('GlobalSegmentDetailScreen', () {
    testWidgets('renders the segment stats and description', (tester) async {
      final api = _CatalogueApi([
        _segment(
          id: 'a',
          name: 'Harlem Hill',
          region: 'New York, US',
          distanceM: 857,
          elevationM: 18,
          description: 'The classic north-end climb.',
        ),
      ]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(PageHeading, 'Harlem Hill'), findsOneWidget);
      expect(find.text('The classic north-end climb.'), findsOneWidget);
      expect(find.byKey(const Key('help-how-this-works')), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Elevation gain'), findsOneWidget);
      expect(find.text('Road'), findsOneWidget);
    });

    testWidgets(
        'a park course segment shows its credit once, beside a description '
        'that no longer carries it', (tester) async {
      final api = _CatalogueApi(
        [_segment(id: 'a', name: 'Beaver Lake Trail', description: 'Run it clockwise.')],
        credit: '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP',
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Run it clockwise.'), findsOneWidget);
      expect(
        find.text('© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('segment-course-credit')), findsOneWidget);
    });

    testWidgets('a park course segment links to its course page',
        (tester) async {
      final api = _CatalogueApi(
        [_segment(id: 'a', name: 'Beaver Lake Trail')],
        parkCourse: true,
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      final link = find.byKey(const Key('segment-park-course-link'));
      expect(
          find.descendant(
              of: link, matching: find.text('Park course at Beaver Lake Park')),
          findsOneWidget);
      expect(find.byKey(const Key('segment-course-credit')), findsNothing);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ParkCourseScreen), findsOneWidget);
    });

    testWidgets('a segment no park course is built on shows no credit',
        (tester) async {
      final api = _CatalogueApi([_segment(id: 'a', name: 'Harlem Hill')]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('segment-course-credit')), findsNothing);
      expect(find.byKey(const Key('segment-park-course-link')), findsNothing);
    });

    testWidgets('a segment with geometry lays its preview out in a bounded box',
        (tester) async {
      final api = _CatalogueApi([
        _segment(
          id: 'a',
          name: 'Harlem Hill',
          waypoints: const [
            {'lat': 40.7963, 'lng': -73.9582},
            {'lat': 40.7988, 'lng': -73.9575},
          ],
        ),
      ]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AspectRatio), findsOneWidget);
    });

    testWidgets('an unknown or retired segment renders the not-found state',
        (tester) async {
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: _CatalogueApi(const []), segmentId: 'gone')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
            of: find.byType(EmptyState),
            matching: find.text('Segment not found')),
        findsOneWidget,
      );
      expect(find.text('Leaderboard'), findsNothing);
    });

    testWidgets('the leaderboard marks the crown holder and the viewer',
        (tester) async {
      final api = _BoardApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        [_entry('other-1', 'Rival', 1), _entry('viewer-1', 'Me', 2)],
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rival'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('the viewer holding rank 1 sees the crown banner',
        (tester) async {
      final api = _BoardApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        [_entry('viewer-1', 'Me', 1)],
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('You hold this crown — Fastest overall.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed leaderboard offers a retry, not "No efforts yet"',
        (tester) async {
      final api = _ThrowingBoardApi([_segment(id: 'a', name: 'Harlem Hill')]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the leaderboard"), findsOneWidget);
      expect(
        find.text('No efforts yet — be the first to run this segment.'),
        findsNothing,
      );
    });

    testWidgets(
        'a signed-out viewer is asked to sign in rather than shown a doomed retry',
        (tester) async {
      final api = _CatalogueApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        viewer: null,
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text("Couldn't load the leaderboard"), findsNothing);
      expect(find.text('Loading…'), findsNothing);
    });

    testWidgets(
        'a segment timed by its lines with old circle efforts shows the note '
        '(issue #1308)', (tester) async {
      final api = _ZoneNoteApi([_gatedSegment('a')], hasZone: true);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text(_oldMatchNote), findsOneWidget);
    });

    testWidgets(
        'no note when every effort is a line match, or the segment has no '
        'lines (and then nothing is asked)', (tester) async {
      final gated = _ZoneNoteApi([_gatedSegment('a')], hasZone: false);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: gated, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text(_oldMatchNote), findsNothing);

      final plain = _ZoneNoteApi([_segment(id: 'b', name: 'Plain')],
          hasZone: true);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: plain, segmentId: 'b')),
      );
      await tester.pumpAndSettle();
      expect(find.text(_oldMatchNote), findsNothing);
      expect(plain.asked, 0);
    });
  });
}
