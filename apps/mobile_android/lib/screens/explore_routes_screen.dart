import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'
    show CameraFit, LatLngBounds, MapController;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppSpace, HubTabBody, MapControlButton, MapFirstPage, showFilterSheet;

import '../auth_error.dart';
import '../explore_viewport.dart';
import '../fab_clearance.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../main.dart' show pendingArmRunWithRoute;
import '../official_distance.dart';
import '../preferences.dart';
import '../quiet_location.dart';
import '../route_surface_label.dart';
import '../routes_views.dart';
import '../widgets/explore_map_chrome.dart';
import '../widgets/explore_routes_map.dart';
import '../widgets/route_track_preview.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'public_route_screen.dart';
import 'run_screen.dart' show runRecordingActive;

/// A public route on the Explore map: the pin's facts, as an [ExplorePin] the
/// viewport rules can filter, sort and count.
class ExploreRoutePin extends ExplorePin {
  const ExploreRoutePin({
    required super.id,
    required super.name,
    required super.lat,
    required super.lng,
    super.distanceM,
    super.surface,
    super.featured,
    super.runCount,
    this.official = false,
    this.elevationM,
  });

  factory ExploreRoutePin.of(cm.DiscoverableRoutePin p) => ExploreRoutePin(
        id: p.id,
        name: p.name,
        lat: p.lat,
        lng: p.lng,
        distanceM: p.distanceM,
        surface: p.surface,
        featured: p.featured,
        runCount: p.runCount,
        official: p.official,
        elevationM: p.elevationM,
      );

  final bool official;
  final double? elevationM;
}

/// Public routes: Routes → Explore routes (decisions § 2611).
///
/// Map first: under the hub's tabs the map is the page. The view menu, Search
/// and Filters float on its top edge; Popular routes, Where you've run and
/// Near me are compact labelled buttons at its end edge above a "List · N
/// routes" pill; a tapped pin opens a card with the whole name, the Official
/// line under it, the stats, Run this route, Details and Save. The list of
/// the routes in view is a page of its own, and a card there returns here
/// with that route open. Mounted on its own (a test) it is a page titled
/// Explore Routes.
class ExploreRoutesScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRouteStore routeStore;
  final Preferences preferences;

  /// The Routes tab's view menu. Null on its own.
  final RoutesExploreChrome? chrome;

  /// The other maps to open (the routes heatmap, the runner's own), as
  /// compact map buttons stacked above Near me.
  final List<Widget> mapButtons;

  /// Opens the route builder. Kept for the Routes tab's wiring; the map has
  /// no empty-library state of its own.
  final VoidCallback? onBuildRoute;

  /// Test seam for the "Near me" fix. Production callers leave it null and
  /// get [locateForBrowse].
  final Future<Position> Function()? locateFn;

  /// Where the runner's newest run with a track started, for the map to open
  /// on before it knows anything better.
  final LatLng? lastRunStart;

  const ExploreRoutesScreen({
    super.key,
    this.apiClient,
    required this.routeStore,
    required this.preferences,
    this.chrome,
    this.mapButtons = const [],
    this.onBuildRoute,
    this.locateFn,
    this.lastRunStart,
  });

  @override
  State<ExploreRoutesScreen> createState() => _ExploreRoutesScreenState();
}

class _ExploreRoutesScreenState extends State<ExploreRoutesScreen> {
  final _map = MapController();
  final _mapKey = GlobalKey<ExploreRoutesMapState>();

  /// Ticks whenever what the list page shows changes.
  final _changes = ValueNotifier<int>(0);

  List<ExploreRoutePin> _pins = const [];
  bool _loaded = false;
  ViewBounds? _bounds;
  LatLngPoint? _center;
  LatLngPoint? _origin;

  /// Every route seen this visit, for the empty view's nearest one.
  final Map<String, ExploreRoutePin> _seen = {};

  DistanceBucket _distance = DistanceBucket.any;
  String? _surface;
  bool _featuredOnly = false;

  String? _selectedId;

  /// A search pick off the current map, until the map moves to it.
  ExploreRoutePin? _selectedExtra;
  List<LatLng> _selectedLine = const [];
  ({cm.Route? route, List<cm.Waypoint> waypoints, bool isOwner})? _viewable;

  Set<String> _bookmarkedIds = const {};
  final Set<String> _bookmarkBusy = {};
  bool _locating = false;
  bool _arming = false;

  @override
  void initState() {
    super.initState();
    _loadBookmarkedIds();
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

  bool get _signedIn => widget.apiClient?.userId != null;

  ViewportFilter get _filter => ViewportFilter(
        distance: _distance,
        useMiles: widget.preferences.useMiles,
        surface: _surface,
        featuredOnly: _featuredOnly,
      );

  int get _filterCount =>
      (_distance != DistanceBucket.any ? 1 : 0) +
      (_surface != null ? 1 : 0) +
      (_featuredOnly ? 1 : 0);

  List<ExploreRoutePin> get _shown => filterViewport(_pins, _filter);

  ExploreRoutePin? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final p in _shown) {
      if (p.id == id) return p;
    }
    return _selectedExtra?.id == id ? _selectedExtra : null;
  }

  Future<void> _loadBookmarkedIds() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final saved = await api.fetchBookmarkedRoutes(limit: 1000);
      if (mounted) setState(() => _bookmarkedIds = {for (final r in saved) r.id});
    } catch (e) {
      debugPrint('fetchBookmarkedRoutes failed: $e');
    }
  }

  void _onPins(
      List<cm.DiscoverableRoutePin> pins, ViewBounds bounds, LatLngPoint center) {
    _update(() {
      _pins = [for (final p in pins) ExploreRoutePin.of(p)];
      for (final p in _pins) {
        _seen[p.id] = p;
      }
      _bounds = bounds;
      _center = center;
      _loaded = true;
    });
  }

  Future<void> _onTap(List<cm.DiscoverableRoutePin> pins) async {
    if (pins.length == 1) {
      _select(pins.first.id);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final id = await showExplorePicker(
      context,
      title: l10n.exploreMapWhichRoute,
      items: [
        for (final p in pins)
          (
            id: p.id,
            name: p.name,
            stats: _stats(l10n, ExploreRoutePin.of(p), unit),
          ),
      ],
    );
    if (id != null && mounted) _select(id);
  }

  /// Opens [id]'s card and draws its line, read through the viewer-aware
  /// path so a non-owner gets the privacy-clipped line (decisions § 33).
  Future<void> _select(String id, {bool frame = false}) async {
    final api = widget.apiClient;
    _update(() {
      _selectedId = id;
      _selectedLine = const [];
      _viewable = null;
    });
    if (api == null) return;
    try {
      final viewable = await loadViewableRoute(api, id);
      if (!mounted || _selectedId != id) return;
      final line = [
        for (final w in viewable.waypoints) LatLng(w.lat, w.lng),
      ];
      setState(() {
        _viewable = viewable;
        _selectedLine = line;
      });
      if (frame && line.length > 1) _frame(line);
    } catch (e) {
      debugPrint('explore route line read failed: $e');
    }
  }

  void _frame(List<LatLng> line) {
    _mapKey.currentState?.claim();
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(line),
        padding: const EdgeInsets.fromLTRB(40, 96, 40, 260),
        maxZoom: 15,
      ));
    } catch (e) {
      debugPrint('ExploreRoutesScreen: map not ready to frame: $e');
    }
  }

  void _close() => _update(() {
        _selectedId = null;
        _selectedExtra = null;
        _selectedLine = const [];
        _viewable = null;
      });

  void _zoomOut() {
    _mapKey.currentState?.claim();
    try {
      final camera = _map.camera;
      _map.move(camera.center, (camera.zoom - 2).clamp(2, 18).toDouble());
    } catch (e) {
      debugPrint('ExploreRoutesScreen: map not ready to zoom: $e');
    }
  }

  void _moveTo(LatLngPoint at, double zoom) {
    _mapKey.currentState?.claim();
    try {
      _map.move(LatLng(at.lat, at.lng), zoom);
    } catch (e) {
      debugPrint('ExploreRoutesScreen: map not ready to move: $e');
    }
  }

  /// Near me moves the map to the runner and makes nearest first the list's
  /// order.
  Future<void> _nearMe() async {
    if (_locating) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _locating = true);
    try {
      final pos = await (widget.locateFn ?? locateForBrowse)();
      if (!mounted) return;
      final at = LatLngPoint(pos.latitude, pos.longitude);
      _update(() => _origin = at);
      _moveTo(at, 12);
    } on LocationPermanentlyDeniedException {
      if (!mounted) return;
      showTopBanner(context, l10n.exploreRoutesLocationOff,
          actionLabel: l10n.runOpenSettings,
          onAction: () => unawaited(Geolocator.openAppSettings()));
    } on PermissionDeniedException {
      if (mounted) {
        showTopBanner(context, l10n.exploreRoutesLocationPermissionRequired);
      }
    } catch (e) {
      debugPrint('ExploreRoutesScreen near me failed: $e');
      if (mounted) {
        showTopBanner(context,
            l10n.exploreRoutesNearbyLocationUnavailable(browseLocateErrorText(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Loads the route into the recorder without starting it, as a park
  /// course's Run this course does (decisions § 2604): this is pressed while
  /// browsing, often far from the start.
  Future<void> _runThisRoute(String id) async {
    final api = widget.apiClient;
    if (api == null || _arming) return;
    final l10n = AppLocalizations.of(context);
    if (runRecordingActive.value) {
      showTopBanner(context, l10n.exploreMapRunRecording);
      return;
    }
    setState(() => _arming = true);
    try {
      final viewable = _viewable ?? await loadViewableRoute(api, id);
      final route = viewable.route;
      if (route == null || viewable.waypoints.length < 2) {
        throw StateError('route $id has no line to follow');
      }
      if (!mounted) return;
      pendingArmRunWithRoute.value =
          publicRouteStartTarget(route, viewable.waypoints);
    } catch (e) {
      debugPrint('explore run this route failed: $e');
      if (!mounted) return;
      showTopBanner(context, l10n.exploreMapRunFailed,
          actionLabel: l10n.errorStateRetry, onAction: () => _runThisRoute(id));
    } finally {
      if (mounted) setState(() => _arming = false);
    }
  }

  void _openDetails(String id) {
    final api = widget.apiClient;
    if (api == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => PublicRouteScreen(api: api, routeId: id),
        ))
        .then((_) => _loadBookmarkedIds());
  }

  /// Saving a public route is a `saved_routes` reference, not a private copy
  /// (decisions § 30), and a second tap removes it. The icon flips before the
  /// request and back if it fails; a tap while one is in flight is dropped.
  Future<void> _toggleBookmark(String id, String name) async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    if (_bookmarkBusy.contains(id)) return;
    final l10n = AppLocalizations.of(context);
    final wasSaved = _bookmarkedIds.contains(id);
    setState(() {
      _bookmarkBusy.add(id);
      _bookmarkedIds =
          wasSaved ? ({..._bookmarkedIds}..remove(id)) : {..._bookmarkedIds, id};
    });
    try {
      if (wasSaved) {
        await api.unbookmarkRoute(id);
      } else {
        await api.bookmarkRoute(id);
      }
      if (!mounted) return;
      showTopBanner(context,
          wasSaved ? l10n.exploreRoutesRemoved(name) : l10n.exploreRoutesSaved(name));
    } catch (e) {
      debugPrint('explore bookmark toggle failed: $e');
      if (!mounted) return;
      setState(() {
        _bookmarkedIds = wasSaved
            ? {..._bookmarkedIds, id}
            : ({..._bookmarkedIds}..remove(id));
      });
      showTopBanner(context, l10n.routeDetailBookmarkFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _bookmarkBusy.remove(id));
    }
  }

  Map<DistanceBucket, String> _distanceLabels(AppLocalizations l10n) {
    final mi = widget.preferences.useMiles;
    return {
      DistanceBucket.any: l10n.exploreRoutesDistanceAny,
      DistanceBucket.short:
          mi ? l10n.exploreRoutesDistanceUnderMi : l10n.exploreRoutesDistanceUnderKm,
      DistanceBucket.medium:
          mi ? l10n.exploreRoutesDistanceMidMi : l10n.exploreRoutesDistanceMidKm,
      DistanceBucket.long:
          mi ? l10n.exploreRoutesDistanceLongMi : l10n.exploreRoutesDistanceLongKm,
      DistanceBucket.ultra:
          mi ? l10n.exploreRoutesDistanceUltraMi : l10n.exploreRoutesDistanceUltraKm,
    };
  }

  Map<String?, String> _surfaceLabels(AppLocalizations l10n) => {
        null: l10n.exploreRoutesSurfaceAny,
        'road': l10n.exploreRoutesSurfaceRoad,
        'trail': l10n.exploreRoutesSurfaceTrail,
        'mixed': l10n.exploreRoutesSurfaceMixed,
      };

  void _clearFilters() => _update(() {
        _distance = DistanceBucket.any;
        _surface = null;
        _featuredOnly = false;
      });

  Future<void> _openFilters(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showFilterSheet(
      context: context,
      title: l10n.filterBarFilters,
      doneLabel: l10n.filterBarDone,
      resetLabel: l10n.routesClearFilters,
      onReset: _clearFilters,
      builder: (sheetContext, setSheet) {
        final theme = Theme.of(sheetContext);
        Widget group(String heading, List<Widget> chips) => Padding(
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
                        spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: chips),
                  ),
                ],
              ),
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            group(l10n.filterBarDistance, [
              for (final e in _distanceLabels(l10n).entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _distance == e.key,
                  onSelected: (_) {
                    _update(() => _distance = e.key);
                    setSheet(() {});
                  },
                ),
            ]),
            group(l10n.filterBarSurface, [
              for (final e in _surfaceLabels(l10n).entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _surface == e.key,
                  onSelected: (_) {
                    _update(() => _surface = e.key);
                    setSheet(() {});
                  },
                ),
            ]),
            group(l10n.exploreRoutesFeatured, [
              FilterChip(
                avatar: const Icon(Icons.star_border, size: 18),
                label: Text(l10n.exploreRoutesFeatured),
                selected: _featuredOnly,
                onSelected: (v) {
                  _update(() => _featuredOnly = v);
                  setSheet(() {});
                },
              ),
            ]),
          ],
        );
      },
    );
  }

  /// Finds a route anywhere, not only in view, and opens it on the map.
  Future<void> _openSearch() async {
    final api = widget.apiClient;
    if (api == null) return;
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final found = <String, cm.Route>{};
    final bounds = distanceBucketBounds(_distance, widget.preferences.useMiles);
    final id = await showExploreSearch(
      context,
      hint: l10n.exploreRoutesSearchHint,
      emptyText: l10n.exploreRoutesEmptyNoMatch,
      failedText: l10n.exploreRoutesSearchFailed,
      search: (q) async {
        final page = await api.searchPublicRoutes(
          query: q,
          minDistanceM: bounds.min,
          maxDistanceM: bounds.max,
          surface: _surface,
          featuredOnly: _featuredOnly,
          sort: 'popular',
          limit: 20,
        );
        for (final r in page.rows) {
          found[r.id] = r;
        }
        return [
          for (final r in page.rows)
            (
              id: r.id,
              name: r.name,
              meta: UnitFormat.distance(
                  routeDisplayDistanceM(
                      r.distanceMetres, r.officialDistanceMetres),
                  unit),
            ),
        ];
      },
    );
    if (id == null || !mounted) return;
    final r = found[id];
    if (r != null) {
      _selectedExtra = ExploreRoutePin(
        id: r.id,
        name: r.name,
        lat: 0,
        lng: 0,
        distanceM: r.distanceMetres,
        surface: r.surface ?? '',
        featured: r.featured,
        runCount: r.runCount,
        official: r.official,
        elevationM: r.elevationGainMetres,
      );
    }
    await _select(id, frame: true);
  }

  Future<void> _openList() async {
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final api = widget.apiClient;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ExploreListPage<ExploreRoutePin>(
          title: l10n.exploreMapListRoutesTitle,
          changes: _changes,
          items: () => _shown,
          sorts: () => [
            if (_origin != null) ExploreSort.nearest,
            ExploreSort.mostRun,
            ExploreSort.name,
          ],
          sortLabel: (s) => exploreSortLabel(l10n, s as ExploreSort),
          initialSort: defaultSort(_origin),
          sortBy: (items, s) => sortViewport(items, s as ExploreSort, _origin),
          onOpenFilters: _openFilters,
          filterCount: () => _filterCount,
          searchHint: l10n.exploreMapListSearchLabel,
          emptyText: l10n.exploreMapEmptyRoutes,
          cardBuilder: (context, p, onTap) => ExploreListCard(
            key: ValueKey('explore-list-card-${p.id}'),
            name: p.name,
            official: p.official,
            stats: _stats(l10n, p, unit),
            onTap: onTap,
            thumbnail: api == null
                ? const Icon(Icons.route)
                : RouteTrackPreview(
                    routeId: p.id,
                    waypoints: const [],
                    ownerUserId: '',
                    api: api,
                    aspect: 1,
                  ),
          ),
        ),
      ),
    );
    if (id == null || !mounted) return;
    await _select(id, frame: true);
  }

  /// "12.50 km · 80 m ↑ · Trail". Every space inside a fact is non-breaking,
  /// so a raised text scale wraps between facts, never inside one.
  String _stats(AppLocalizations l10n, ExploreRoutePin p, cm.DistanceUnit unit) {
    String glued(String s) => s.replaceAll(' ', ' ');
    final climb = p.elevationM;
    return [
      glued(UnitFormat.distance(p.distanceM, unit)),
      if (climb != null && climb > 0)
        glued('${UnitFormat.elevation(climb, unit)} ↑'),
      if (p.surface.isNotEmpty) routeSurfaceLabel(l10n, p.surface),
    ].join(' · ');
  }

  Widget? _overlay(AppLocalizations l10n) {
    if (!_loaded || _selected != null) return null;
    final shown = _shown;
    if (shown.isNotEmpty) return null;
    final center = _center;
    final bounds = _bounds;
    final elsewhere = filterViewport(_seen.values, _filter).where(
        (p) => bounds == null || !inBounds(p.lat, p.lng, bounds));
    final nearest = center == null ? null : nearestTo(elsewhere, center);
    return ExploreEmptyOverlay(
      title: l10n.exploreMapEmptyRoutes,
      onZoomOut: _zoomOut,
      onClearFilters: _filter.active ? _clearFilters : null,
      nearestName: nearest?.name,
      onNearest: nearest == null
          ? null
          : () {
              _moveTo(LatLngPoint(nearest.lat, nearest.lng), 13);
              _select(nearest.id);
            },
    );
  }

  Widget _footer(AppLocalizations l10n) {
    final selected = _selected;
    if (selected == null) {
      return ExploreListPill(
        label: l10n.exploreMapListRoutes(_shown.length),
        onPressed: _openList,
      );
    }
    final saved = _bookmarkedIds.contains(selected.id);
    final unit = widget.preferences.unit;
    return ExploreSelectedCard(
      key: ValueKey('explore-card-${selected.id}'),
      name: selected.name,
      official: selected.official,
      stats: _stats(l10n, selected, unit),
      onClose: _close,
      actions: [
        FilledButton.icon(
          key: const ValueKey('explore-card-run'),
          onPressed: _arming ? null : () => _runThisRoute(selected.id),
          icon: const Icon(Icons.directions_run),
          label: Text(l10n.exploreMapRunThisRoute),
        ),
        OutlinedButton(
          key: const ValueKey('explore-card-details'),
          onPressed: () => _openDetails(selected.id),
          child: Text(l10n.exploreMapDetails),
        ),
        if (_signedIn)
          IconButton(
            key: const ValueKey('explore-card-save'),
            onPressed: _bookmarkBusy.contains(selected.id)
                ? null
                : () => _toggleBookmark(selected.id, selected.name),
            tooltip: saved
                ? l10n.exploreRoutesRemoveFromLibrary
                : l10n.exploreRoutesSaveToLibrary,
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    final overlay = _signedIn ? _overlay(l10n) : null;
    return HubTabBody(
      title: l10n.exploreRoutesTitle,
      // A map never scrolls the hub's large title away (decisions § 2610).
      collapsesHubTitle: true,
      body: MapFirstPage(
        map: ExploreRoutesMap(
          key: _mapKey,
          api: api,
          controller: _map,
          onPins: _onPins,
          onTap: _onTap,
          visibleIds: {for (final p in _shown) p.id},
          selectedId: _selectedId,
          selectedLine: _selectedLine,
          lastRunStart: widget.lastRunStart,
        ),
        overlays: [
          ExploreTopBar(
            menu: widget.chrome?.menu ?? const SizedBox.shrink(),
            searchLabel: l10n.exploreRoutesSearchHint,
            onSearch: _openSearch,
            filtersLabel: _filterCount > 0
                ? l10n.filterBarFiltersCount(_filterCount)
                : l10n.filterBarFilters,
            filterCount: _filterCount,
            onFilters: () => _openFilters(context),
          ),
          if (overlay != null)
            Padding(padding: const EdgeInsets.only(top: 64), child: overlay),
        ],
        controls: [
          ...widget.mapButtons,
          MapControlButton(
            key: const ValueKey('explore-near-me'),
            label: l10n.exploreRoutesModeNearMe,
            icon: Icons.near_me_outlined,
            selectedIcon: Icons.near_me,
            selected: _origin != null,
            compact: true,
            onPressed: _nearMe,
          ),
        ],
        // Signed out, the map stays and the way forward takes the card's
        // place.
        footer: _signedIn
            ? _footer(l10n)
            : Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 4,
                borderRadius: BorderRadius.circular(20),
                child: SignInRequiredState(
                  api: api,
                  message: l10n.exploreRoutesSignInToExplore,
                  onSignedIn: () async {
                    setState(() {});
                    await _loadBookmarkedIds();
                    await _mapKey.currentState?.refresh();
                  },
                ),
              ),
        attribution: ExploreRoutesMap.credit(context),
        bottomClearance: DockedFabInset.of(context),
      ),
    );
  }
}
