import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../explore_viewport.dart' show ExplorePin, LatLngPoint, ViewBounds;
import '../heatmap_clustering.dart';
import '../l10n/gen/app_localizations.dart';
import 'live_run_map.dart'
    show basemapTileLayer, basemapVoidColour, currentBasemapIsDark, currentTileUrl;
import 'map_attribution.dart';

/// The map behind Routes → Explore segments (decisions § 2611): every
/// catalogue segment the page hands it, as its line and a start pin with a
/// 48 dp target. The catalogue is fetched whole, so the map reads nothing:
/// it reports its view through [onMove] and taps through [onTap] (one pin, or
/// a small cluster's segments for "Which segment?"). It frames every segment
/// once, when it first lays out.
class ExploreSegmentsMap extends StatefulWidget {
  const ExploreSegmentsMap({
    super.key,
    required this.controller,
    required this.pins,
    required this.lines,
    required this.onMove,
    required this.onTap,
    this.selectedId,
  });

  final MapController controller;
  final List<ExplorePin> pins;

  /// Each segment's line, by id.
  final Map<String, List<LatLng>> lines;
  final void Function(ViewBounds bounds, LatLngPoint center) onMove;
  final void Function(List<ExplorePin> pins) onTap;
  final String? selectedId;

  static const pickClusterMax = 6;

  static Widget credit(BuildContext context) =>
      MapAttribution(darkBasemap: currentBasemapIsDark(context));

  @override
  State<ExploreSegmentsMap> createState() => _ExploreSegmentsMapState();
}

class _ExploreSegmentsMapState extends State<ExploreSegmentsMap> {
  Timer? _debounce;
  bool _framed = false;
  bool _ready = false;

  @override
  void didUpdateWidget(ExploreSegmentsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The catalogue lands after the map has laid out: frame it then.
    if (!_framed && widget.pins.isNotEmpty && oldWidget.pins.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _frame();
        _report();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _report() {
    if (!_ready) return;
    final camera = widget.controller.camera;
    final b = camera.visibleBounds;
    widget.onMove(
      ViewBounds(west: b.west, south: b.south, east: b.east, north: b.north),
      LatLngPoint(camera.center.latitude, camera.center.longitude),
    );
  }

  void _frame() {
    if (!_ready || _framed || widget.pins.isEmpty) return;
    _framed = true;
    final points = [for (final p in widget.pins) LatLng(p.lat, p.lng)];
    try {
      if (points.length == 1) {
        widget.controller.move(points.first, 13);
      } else {
        widget.controller.fitCamera(CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(40, 96, 40, 160),
        ));
      }
    } catch (e) {
      debugPrint('explore segments map not ready to frame: $e');
    }
  }

  void _tapCluster(PinCluster<ExplorePin> c) {
    if (c.count <= ExploreSegmentsMap.pickClusterMax) {
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
    final selected = widget.selectedId;
    final dim = selected != null;
    return FlutterMap(
      key: const ValueKey('explore-segments-map'),
      mapController: widget.controller,
      options: MapOptions(
        backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
        initialCenter: const LatLng(20, 0),
        initialZoom: 2,
        minZoom: 2,
        onMapReady: () {
          _ready = true;
          _frame();
          _report();
        },
        onPositionChanged: (_, _) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 200), _report);
        },
      ),
      children: [
        basemapTileLayer(urlTemplate: currentTileUrl(context)),
        PolylineLayer(polylines: [
          for (final p in widget.pins)
            if ((widget.lines[p.id]?.length ?? 0) > 1)
              Polyline(
                points: widget.lines[p.id]!,
                strokeWidth: p.id == selected ? 6 : 3,
                color: p.id == selected
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary
                        .withValues(alpha: dim ? 0.35 : 0.85),
              ),
        ]),
        Builder(builder: (context) {
          final camera = MapCamera.of(context);
          final clusters = clusterPins<ExplorePin>(
            items: widget.pins,
            latOf: (p) => p.lat,
            lngOf: (p) => p.lng,
            project: (lat, lng) {
              final o = camera.latLngToScreenOffset(LatLng(lat, lng));
              return (x: o.dx, y: o.dy);
            },
            radiusPx: 44,
          );
          return MarkerLayer(markers: [
            for (final c in clusters)
              Marker(
                point: LatLng(c.lat, c.lng),
                width: 48,
                height: 48,
                child: c.isCluster
                    ? Semantics(
                        excludeSemantics: true,
                        button: true,
                        label: l10n.segmentCatalogueCount(c.count),
                        onTap: () => _tapCluster(c),
                        child: GestureDetector(
                          key: ValueKey('explore-segment-cluster-${c.first.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tapCluster(c),
                          child: _Disc(
                            size: 32,
                            color: theme.colorScheme.primary,
                            faded: dim,
                            child: FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text('${c.count}',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                        color: theme.colorScheme.onPrimary)),
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
                          key: ValueKey('explore-segment-pin-${c.first.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onTap([c.first]),
                          child: _Disc(
                            size: c.first.id == selected ? 26 : 20,
                            color: c.first.id == selected
                                ? theme.colorScheme.tertiary
                                : theme.colorScheme.primary,
                            faded: dim && c.first.id != selected,
                          ),
                        ),
                      ),
              ),
          ]);
        }),
      ],
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({
    required this.size,
    required this.color,
    this.faded = false,
    this.child,
  });

  final double size;
  final Color color;
  final bool faded;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Center(
        child: Opacity(
          opacity: faded ? 0.4 : 1,
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
        ),
      );
}
