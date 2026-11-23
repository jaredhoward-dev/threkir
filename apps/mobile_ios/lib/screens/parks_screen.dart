import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:ui_kit/ui_kit.dart'
    show
        AppSearchField,
        EmptyState,
        ListSkeleton,
        MapControlButton,
        MapFirstPage,
        PageHeader,
        PushedPage,
        SectionHeader;

import '../adaptive_width.dart';
import '../any_time_courses.dart' show parkSearchMatches, parkSearchTerms;
import '../backend_timeout.dart';
import '../l10n/gen/app_localizations.dart';
import '../park_courses.dart' show groupParksByRegion, regionName;
import '../park_map.dart';
import '../quiet_location.dart' show browseLocateErrorText, locateForBrowse;
import '../widgets/error_state.dart';
import '../widgets/info_tip.dart' show InfoTipButton;
import '../widgets/live_run_map.dart' show currentBasemapIsDark;
import '../widgets/map_attribution.dart';
import '../widgets/park_course_map.dart';
import '../widgets/top_banner.dart';
import 'park_courses_screen.dart' show ParkCard, ParkScreen;

/// The parks a search finds: by a park's own name and place, or by any of its
/// courses' names, so a course name leads to the park that holds it. Every
/// park and course is already loaded, so it is matched on the list
/// ([parkSearchMatches]).
List<ParkListing> parksMatching(
  List<ParkListing> parks,
  Map<String, List<ParkCourseListing>> coursesByPark,
  String query,
) {
  final terms = parkSearchTerms(query);
  if (terms.isEmpty) return parks;
  return [
    for (final listing in parks)
      if (parkSearchMatches(
            terms,
            parkName: listing.park.name,
            regionCode: listing.park.regionCode,
          ) ||
          (coursesByPark[listing.park.id] ?? const []).any(
            (c) => parkSearchMatches(
              terms,
              courseName: c.segment.name,
              parkName: listing.park.name,
              regionCode: listing.park.regionCode,
            ),
          ))
        listing,
  ];
}

void _pushPark(BuildContext context, ApiClient? api, ParkListing listing) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParkScreen(api: api, listing: listing),
      ),
    );

/// Park courses (issue #1313, decisions § 2383), map first (decisions
/// § 2612): every park as a pin on a map, a search on the map's top edge that
/// filters the pins, Near me, and a "List · N parks" button (the parks in view) that opens
/// them grouped by region on [ParksListScreen]. The intro is behind the top
/// bar's How park courses work. Mobile mirror of web `/parks`. The catalogue
/// is world-readable, so this works signed out; only the boards on
/// [ParkCourseScreen] need an account.
class ParksScreen extends StatefulWidget {
  final ApiClient? api;

  /// The search the index opens on, carried from Races & courses' "See all".
  final String initialQuery;

  /// Test seam for Near me; production asks for a browse fix.
  final Future<Position> Function()? locate;

  const ParksScreen({
    super.key,
    this.api,
    this.initialQuery = '',
    this.locate,
  });

  @override
  State<ParksScreen> createState() => _ParksScreenState();
}

class _ParksScreenState extends State<ParksScreen> {
  List<ParkListing> _parks = const [];
  bool _loading = true;
  bool _error = false;

  /// Every listed course, by park id. A second read that places the parks
  /// with no stored centroid and decorates the list, so a failure leaves the
  /// parks listed without their lines.
  Map<String, List<ParkCourseListing>> _coursesByPark = const {};

  late final _searchCtl = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  late String _query = widget.initialQuery;

  final _map = GlobalKey<ParksMapState>();

  /// The map's last settled view; null until it reports one, when every park
  /// shown counts as in view.
  ParkMapBounds? _view;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCourses();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _error = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final parks = await api.fetchParks().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _parks = parks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadCourses() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final courses =
          await api.fetchAllParkCourses().timeout(kBackendLoadTimeout);
      final byPark = <String, List<ParkCourseListing>>{};
      for (final c in courses) {
        byPark.putIfAbsent(c.course.parkId, () => []).add(c);
      }
      if (mounted) setState(() => _coursesByPark = byPark);
    } catch (e) {
      debugPrint('parks index: course read failed: $e');
    }
  }

  List<ParkMapPin> _pins(List<ParkListing> shown) => [
        for (final listing in shown)
          if (parkMarkerPoint(
            (lat: listing.park.centroidLat, lng: listing.park.centroidLng),
            [
              for (final c in _coursesByPark[listing.park.id] ?? const [])
                [
                  for (final w in ApiClient.globalSegmentGeometry(c.segment))
                    (lat: w.lat, lng: w.lng),
                ],
            ],
          )
              case final point?)
            ParkMapPin(
              id: listing.park.id,
              name: listing.park.name,
              courseCount: (_coursesByPark[listing.park.id] ?? const []).length,
              point: point,
            ),
      ];

  Future<void> _nearMe() async {
    if (_locating) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _locating = true);
    try {
      final pos = await (widget.locate ?? locateForBrowse)();
      _map.currentState?.showPlace((lat: pos.latitude, lng: pos.longitude));
    } catch (e) {
      debugPrint('parks index: locate failed: $e');
      if (mounted) {
        showTopBanner(
          context,
          l10n.exploreRoutesNearbyLocationUnavailable(
            browseLocateErrorText(l10n, e),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openList() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParksListScreen(
            api: widget.api,
            parks: _parks,
            coursesByPark: _coursesByPark,
            search: _searchCtl,
            onSearch: (value) {
              _debounce?.cancel();
              setState(() => _query = value);
            },
          ),
        ),
      );

  void _openPark(String id) {
    for (final listing in _parks) {
      if (listing.park.id == id) return _pushPark(context, widget.api, listing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return PushedPage.placeholder(
        title: l10n.parksTitle,
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [ListSkeleton.section(label: l10n.parksLoading, rows: 5)],
        ),
      );
    }
    if (_error) {
      return PushedPage.placeholder(
        title: l10n.parksTitle,
        child: AppErrorState(message: l10n.parksLoadFailed, onRetry: _load),
      );
    }
    if (_parks.isEmpty) {
      return PushedPage.placeholder(
        title: l10n.parksTitle,
        child: EmptyState(
          key: const Key('parks-empty'),
          icon: Icons.park_outlined,
          title: l10n.parksEmpty,
          body: l10n.parksIntro,
        ),
      );
    }
    final shown = parksMatching(_parks, _coursesByPark, _query);
    final pins = _pins(shown);
    final view = _view;
    final inView = view == null
        ? shown.length
        : countInView([for (final p in pins) p.point], view);
    return MapFirstPage(
      appBar: AppBar(
        actions: [
          InfoTipButton(
            key: const Key('parks-how-it-works'),
            label: l10n.parksHowItWorks,
            title: l10n.parksHowItWorks,
            body: l10n.parksIntro,
            guideId: 'park-courses',
          ),
        ],
      ),
      // The search sits on the map's top edge in the solid header rather than
      // floating over the map: at a large text size a floating field covered
      // Near me and the List button on a small phone.
      header: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: l10n.parksTitle,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AppSearchField(
              key: const Key('parks-search'),
              controller: _searchCtl,
              hint: l10n.parksSearchPlaceholder,
              clearTooltip: l10n.commonClearSearch,
              onChanged: _onSearch,
            ),
          ),
        ],
      ),
      map: ParksMap(
        key: _map,
        pins: pins,
        onOpen: _openPark,
        onView: (b) => setState(() => _view = b),
      ),
      controls: [
        MapControlButton(
          key: const Key('parks-near-me'),
          label: l10n.exploreRoutesModeNearMe,
          icon: Icons.near_me_outlined,
          onPressed: _locating ? null : _nearMe,
        ),
      ],
      footer: Center(
        child: FilledButton.icon(
          key: const Key('parks-list-button'),
          onPressed: _openList,
          icon: const Icon(Icons.list),
          label: Text(l10n.parksListButton(inView)),
        ),
      ),
      attribution: MapAttribution(darkBasemap: currentBasemapIsDark(context)),
    );
  }
}

/// The parks as a list, grouped by region: what the map's List button opens.
/// Its search is the map's, so a search typed here filters the map's pins
/// too once back.
class ParksListScreen extends StatefulWidget {
  final ApiClient? api;
  final List<ParkListing> parks;
  final Map<String, List<ParkCourseListing>> coursesByPark;
  final TextEditingController search;
  final ValueChanged<String> onSearch;

  const ParksListScreen({
    super.key,
    required this.api,
    required this.parks,
    required this.coursesByPark,
    required this.search,
    required this.onSearch,
  });

  @override
  State<ParksListScreen> createState() => _ParksListScreenState();
}

class _ParksListScreenState extends State<ParksListScreen> {
  late String _query = widget.search.text;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value);
      widget.onSearch(value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    widget.search.clear();
    setState(() => _query = '');
    widget.onSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = groupParksByRegion<ParkListing>(
      parksMatching(widget.parks, widget.coursesByPark, _query),
      regionCodeOf: (p) => p.park.regionCode,
      nameOf: (p) => p.park.name,
    );
    final wide = widthClassOf(context) == WidthClass.expanded;
    Widget card(ParkListing listing) => ParkCard(
          key: ValueKey('parks-park-${listing.park.id}'),
          listing: listing,
          courses: widget.coursesByPark[listing.park.id],
          onTap: () => _pushPark(context, widget.api, listing),
        );
    return PushedPage(
      title: l10n.parksTitle,
      body: ListView(
        key: const Key('parks-list'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          contentColumn(
            context,
            maxWidth: 1080,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: l10n.parksTitle,
                  padding: const EdgeInsets.only(bottom: 8),
                ),
                AppSearchField(
                  key: const Key('parks-list-search'),
                  controller: widget.search,
                  hint: l10n.parksSearchPlaceholder,
                  clearTooltip: l10n.commonClearSearch,
                  onChanged: _onSearch,
                ),
                if (groups.isEmpty)
                  EmptyState(
                    key: const Key('parks-no-match'),
                    icon: Icons.search_off,
                    title: l10n.parksNoMatch(_query.trim()),
                    ctaLabel: l10n.commonClearSearch,
                    ctaIcon: Icons.close,
                    onCta: _clearSearch,
                  ),
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 8),
                    child: SectionHeader.title(
                      label: regionName(group.regionCode),
                    ),
                  ),
                  if (wide)
                    _TwoColumns(
                      children: [for (final l in group.parks) card(l)],
                    )
                  else
                    for (final l in group.parks) card(l),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays [children] out two to a row, each half the width.
class _TwoColumns extends StatelessWidget {
  final List<Widget> children;
  const _TwoColumns({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final w = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            children: [
              for (final c in children) SizedBox(width: w, child: c),
            ],
          );
        },
      );
}
