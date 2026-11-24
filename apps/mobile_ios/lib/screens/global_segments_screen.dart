import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show CameraFit, LatLngBounds, MapController;
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppInsets,
        AppSemanticColors,
        AppSpace,
        DetailHero,
        DetailMeta,
        DetailPage,
        EmptyState,
        ListCard,
        HubTabBody,
        IdentityAvatar,
        ListSkeleton,
        MapControlButton,
        MapFirstPage,
        SkeletonBlock,
        StatGrid,
        StatTile,
        showFilterSheet;

import '../backend_timeout.dart';
import '../catalogue_browse.dart';
import '../explore_viewport.dart';
import '../fab_clearance.dart';
import '../fitness_surface_requests.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../race_service.dart';
import '../route_surface_label.dart';
import '../routes_views.dart';
import '../widgets/error_state.dart';
import '../widgets/explore_map_chrome.dart';
import '../widgets/explore_segments_map.dart';
import '../widgets/help_button.dart';
import 'park_courses_screen.dart';
import 'races_screen.dart';
import '../widgets/head_to_head_card.dart' show showHeadToHeadSheet;
import '../widgets/sign_in_required_state.dart';
import '../widgets/track_preview.dart';
import '../widgets/loading_skeletons.dart';
import '../widgets/old_match_note.dart';
import '../widgets/segments_panel.dart' show SegmentTierFilters;

/// A catalogue segment on the Explore segments map: its start as an
/// [ExplorePin], with what its card and list row show.
class ExploreSegmentPin extends ExplorePin {
  const ExploreSegmentPin({
    required super.id,
    required super.name,
    required super.lat,
    required super.lng,
    super.distanceM,
    super.surface,
    this.region,
    this.elevationM,
    this.line = const [],
  });

  final String? region;
  final double? elevationM;
  final List<Waypoint> line;
}

/// The curated line of a catalogue row, leaving out any point that does not
/// parse.
List<Waypoint> segmentLine(GlobalSegmentRow row) {
  final out = <Waypoint>[];
  for (final w in row.waypoints) {
    try {
      final p = Waypoint.fromJson(w);
      if (p.lat.isFinite && p.lng.isFinite) out.add(p);
    } catch (_) {
      continue;
    }
  }
  return out;
}

/// The curated famous-segment catalogue (decisions § 233) on a map:
/// Routes → Explore segments (decisions § 2611). Every segment is drawn with
/// its start pin; a tapped one opens a card; the segments in view are a list
/// of their own, searched with accent folding and filtered by region and
/// surface through the `catalogue_browse.dart` parity pair over the whole
/// fetched catalogue, so neither costs a round-trip.
///
/// The catalogue is world-readable, so this screen works signed out, unlike
/// the leaderboard on [GlobalSegmentDetailScreen]. Mounted on its own, where
/// no shell can select the view, it is a page titled Segments.
class GlobalSegmentsScreen extends StatefulWidget {
  final ApiClient? api;

  /// The Routes tab's view menu. Null on its own.
  final RoutesExploreChrome? chrome;

  const GlobalSegmentsScreen({super.key, this.api, this.chrome});

  @override
  State<GlobalSegmentsScreen> createState() => _GlobalSegmentsScreenState();
}

class _GlobalSegmentsScreenState extends State<GlobalSegmentsScreen> {
  final _map = MapController();
  final _changes = ValueNotifier<int>(0);

  List<ExploreSegmentPin> _pins = const [];
  Map<String, List<LatLng>> _lines = const {};
  bool _loading = true;
  bool _error = false;

  String? _region;
  String? _surface;
  ViewBounds? _bounds;
  LatLngPoint? _center;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _map.dispose();
    _changes.dispose();
    super.dispose();
  }

  void _update(VoidCallback fn) {
    setState(fn);
    _changes.value++;
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
      final segments =
          await api.fetchGlobalSegments().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      final pins = <ExploreSegmentPin>[];
      final lines = <String, List<LatLng>>{};
      for (final s in segments) {
        final line = segmentLine(s);
        if (line.isEmpty) continue;
        pins.add(ExploreSegmentPin(
          id: s.id,
          name: s.name,
          lat: line.first.lat,
          lng: line.first.lng,
          distanceM: s.distanceM,
          surface: s.surface,
          region: s.region,
          elevationM: s.elevationM,
          line: line,
        ));
        lines[s.id] = [for (final w in line) LatLng(w.lat, w.lng)];
      }
      _update(() {
        _pins = pins;
        _lines = lines;
        _loading = false;
      });
    } catch (_) {
      // Surfaced rather than degraded to an empty list: "the catalogue is
      // empty" and "the fetch failed" are different claims, and only one of
      // them is worth offering a retry for.
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  List<CatalogueSegment> _catalogueOf(Iterable<ExploreSegmentPin> pins) => [
        for (final p in pins)
          CatalogueSegment(
            id: p.id,
            name: p.name,
            surface: p.surface,
            region: p.region,
            distanceM: p.distanceM,
            elevationM: p.elevationM,
          ),
      ];

  /// The catalogue helpers answer in their own row type; this maps that
  /// answer back onto the pins, in its order.
  List<ExploreSegmentPin> _byIds(Iterable<CatalogueSegment> rows) {
    final byId = {for (final p in _pins) p.id: p};
    return [
      for (final r in rows) ?byId[r.id],
    ];
  }

  List<ExploreSegmentPin> get _filtered => _byIds(filterCatalogue(
        _catalogueOf(_pins),
        region: _region,
        surface: _surface,
      ));

  List<ExploreSegmentPin> get _inView {
    final bounds = _bounds;
    final filtered = _filtered;
    if (bounds == null) return filtered;
    return [for (final p in filtered) if (inBounds(p.lat, p.lng, bounds)) p];
  }

  ExploreSegmentPin? get _selected {
    for (final p in _pins) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  int get _filterCount => (_region != null ? 1 : 0) + (_surface != null ? 1 : 0);

  void _reset() => _update(() {
        _region = null;
        _surface = null;
      });

  void _onMove(ViewBounds bounds, LatLngPoint center) => _update(() {
        _bounds = bounds;
        _center = center;
      });

  Future<void> _onTap(List<ExplorePin> pins) async {
    if (pins.length == 1) {
      _select(pins.first.id);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final byId = {for (final p in _pins) p.id: p};
    final id = await showExplorePicker(
      context,
      title: l10n.exploreMapWhichSegment,
      items: [
        for (final p in pins)
          if (byId[p.id] case final s?)
            (id: s.id, name: s.name, stats: _stats(l10n, s)),
      ],
    );
    if (id != null && mounted) _select(id);
  }

  void _select(String id, {bool frame = false}) {
    _update(() => _selectedId = id);
    final line = _lines[id];
    if (!frame || line == null || line.isEmpty) return;
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(line),
        padding: const EdgeInsets.fromLTRB(40, 96, 40, 260),
        maxZoom: 16,
      ));
    } catch (e) {
      debugPrint('explore segments map not ready to frame: $e');
    }
  }

  void _zoomOut() {
    try {
      final camera = _map.camera;
      _map.move(camera.center, (camera.zoom - 2).clamp(2, 18).toDouble());
    } catch (e) {
      debugPrint('explore segments map not ready to zoom: $e');
    }
  }

  void _open(String segmentId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          GlobalSegmentDetailScreen(api: widget.api, segmentId: segmentId),
    ));
  }

  static String _sortLabel(AppLocalizations l10n, CatalogueSort sort) =>
      switch (sort) {
        CatalogueSort.name => l10n.segmentCatalogueSortName,
        CatalogueSort.shortest => l10n.segmentCatalogueSortShortest,
        CatalogueSort.longest => l10n.segmentCatalogueSortLongest,
        CatalogueSort.climb => l10n.segmentCatalogueSortClimb,
      };

  /// Park courses live in Races & courses (decisions § 2436), so this opens
  /// that tab on its Courses view rather than pushing a copy of the park
  /// index over the hub (decisions § 2437, § 2480).
  void _openParks() => openFitnessSurface(
        context,
        FitnessTab.races,
        racesShow: RacesShow.courses,
        fallback: () => RacesScreen(
          service: RaceService(),
          api: widget.api,
          initialShow: RacesShow.courses,
        ),
      );

  /// "1.20 km · 85 m ↑ · Road", each fact glued so a raised text scale wraps
  /// between facts, never inside one.
  String _stats(AppLocalizations l10n, ExploreSegmentPin p) {
    String glued(String s) => s.replaceAll(' ', '\u00A0');
    final climb = p.elevationM;
    return [
      glued(formatDistanceForPref(p.distanceM)),
      if (climb != null && climb > 0) glued('${formatElevationForPref(climb)} ↑'),
      routeSurfaceLabel(l10n, p.surface),
    ].join(' · ');
  }

  Future<void> _openFilters(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogue = _catalogueOf(_pins);
    final regions = catalogueRegions(catalogue);
    final surfaces = catalogueSurfaces(catalogue);
    return showFilterSheet(
      context: context,
      title: l10n.filterBarFilters,
      doneLabel: l10n.filterBarDone,
      resetLabel: l10n.segmentsPanelResetFilters,
      onReset: _reset,
      builder: (sheetContext, setSheet) {
        final theme = Theme.of(sheetContext);
        Widget group(String heading, List<(String?, String)> options,
                String? selected, ValueChanged<String?> onPick) =>
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpace.sm),
                  // semantics-children: a group name, read once before the controls inside it
                  Semantics(
                    container: true,
                    label: heading,
                    child: Wrap(
                      spacing: AppSpace.sm,
                      children: [
                        for (final (value, label) in options)
                          ChoiceChip(
                            label: Text(label),
                            selected: value == selected,
                            onSelected: (_) {
                              _update(() => onPick(value));
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (regions.length > 1)
              group(
                l10n.filterBarRegion,
                [
                  (null, l10n.segmentCatalogueAllRegions),
                  for (final r in regions) (r, r),
                ],
                _region,
                (v) => _region = v,
              ),
            if (surfaces.length > 1)
              group(
                l10n.filterBarSurface,
                [
                  (null, l10n.segmentCatalogueAllSurfaces),
                  for (final s in surfaces) (s, routeSurfaceLabel(l10n, s)),
                ],
                _surface,
                (v) => _surface = v,
              ),
            Text(
              l10n.segmentCatalogueIntro,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSearch() async {
    final l10n = AppLocalizations.of(context);
    final id = await showExploreSearch(
      context,
      hint: l10n.segmentCatalogueSearchHint,
      emptyText: l10n.segmentCatalogueNoMatches,
      failedText: l10n.segmentCatalogueLoadFailed,
      search: (q) async => [
        for (final p in _byIds(filterCatalogue(_catalogueOf(_filtered), query: q))
            .take(30))
          (id: p.id, name: p.name, meta: p.region ?? ''),
      ],
    );
    if (id != null && mounted) _select(id, frame: true);
  }

  Future<void> _openList() async {
    final l10n = AppLocalizations.of(context);
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ExploreListPage<ExploreSegmentPin>(
          title: l10n.exploreMapListSegmentsTitle,
          changes: _changes,
          items: () => _inView,
          sorts: () => CatalogueSort.values,
          sortLabel: (s) => _sortLabel(l10n, s as CatalogueSort),
          initialSort: CatalogueSort.name,
          sortBy: (items, s) =>
              _byIds(sortCatalogue(_catalogueOf(items), s as CatalogueSort)),
          onOpenFilters: _openFilters,
          filterCount: () => _filterCount,
          searchHint: l10n.exploreMapListSearchLabel,
          emptyText: l10n.exploreMapEmptySegments,
          cardBuilder: (context, p, onTap) => ExploreListCard(
            key: ValueKey('segment-list-card-${p.id}'),
            name: p.name,
            detail: p.region,
            stats: _stats(l10n, p),
            onTap: onTap,
            thumbnail: TrackPreview(points: p.line, aspect: 1),
          ),
        ),
      ),
    );
    if (id != null && mounted) _select(id, frame: true);
  }

  /// What covers the map's middle while there is nothing to browse: the read
  /// in flight, a failed read with Retry, an empty catalogue with the way to
  /// park courses. The map, its menu and Park courses stay around it.
  Widget? _status(AppLocalizations l10n) {
    final theme = Theme.of(context);
    Widget card(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(
              AppInsets.gutter, 64, AppInsets.gutter, 0),
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 2,
            borderRadius: BorderRadius.circular(16),
            child: child,
          ),
        );
    if (_loading) {
      return card(Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpace.smPlus),
              Expanded(child: Text(l10n.segmentsPanelLoading)),
            ],
          ),
        ),
      ));
    }
    if (_error) {
      return card(AppErrorState(
        message: l10n.segmentCatalogueLoadFailed,
        onRetry: _load,
      ));
    }
    if (_pins.isEmpty) {
      return card(EmptyState(
        icon: Icons.terrain,
        title: l10n.segmentCatalogueEmpty,
        ctaLabel: l10n.parksBrowseLink,
        ctaIcon: Icons.park_outlined,
        onCta: _openParks,
      ));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HubTabBody(
      // The view's own name: "Famous segments" under a tab reading
      // "Segments" was two names for one place (issue #1374 report 2).
      title: l10n.runSurfaceTabSegments,
      // A map never scrolls the hub's large title away (decisions § 2610).
      collapsesHubTitle: true,
      onRefresh: _load,
      body: _buildMap(context, l10n),
    );
  }

  Widget _buildMap(BuildContext context, AppLocalizations l10n) {
    final filtered = _filtered;
    final inView = _inView;
    final selected = _selected;
    final center = _center;
    final status = _status(l10n);
    final ready = status == null;
    final empty =
        ready && _bounds != null && inView.isEmpty && selected == null;
    final nearest = empty && center != null ? nearestTo(filtered, center) : null;
    return MapFirstPage(
      map: ExploreSegmentsMap(
        controller: _map,
        pins: filtered,
        lines: _lines,
        selectedId: _selectedId,
        onMove: _onMove,
        onTap: _onTap,
      ),
      overlays: [
        ExploreTopBar(
          menu: widget.chrome?.menu ?? const SizedBox.shrink(),
          searchLabel: l10n.segmentCatalogueSearchHint,
          onSearch: _openSearch,
          filtersLabel: _filterCount > 0
              ? l10n.filterBarFiltersCount(_filterCount)
              : l10n.filterBarFilters,
          filterCount: _filterCount,
          onFilters: () => _openFilters(context),
        ),
        ?status,
        if (empty)
          Padding(
            padding: const EdgeInsets.only(top: 64),
            child: ExploreEmptyOverlay(
              title: l10n.exploreMapEmptySegments,
              onZoomOut: _zoomOut,
              onClearFilters: _filterCount > 0 ? _reset : null,
              nearestName: nearest?.name,
              onNearest: nearest == null
                  ? null
                  : () => _select(nearest.id, frame: true),
            ),
          ),
      ],
      controls: [
        MapControlButton(
          key: const Key('segments-parks-link'),
          icon: Icons.park_outlined,
          label: l10n.parksBrowseLink,
          compact: true,
          onPressed: _openParks,
        ),
      ],
      footer: !ready
          ? null
          : selected == null
          ? ExploreListPill(
              label: l10n.exploreMapListSegments(inView.length),
              onPressed: _openList,
            )
          : ExploreSelectedCard(
              key: ValueKey('explore-segment-card-${selected.id}'),
              name: selected.name,
              detail: selected.region,
              stats: _stats(l10n, selected),
              onClose: () => _update(() => _selectedId = null),
              actions: [
                FilledButton(
                  key: const ValueKey('explore-card-details'),
                  onPressed: () => _open(selected.id),
                  child: Text(l10n.exploreMapDetails),
                ),
              ],
            ),
      attribution: ExploreSegmentsMap.credit(context),
      bottomClearance: DockedFabInset.of(context),
    );
  }
}

/// One catalogue segment: its curated geometry, key stats, description, and the
/// block-guarded leaderboard with the same gender / age-band tiers the
/// route-segment panel offers. Mobile mirror of web `/segments/[id]`.
class GlobalSegmentDetailScreen extends StatefulWidget {
  final ApiClient? api;
  final String segmentId;

  const GlobalSegmentDetailScreen({
    super.key,
    required this.api,
    required this.segmentId,
  });

  @override
  State<GlobalSegmentDetailScreen> createState() =>
      _GlobalSegmentDetailScreenState();
}

class _GlobalSegmentDetailScreenState extends State<GlobalSegmentDetailScreen> {
  GlobalSegmentRow? _segment;
  bool _loading = true;
  bool _loadFailed = false;

  // A null board is the loading state, so a rejected fetch that left it null
  // would read as "still loading" forever. The failure carries its own flag.
  List<GlobalSegmentLeaderboardEntry>? _board;
  bool _boardFailed = false;
  String? _gender;
  String? _ageBand;

  /// The park course built on this segment, if any: the screen links to its
  /// course page, and shows its source credit, which lives in the course's
  /// own column rather than the description (decisions § 2438). Null until
  /// read, and when the read fails: both are auxiliary on this screen.
  ({ParkListing park, ParkCourseListing course})? _parkCourse;

  String? get _courseCredit {
    final credit = _parkCourse?.course.course.attribution?.trim();
    return credit == null || credit.isEmpty ? null : credit;
  }

  @override
  void initState() {
    super.initState();
    _loadSegment();
    _loadParkCourse();
  }

  Future<void> _loadParkCourse() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final found = await api
          .fetchParkCourseForSegment(widget.segmentId)
          .timeout(kBackendLoadTimeout);
      if (!mounted || found == null) return;
      setState(() => _parkCourse = found);
    } catch (e) {
      debugPrint('fetchParkCourseForSegment failed: $e');
    }
  }

  void _openParkCourse(({ParkListing park, ParkCourseListing course}) pc) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParkCourseScreen(
            api: widget.api,
            listing: pc.park,
            course: pc.course,
          ),
        ),
      );

  Future<void> _loadSegment() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final segment = await api
          .fetchGlobalSegment(widget.segmentId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _segment = segment;
        _loading = false;
      });
      if (segment != null) await _refreshBoard();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  Future<void> _refreshBoard() async {
    final api = widget.api;
    // `global_segment_leaderboard` raises 42501 for an anonymous caller, so a
    // signed-out viewer gets the sign-in state rather than an error with a
    // retry that could never succeed.
    if (api == null || api.userId == null) return;
    setState(() {
      _board = null;
      _boardFailed = false;
    });
    try {
      final board = await api
          .fetchGlobalSegmentLeaderboard(
            widget.segmentId,
            gender: _gender,
            ageBand: _ageBand,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _board = board);
    } catch (_) {
      if (!mounted) return;
      setState(() => _boardFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final segment = _segment;
    return DetailPage(
      title: segment?.name ?? l10n.segmentCatalogueTitle,
      pinned: const [HelpButton(routes: ['/segments/[id]'])],
      body: _loading
          ? ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const SkeletonStatStrip(cells: 3),
                const SizedBox(height: 16),
                const SkeletonBlock(height: 160),
                const SizedBox(height: 16),
                ListSkeleton.section(
                  label: l10n.segmentsPanelLoading,
                  rows: 5,
                ),
              ],
            )
          : _loadFailed
              ? AppErrorState(
                  message: l10n.segmentCatalogueDetailFailedTitle,
                  onRetry: _loadSegment,
                )
              : segment == null
                  ? EmptyState(
                      icon: Icons.search_off,
                      title: l10n.segmentCatalogueNotFoundTitle,
                      body: l10n.segmentCatalogueNotFoundBody,
                    )
                  : _buildDetail(context, l10n, segment),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    AppLocalizations l10n,
    GlobalSegmentRow segment,
  ) {
    final theme = Theme.of(context);
    // The catalogue geometry is public curated data, NOT any athlete's GPS
    // track, so it renders directly — there is no owner whose privacy
    // zones could apply, and nothing for `fetchClippedTrackForRun` to
    // protect.
    final geometry = ApiClient.globalSegmentGeometry(segment);
    final elevation = segment.elevationM;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        DetailHero(
          title: segment.name,
          meta: [
            if (segment.region != null && segment.region!.trim().isNotEmpty)
              DetailMeta(icon: Icons.place, text: segment.region!),
          ],
          padding: const EdgeInsets.only(bottom: 12),
        ),
        StatGrid(
          cells: [
            StatTile.medium(
              label: l10n.segmentCatalogueStatDistance,
              value: formatDistanceForPref(segment.distanceM),
            ),
            if (elevation != null && elevation > 0)
              StatTile.medium(
                label: l10n.segmentCatalogueStatElevation,
                value: formatElevationForPref(elevation),
              ),
            StatTile.medium(
              label: l10n.segmentCatalogueStatSurface,
              value: routeSurfaceLabel(l10n, segment.surface),
            ),
          ],
        ),
        if (segment.description != null &&
            segment.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(segment.description!, style: theme.textTheme.bodyMedium),
        ],
        if (_parkCourse case final pc?) ...[
          const SizedBox(height: 8),
          ListCard.row(
            key: const Key('segment-park-course-link'),
            margin: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.park_outlined),
            title: l10n.segmentCatalogueParkCourseLink(pc.park.park.name),
            chevron: true,
            onTap: () => _openParkCourse(pc),
          ),
        ],
        if (_courseCredit case final credit?) ...[
          const SizedBox(height: 8),
          Text(
            credit,
            key: const Key('segment-course-credit'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (geometry.length >= 2) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              // TrackPreview fills whatever it is given, and a ListView
              // gives an unbounded height.
              aspectRatio: 2.4,
              child: TrackPreview(points: geometry),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          l10n.segmentCatalogueLeaderboard,
          style: theme.textTheme.titleSmall,
        ),
        if (widget.api case final api? when api.userId != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('global-segment-head-to-head-open'),
              onPressed: () => showHeadToHeadSheet(
                context,
                api: api,
                kind: 'global_segment',
                targetId: segment.id,
              ),
              icon: const Icon(Icons.people_outline, size: 18),
              label: Text(l10n.headToHeadCompare),
            ),
          ),
        const SizedBox(height: 8),
        _buildBoard(context, l10n),
      ],
    );
  }

  Widget _buildBoard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final api = widget.api;
    if (api == null || api.userId == null) {
      return SizedBox(
        height: 220,
        child: SignInRequiredState(api: api, onSignedIn: _refreshBoard),
      );
    }
    final filtered = _gender != null || _ageBand != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentTierFilters(
          framed: false,
          genderFilter: _gender,
          ageFilter: _ageBand,
          onGenderChanged: (v) {
            setState(() => _gender = v);
            _refreshBoard();
          },
          onAgeChanged: (v) {
            setState(() => _ageBand = v);
            _refreshBoard();
          },
          onReset: () {
            setState(() {
              _gender = null;
              _ageBand = null;
            });
            _refreshBoard();
          },
        ),
        const SizedBox(height: 8),
        if (_segment case final segment?)
          OldMatchNote(api: api, segment: segment),
        if (_boardFailed)
          AppErrorState(
            message: l10n.segmentsPanelLeaderboardError,
            onRetry: _refreshBoard,
          )
        else if (_board == null)
          Text(
            l10n.segmentsPanelLeaderboardLoading,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else if (_board!.isEmpty)
          Text(
            filtered
                ? l10n.segmentsPanelLeaderboardEmptyFiltered
                : l10n.segmentsPanelLeaderboardEmpty,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          ..._boardRows(context, l10n, api.userId),
      ],
    );
  }

  List<Widget> _boardRows(
    BuildContext context,
    AppLocalizations l10n,
    String? viewerId,
  ) {
    final board = _board!;
    final label = crownLabel(_gender, _ageBand);
    final leader = board.first;
    final viewerHoldsCrown = leader.rank == 1 &&
        viewerId != null &&
        leader.effort.userId == viewerId;
    return [
      if (viewerHoldsCrown)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(Icons.emoji_events,
                  size: 18, color: AppSemanticColors.of(context).crown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.segmentsPanelCrownBanner(label),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      for (final entry in board)
        _BoardRow(entry: entry, viewerId: viewerId, crownLabel: label),
    ];
  }
}

class _BoardRow extends StatelessWidget {
  final GlobalSegmentLeaderboardEntry entry;
  final String? viewerId;
  final String crownLabel;

  const _BoardRow({
    required this.entry,
    required this.viewerId,
    required this.crownLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isViewer = viewerId != null && entry.effort.userId == viewerId;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isViewer
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: entry.rank == 1
                ? Tooltip(
                    message: crownLabel,
                    child: Icon(
                      Icons.emoji_events,
                      size: 20,
                      color: AppSemanticColors.of(context).crown,
                    ),
                  )
                : Text(
                    '#${entry.rank}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          IdentityAvatar(
            seed: entry.athlete.id,
            name: entry.athlete.displayName,
            size: 24,
            imageUrl: entry.athlete.avatarUrl,
          ),
          const SizedBox(width: 8),
          // The viewer's "You" sits under the name, not beside it: inline
          // at 320 dp and 2x it and the time left the name no width. The
          // label and the weight are the cue; the row tint is too faint.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.athlete.displayName ?? l10n.segmentsPanelRunnerFallback,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: isViewer ? FontWeight.w700 : null),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isViewer)
                  Text(
                    l10n.navYou,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatEffortTime(entry.effort.timeSeconds),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
