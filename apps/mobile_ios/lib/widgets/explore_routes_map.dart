import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../explore_viewport.dart' show LatLngPoint, ViewBounds;
import '../heatmap_clustering.dart';
import '../l10n/gen/app_localizations.dart';
import '../map_view_memory.dart';
import '../quiet_location.dart';
import 'live_run_map.dart'
    show basemapTileLayer, basemapVoidColour, currentBasemapIsDark, currentTileUrl;
import 'map_attribution.dart';

/// The map behind Routes → Explore (decisions § 2611): the public routes in
/// view, as start pins, from the same `discoverable_routes_in_bbox` read the
/// routes heatmap uses, which places each pin server-side (a non-owner never
/// receives a route's raw line here).
///
/// It refetches as the camera settles and reports what it read through
/// [onPins]; the page filters them and hands back the ids to draw as
/// [visibleIds]. It opens on the best place it knows and moves to a better
/// one as it arrives, until the runner moves the map (decisions § 2613): the
/// world, then the start of their newest run ([lastRunStart]), then where
/// they last left this map ([memory]), then a quiet fix of where they are
/// (never prompting).
/// A pin is a 48 dp target. A tap on one pin reports it through [onTap]; a
/// tap on a small cluster of overlapping pins reports them all, for the
/// page's "Which route?"; a big cluster zooms in. With a route selected its
/// line is drawn, its start marked, and the other pins dim.
/// The preferences key for where Routes → Explore was last left.
const String kExploreRoutesViewKey = 'explore_routes_last_view';

class ExploreRoutesMap extends StatefulWidget {
  const ExploreRoutesMap({
    super.key,
    required this.api,
    required this.controller,
    required this.onPins,
    required this.onTap,
    this.visibleIds,
    this.selectedId,
    this.selectedLine = const [],
    this.quietFixes = quietPositionFixes,
    this.lastRunStart,
    this.memory = const MapViewMemory(kExploreRoutesViewKey),
  });

  final ApiClient? api;

  /// Owned by the screen, which moves it for Near me, a search pick and
  /// Zoom out.
  final MapController controller;

  /// Every read of the routes in view, with the view it was read for.
  final void Function(List<cm.DiscoverableRoutePin> pins, ViewBounds bounds,
      LatLngPoint center) onPins;

  /// The pins under a tap: one, or a small cluster's routes.
  final void Function(List<cm.DiscoverableRoutePin> pins) onTap;

  /// The pins the page's filters keep; null draws every pin read.
  final Set<String>? visibleIds;

  final String? selectedId;
  final List<LatLng> selectedLine;

  /// Test seam; production centres on [quietPositionFixes].
  final Stream<Position> Function() quietFixes;

  /// Where the runner's newest run with a track started, if this phone holds
  /// one.
  final LatLng? lastRunStart;

  /// Where this map was last left.
  final MapViewMemory memory;

  /// A cluster this small opens as a list; a bigger one zooms in.
  static const pickClusterMax = 6;

  /// This map's credit, for the page to float in its column, where the map's
  /// own bottom edge is covered.
  static Widget credit(BuildContext context) =>
      MapAttribution(darkBasemap: currentBasemapIsDark(context));

  @override
  State<ExploreRoutesMap> createState() => ExploreRoutesMapState();
}

class ExploreRoutesMapState extends State<ExploreRoutesMap> {
  static const _clusterRadiusPx = 44.0;
  static const _openZoom = 12.0;

  List<cm.DiscoverableRoutePin> _pins = const [];
  Timer? _debounce;
  StreamSubscription<Position>? _fixes;
  ({LatLng at, double zoom, MapOpening by})? _pending;
  late MapOpening _openedOn =
      widget.lastRunStart == null ? MapOpening.world : MapOpening.lastRun;
  bool _ready = false;
  bool _moved = false;

  /// Whether the remembered view has been read: until then a save would
  /// overwrite it with the view the map opened on.
  bool _recalled = false;
  int _generation = 0;

  /// The last read of the routes in view failed. Shown on the map with
  /// Retry, never as an empty map (issue #1374 FS-10).
  bool _failed = false;

  /// Whether the camera has had a move since the runner last touched it.
  bool get moved => _moved;

  /// Whether the remembered view has been read.
  @visibleForTesting
  bool get recalled => _recalled;

  /// A move the runner asked for through the page (Near me, a search pick,
  /// Zoom out): the map stops moving itself to a better opening view.
  void claim() => _moved = true;

  @override
  void initState() {
    super.initState();
    _fixes = widget.quietFixes().listen((pos) => _open(
        LatLng(pos.latitude, pos.longitude), _openZoom, MapOpening.here));
    _recall();
  }

  Future<void> _recall() async {
    final view = await widget.memory.load();
    _recalled = true;
    if (view == null || !mounted) return;
    _open(LatLng(view.lat, view.lng), view.zoom, MapOpening.remembered);
  }

  /// Moves to [at] when [by] beats what the map opened on and the runner has
  /// not moved it; held until the map is ready.
  void _open(LatLng at, double zoom, MapOpening by) {
    if (!mounted || !opensOn(_openedOn, by, touched: _moved)) return;
    final pending = _pending;
    if (pending != null && pending.by.index >= by.index) return;
    if (!_ready) {
      _pending = (at: at, zoom: zoom, by: by);
      return;
    }
    _openedOn = by;
    widget.controller.move(at, zoom);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fixes?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  Future<void> refresh() async {
    if (!_ready) return;
    final camera = widget.controller.camera;
    final b = camera.visibleBounds;
    final bounds =
        ViewBounds(west: b.west, south: b.south, east: b.east, north: b.north);
    final center = LatLngPoint(camera.center.latitude, camera.center.longitude);
    if (_recalled) {
      unawaited(widget.memory.save(
          (lat: center.lat, lng: center.lng, zoom: camera.zoom)));
    }
    final api = widget.api;
    if (api == null) return;
    final generation = ++_generation;
    try {
      final pins = await api.fetchDiscoverableRoutesInBbox(
        minLng: b.west,
        minLat: b.south,
        maxLng: b.east,
        maxLat: b.north,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _pins = pins;
        _failed = false;
      });
      widget.onPins(pins, bounds, center);
    } catch (e) {
      // L4: a failed read keeps the pins already shown and says so on the map.
      debugPrint('explore map routes read failed: ${safeErrorLabel(e)}');
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  void _tapCluster(PinCluster<cm.DiscoverableRoutePin> c) {
    if (c.count <= ExploreRoutesMap.pickClusterMax) {
      widget.onTap(c.items);
      return;
    }
    final camera = widget.controller.camera;
    widget.controller.move(LatLng(c.lat, c.lng), camera.zoom + 2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final visible = widget.visibleIds;
    final shown = visible == null
        ? _pins
        : [for (final p in _pins) if (visible.contains(p.id)) p];
    final selected = widget.selectedId;
    return FlutterMap(
      key: const ValueKey('explore-routes-map'),
      mapController: widget.controller,
      options: MapOptions(
        backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
        initialCenter: widget.lastRunStart ?? const LatLng(20, 0),
        initialZoom: widget.lastRunStart == null ? 2 : _openZoom,
        minZoom: 2,
        onMapReady: () {
          _ready = true;
          final pending = _pending;
          _pending = null;
          if (pending != null) _open(pending.at, pending.zoom, pending.by);
          refresh();
        },
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) _moved = true;
          _schedule();
        },
      ),
      children: [
        basemapTileLayer(urlTemplate: currentTileUrl(context)),
        if (selected != null && widget.selectedLine.length > 1)
          PolylineLayer(polylines: [
            Polyline(
              points: widget.selectedLine,
              strokeWidth: 5,
              color: theme.colorScheme.primary,
              borderStrokeWidth: 2,
              borderColor: theme.colorScheme.surface,
            ),
          ]),
        Builder(builder: (context) {
          final camera = MapCamera.of(context);
          final clusters = clusterPins<cm.DiscoverableRoutePin>(
            items: shown,
            latOf: (p) => p.lat,
            lngOf: (p) => p.lng,
            project: (lat, lng) {
              final o = camera.latLngToScreenOffset(LatLng(lat, lng));
              return (x: o.dx, y: o.dy);
            },
            radiusPx: _clusterRadiusPx,
          );
          final dim = selected != null;
          return MarkerLayer(
            markers: [
              for (final c in clusters)
                Marker(
                  point: LatLng(c.lat, c.lng),
                  width: 48,
                  height: 48,
                  child: c.isCluster
                      ? Semantics(
                          excludeSemantics: true,
                          onTap: () => _tapCluster(c),
                          button: true,
                          label: l10n.heatmapRouteCount(c.count),
                          child: GestureDetector(
                            key: ValueKey('explore-cluster-${c.first.id}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _tapCluster(c),
                            child: Opacity(
                              opacity: dim ? 0.4 : 1,
                              child: _Dot(
                                size: 32,
                                color: theme.colorScheme.primary,
                                // Scales down rather than spill out of the
                                // dot at a large text size.
                                child: FittedBox(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      '${c.count}',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                              color: theme
                                                  .colorScheme.onPrimary),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      // semantics-children: the child draws no text, and keeps its own tap
                      : Semantics(
                          button: true,
                          selected: c.first.id == selected,
                          label: c.first.name,
                          child: GestureDetector(
                            key: ValueKey('explore-pin-${c.first.id}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onTap([c.first]),
                            child: c.first.id == selected
                                ? _Dot(
                                    size: 28,
                                    color: theme.colorScheme.tertiary,
                                  )
                                : Opacity(
                                    opacity: dim ? 0.4 : 1,
                                    child: _Dot(
                                      size: 20,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                          ),
                        ),
                ),
            ],
          );
        }),
        if (_failed)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              // Under the page's bar on the map's top edge.
              padding: const EdgeInsets.fromLTRB(8, 72, 8, 8),
              child: ActionChip(
                key: const Key('explore-map-load-failed'),
                avatar: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.heatmapLoadFailed),
                onPressed: refresh,
              ),
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color, this.child});

  final double size;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
                color: Theme.of(context).colorScheme.surface, width: 2),
          ),
          child: child,
        ),
      );
}
