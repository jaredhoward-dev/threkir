import 'dart:math' as math;

import 'package:core_models/core_models.dart' show GlobalSegmentRow, Waypoint;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppMotion, AppSemanticColors, ChartPalette;

import '../course_gates.dart';
import '../course_jump.dart';
import '../gate_crossing.dart' show Gate;
import '../l10n/gen/app_localizations.dart';
import '../park_courses.dart' show CourseCheckpoint, checkpointMarks;
import '../park_map.dart' show ParkMapBounds, ParkMapPoint, groupOverlapping;
import '../run_stats.dart' show haversineMetres;
import 'live_run_map.dart'
    show
        basemapTileLayer,
        basemapVoidColour,
        chevronInk,
        chevronOutline,
        currentBasemapIsDark,
        currentTileUrl,
        mapFinishZoneColour,
        mapOverlayOutline,
        mapStartZoneColour,
        mapBoxInk,
        mapTrackLine,
        mapZoneFillOpacity,
        solidMapLine;
import 'map_attribution.dart';
import 'track_decorations.dart' show computeChevrons;

/// A course whose first and last points sit this close together starts and
/// finishes in one place, so the map draws one marker for both.
const double kParkCourseSharedEndM = 60;

/// Starts closer together than this share one start marker on the park map.
const double kParkStartMergeM = 60;

/// How many direction chevrons a course line carries, spread along its length.
const int kParkCourseChevrons = 6;

/// The colour of a park's [index]th course line, as the park map draws it and
/// the course list's swatch repeats it. Keyed on the basemap, as the start and
/// finish colours are, because the line is drawn over tiles.
Color parkCourseLineColour(int index, {required bool darkBasemap}) {
  final kinds = (darkBasemap ? ChartPalette.dark : ChartPalette.light).kinds;
  return kinds[index % kinds.length];
}

AppSemanticColors _endPalette(bool darkBasemap) =>
    darkBasemap ? AppSemanticColors.dark : AppSemanticColors.light;

LatLng _ll(Waypoint w) => LatLng(w.lat, w.lng);

/// Whether [line] starts and finishes in the same place.
bool courseEndsShared(List<Waypoint> line) =>
    line.length >= 2 &&
    haversineMetres(
          line.first.lat,
          line.first.lng,
          line.last.lat,
          line.last.lng,
        ) <=
        kParkCourseSharedEndM;

double _lineMetres(List<LatLng> pts) {
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += haversineMetres(
      pts[i - 1].latitude,
      pts[i - 1].longitude,
      pts[i].latitude,
      pts[i].longitude,
    );
  }
  return total;
}

/// A course's start and finish lines as a page draws them: the segment's
/// stored lines, the ones the matcher times, or null unless both are whole
/// (decisions § 2582). Twin of web's `courseBoxGates` (`course_map.ts`).
({Gate start, Gate finish})? courseBoxGates(GlobalSegmentRow segment) {
  Gate? gate(double? lat, double? lng, double? bearing, double? halfWidth) {
    if (lat == null ||
        lng == null ||
        bearing == null ||
        halfWidth == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        !bearing.isFinite ||
        !halfWidth.isFinite) {
      return null;
    }
    return Gate(lat: lat, lng: lng, bearingDeg: bearing, halfWidthM: halfWidth);
  }

  final start = gate(segment.startGateLat, segment.startGateLng,
      segment.startGateBearingDeg, segment.startGateHalfWidthM);
  final finish = gate(segment.endGateLat, segment.endGateLng,
      segment.endGateBearingDeg, segment.endGateHalfWidthM);
  if (start == null || finish == null) return null;
  return (start: start, finish: finish);
}

/// The one sentence a course page gives a runner (decisions § 2582): start
/// recording in the green box and follow the arrows to the red one (round the
/// loop [laps] times on a lapped course). Where the start and finish share a
/// spot, a loop or an out-and-back, it is one start box, left and come back
/// to, by way of the Turn around mark when the course marks one. Twin of
/// web's `courseBoxInstruction`.
String courseBoxInstruction(
  AppLocalizations l10n,
  ({Gate start, Gate finish}) g, {
  required bool hasTurn,
  int? laps,
}) {
  final n = laps != null && laps > 0 ? laps : 1;
  if (gateBoxParts(g.start, g.finish).layout == GateBoxLayout.shared) {
    return hasTurn ? l10n.parksBoxesOutAndBack : l10n.parksBoxesShared(n);
  }
  return l10n.parksBoxesApart(n);
}

LatLng _gp(GatePoint p) => LatLng(p.lat, p.lng);

/// The start and finish boxes over a course map (decisions § 2582), from
/// [gateBoxParts]: a translucent fill with a full-strength outline, the
/// timing line (solid for the start, chequered for the finish and for the one
/// start-coloured box a start and finish at one spot share), and a flag with
/// the box's name at a fixed size, so the boxes read first at the
/// whole-course zoom. Twin of web's `addCourseGateBoxLayers` and its markers.
/// With [onTap] each name tag is a button, named by [tapLabel], that the map
/// passes its box to ([GateWhich] null for the one box a start and finish
/// share).
List<Widget> courseGateBoxLayers({
  required Gate start,
  required Gate finish,
  required bool darkBasemap,
  required String startLabel,
  required String finishLabel,
  required String bothLabel,
  required double centreLng,
  void Function(GateWhich? which)? onTap,
  String Function(GateWhich? which)? tapLabel,
}) {
  final boxes = gateBoxParts(start, finish);

  final casing = mapOverlayOutline(darkBasemap: darkBasemap);
  Color colourOf(GateWhich? w) => w == GateWhich.finish
      ? mapFinishZoneColour(darkBasemap: darkBasemap)
      : mapStartZoneColour(darkBasemap: darkBasemap);
  final edges = <Polyline>[];
  for (final p in boxes.parts) {
    final pts = [_gp(p.line.$1), _gp(p.line.$2)];
    edges
      ..add(Polyline(points: pts, strokeWidth: 8, color: casing))
      ..add(Polyline(points: pts, strokeWidth: 5, color: colourOf(p.which)));
    if (p.which != GateWhich.start) {
      // The chequered finish: light squares over the edge's own colour.
      edges.add(Polyline(
        points: pts,
        strokeWidth: 5,
        color: Colors.white,
        pattern: StrokePattern.dashed(segments: const [5, 5]),
      ));
    }
  }
  return [
    PolygonLayer(
      key: const ValueKey('park-course-boxes'),
      polygons: [
        for (final p in boxes.parts)
          Polygon(
            points: [for (final q in p.box) _gp(q)],
            color: colourOf(p.which).withValues(alpha: mapZoneFillOpacity),
            borderColor: colourOf(p.which),
            borderStrokeWidth: 2,
          ),
      ],
    ),
    PolylineLayer(
        key: const ValueKey('park-course-box-edges'), polylines: edges),
    MarkerLayer(
      key: const ValueKey('park-course-box-markers'),
      markers: [
        for (final mk in boxes.markers)
          Marker(
            point: _gp(mk.at),
            width: 190,
            // A tag that is a button gets a 48 dp tall hit area around it.
            height: onTap == null ? 34 : 48,
            alignment: mk.at.lng <= centreLng
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Align(
              alignment: mk.at.lng <= centreLng
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: _BoxMarker(
                key: ValueKey('park-course-box-${mk.which?.name ?? 'both'}'),
                which: mk.which,
                label: switch (mk.which) {
                  GateWhich.start => startLabel,
                  GateWhich.finish => finishLabel,
                  null => bothLabel,
                },
                darkBasemap: darkBasemap,
                onTap: onTap == null ? null : () => onTap(mk.which),
                tapLabel: tapLabel?.call(mk.which),
              ),
            ),
          ),
      ],
    ),
  ];
}

/// A box's name tag, filled with the box's colour so it is the green or red
/// box at the whole-course zoom: a flag for the start, a chequered flag for
/// the finish, both flags (in the start colour, like the box) for a box they
/// share. Without [onTap] the map's key and the page's sentence name the
/// boxes for a screen reader, so the tag is excluded; with it the tag is a
/// button named [tapLabel] that takes the map to its box. Twin of web's box
/// tags in `RunMap`.
class _BoxMarker extends StatelessWidget {
  final GateWhich? which;
  final String label;
  final bool darkBasemap;
  final VoidCallback? onTap;
  final String? tapLabel;
  const _BoxMarker({
    super.key,
    required this.which,
    required this.label,
    required this.darkBasemap,
    this.onTap,
    this.tapLabel,
  });

  @override
  Widget build(BuildContext context) {
    final ink = mapBoxInk(darkBasemap: darkBasemap);
    final tag = ExcludeSemantics(
      child: DecoratedBox(
        // A pill on the map, not a card: a stadium shape.
        decoration: ShapeDecoration(
          color: which == GateWhich.finish
              ? mapFinishZoneColour(darkBasemap: darkBasemap)
              : mapStartZoneColour(darkBasemap: darkBasemap),
          shape: StadiumBorder(
            side: BorderSide(
              width: 2,
              color: mapOverlayOutline(darkBasemap: darkBasemap),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 10, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (which != GateWhich.finish)
                Icon(Icons.flag_outlined, size: 18, color: ink),
              if (which != GateWhich.start)
                Icon(Icons.sports_score, size: 18, color: ink),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final tap = onTap;
    // The tag has a fixed box on the map, so its text scales only so far.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: tap == null
          ? tag
          : Semantics(
              button: true,
              label: tapLabel,
              // The tap is on the excluded InkWell, so the node carries it.
              onTap: tap,
              excludeSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: tap,
                  customBorder: const StadiumBorder(),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(widthFactor: 1, child: tag),
                  ),
                ),
              ),
            ),
    );
  }
}

class _EndMarker extends StatelessWidget {
  final IconData icon;
  final Color fill;
  final Color ink;
  final Color ring;

  const _EndMarker({
    required this.icon,
    required this.fill,
    required this.ink,
    required this.ring,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 2),
        ),
        child: Center(child: Icon(icon, size: 14, color: ink)),
      );
}

class _CheckpointMarker extends StatelessWidget {
  /// The numbers it stands for: one, or several checkpoints close enough to
  /// share a marker ([checkpointMarks]).
  final String number;
  final Color fill;
  final Color ink;

  const _CheckpointMarker({
    super.key,
    required this.number,
    required this.fill,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: ink, fontWeight: FontWeight.w700);
    // A numbered dot on the map, widened to a stadium when two checkpoints
    // share it; not a status pill.
    return DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(number, style: style),
        ),
      ),
    );
  }
}

/// An out-and-back's turn: a U-turn and its name, on the label halo, where
/// the course's last checkpoint is. The key and the page's sentence name it
/// for a screen reader, so the marker is excluded.
class _TurnMarker extends StatelessWidget {
  final String label;
  final bool darkBasemap;
  const _TurnMarker({
    super.key,
    required this.label,
    required this.darkBasemap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = mapOverlayOutline(darkBasemap: darkBasemap);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ExcludeSemantics(
      child: DecoratedBox(
        // A pill on the map, not a card: a stadium shape.
        decoration: ShapeDecoration(
          color: basemapVoidColour(darkBasemap: darkBasemap),
          shape: StadiumBorder(side: BorderSide(width: 2, color: ink)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 10, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.u_turn_left, size: 18, color: ink),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  final double angle;
  const _Chevron(this.angle);

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle,
        child: const Icon(
          Icons.play_arrow,
          size: 16,
          color: chevronInk,
          shadows: chevronOutline,
        ),
      );
}

/// One park course on a basemap: its line, the direction it is run in, the
/// start and finish (one marker when they share a place) and its numbered
/// checkpoints. Pair it with [ParkCourseMapLegend], which names each mark.
/// It does not pan or pinch, because it sits inside the course page's scroll
/// view; instead the start and finish tags (one where they share a box) take
/// it to their box, and an icon button in its corner back to the whole course
/// ([courseJumps]). The key's entries jump through [ParkCourseMapState.jumpTo].
class ParkCourseMap extends StatefulWidget {
  final List<Waypoint> line;
  final List<CourseCheckpoint> checkpoints;
  final double aspectRatio;

  /// `park_courses.course_shape`: an out-and-back's last checkpoint is drawn
  /// as its turn.
  final String? shape;

  /// The stored start and finish lines, drawn as boxes in place of the
  /// start and finish pins; null draws the pins ([courseBoxGates]).
  final ({Gate start, Gate finish})? zones;

  const ParkCourseMap({
    super.key,
    required this.line,
    this.checkpoints = const [],
    this.aspectRatio = 1.5,
    this.shape,
    this.zones,
  });

  @override
  State<ParkCourseMap> createState() => ParkCourseMapState();
}

class ParkCourseMapState extends State<ParkCourseMap>
    with SingleTickerProviderStateMixin {
  final MapController _map = MapController();
  late final AnimationController _move;

  /// Where the camera is: what a widget test reads after a jump.
  @visibleForTesting
  MapCamera get camera => _map.camera;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _move.dispose();
    _map.dispose();
    super.dispose();
  }

  List<CourseJump> _jumps() => courseJumps(
        gates: widget.zones,
        line: [for (final w in widget.line) GatePoint(w.lat, w.lng)],
        endsShared: courseEndsShared(widget.line),
      );

  /// Move the map to [target], as its tags and controls do: what the map's
  /// key calls when one of its start or finish entries is tapped.
  void jumpTo(CourseJumpTarget target) {
    for (final j in _jumps()) {
      if (j.target == target) return _jumpTo(j);
    }
  }

  /// Fit the camera to [jump]'s bounds, never closer than [kCourseJumpMaxZoom]
  /// on a start or finish, and as the map opens on the whole course. Eased,
  /// or a jump when the reader has asked for less motion.
  void _jumpTo(CourseJump jump) {
    final b = jump.bounds;
    final fit = CameraFit.bounds(
      bounds: LatLngBounds(LatLng(b.south, b.west), LatLng(b.north, b.east)),
      padding: const EdgeInsets.all(28),
      maxZoom:
          jump.target == CourseJumpTarget.course ? 17 : kCourseJumpMaxZoom,
    );
    _move.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      _map.fitCamera(fit);
      return;
    }
    final from = _map.camera;
    final to = fit.fit(from);
    final curve =
        CurvedAnimation(parent: _move, curve: AppMotion.curveEmphasised);
    void step() {
      final t = curve.value;
      _map.move(
        LatLng(
          from.center.latitude + (to.center.latitude - from.center.latitude) * t,
          from.center.longitude +
              (to.center.longitude - from.center.longitude) * t,
        ),
        from.zoom + (to.zoom - from.zoom) * t,
      );
    }

    _move.addListener(step);
    _move.forward(from: 0).whenCompleteOrCancel(() {
      _move.removeListener(step);
      curve.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final checkpoints = widget.checkpoints;
    final zones = widget.zones;
    if (line.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final ends = _endPalette(darkBasemap);
    final ring = mapOverlayOutline(darkBasemap: darkBasemap);
    final pts = [for (final w in line) _ll(w)];
    final shared = courseEndsShared(line);
    final step = math.max(_lineMetres(pts) / kParkCourseChevrons, 25.0);
    final chevrons = computeChevrons(pts, stepMetres: step);
    final marks = checkpointMarks(
      checkpoints: [for (final c in checkpoints) (lat: c.lat, lng: c.lng)],
      line: [for (final w in line) (lat: w.lat, lng: w.lng)],
      shape: widget.shape,
    );
    final jumps = _jumps();
    // semantics-children: the map's credit line keeps its own node
    return Semantics(
      container: true,
      label: l10n.parksMapCourseLabel(checkpoints.length),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
                initialCameraFit: CameraFit.coordinates(
                  coordinates: pts,
                  padding: const EdgeInsets.all(28),
                  maxZoom: 17,
                ),
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                basemapTileLayer(urlTemplate: currentTileUrl(context)),
                PolylineLayer(
                  key: const ValueKey('park-course-line'),
                  polylines:
                      solidMapLine(pts, mapTrackLine(darkBasemap: darkBasemap)),
                ),
                MarkerLayer(
                  key: const ValueKey('park-course-chevrons'),
                  markers: [
                    for (final c in chevrons)
                      Marker(
                        point: c.position,
                        width: 18,
                        height: 18,
                        child: _Chevron(c.angleRadians),
                      ),
                  ],
                ),
                MarkerLayer(
                  key: const ValueKey('park-course-checkpoints'),
                  markers: [
                    for (final k in marks)
                      if (k.isTurn)
                        Marker(
                          point: LatLng(k.lat, k.lng),
                          width: 160,
                          height: 32,
                          child: Center(
                            child: _TurnMarker(
                              key: const ValueKey('park-course-turnaround'),
                              label: l10n.parksTurnAround,
                              darkBasemap: darkBasemap,
                            ),
                          ),
                        )
                      else
                        Marker(
                          point: LatLng(k.lat, k.lng),
                          width: 14.0 + 8 * k.numbers.join(',').length,
                          height: 22,
                          child: _CheckpointMarker(
                            key: ValueKey(
                                'park-course-checkpoint-${k.numbers.join('-')}'),
                            number: k.numbers.join(', '),
                            fill: ring,
                            ink: basemapVoidColour(darkBasemap: darkBasemap),
                          ),
                        ),
                  ],
                ),
                // The boxes take the start and finish pins' place.
                if (zones case final z?)
                  ...courseGateBoxLayers(
                    start: z.start,
                    finish: z.finish,
                    darkBasemap: darkBasemap,
                    startLabel: l10n.parksLegendStart,
                    finishLabel: l10n.parksLegendFinish,
                    bothLabel: l10n.parksLegendStartFinish,
                    onTap: (which) => jumpTo(switch (which) {
                      GateWhich.start => CourseJumpTarget.start,
                      GateWhich.finish => CourseJumpTarget.finish,
                      null => CourseJumpTarget.startFinish,
                    }),
                    tapLabel: (which) => switch (which) {
                      GateWhich.start => l10n.parksMapJumpStart,
                      GateWhich.finish => l10n.parksMapJumpFinish,
                      null => l10n.parksMapJumpStartFinish,
                    },
                    centreLng: (pts.map((p) => p.longitude).reduce(math.min) +
                            pts.map((p) => p.longitude).reduce(math.max)) /
                        2,
                  )
                else
                  MarkerLayer(
                    key: const ValueKey('park-course-ends'),
                    markers: [
                      if (!shared)
                        Marker(
                          point: pts.last,
                          width: 24,
                          height: 24,
                          child: _EndMarker(
                            icon: Icons.flag_outlined,
                            fill: ends.danger,
                            ink: ends.onDanger,
                            ring: ring,
                          ),
                        ),
                      Marker(
                        point: pts.first,
                        width: 24,
                        height: 24,
                        child: _EndMarker(
                          icon: shared ? Icons.flag_outlined : Icons.play_arrow,
                          fill: ends.success,
                          ink: ends.onSuccess,
                          ring: ring,
                        ),
                      ),
                    ],
                  ),
                if (jumps.isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: IconButton.filledTonal(
                        key: const ValueKey('park-course-jump-course'),
                        tooltip: l10n.parksMapJumpWholeCourse,
                        onPressed: () => jumpTo(CourseJumpTarget.course),
                        icon: const Icon(Icons.zoom_out_map),
                      ),
                    ),
                  ),
                MapAttribution(darkBasemap: darkBasemap),
              ],
            ),
          ),
      ),
    );
  }
}

/// The key under a [ParkCourseMap]: one row per kind of mark the map draws,
/// each read by a screen reader as its own item. With [onJump] the start and
/// finish rows are buttons that take the map there, each padded to a 48 dp
/// hit area without a bigger look.
class ParkCourseMapLegend extends StatelessWidget {
  final List<Waypoint> line;

  /// How many numbered checkpoint markers the map draws.
  final int checkpointCount;

  /// Whether the map marks an out-and-back's turn.
  final bool hasTurn;

  /// The lines the map draws as boxes, so the key names the boxes in place
  /// of the pins; null for none.
  final ({Gate start, Gate finish})? zones;

  /// Moves the map to a start or finish; null leaves the key as labels only.
  final void Function(CourseJumpTarget target)? onJump;

  const ParkCourseMapLegend({
    super.key,
    required this.line,
    required this.checkpointCount,
    this.hasTurn = false,
    this.zones,
    this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final ends = _endPalette(darkBasemap);
    final ring = mapOverlayOutline(darkBasemap: darkBasemap);
    final shared = courseEndsShared(line);
    Widget row(Widget mark, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: SizedBox.square(dimension: 22, child: mark),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        );
    Widget item(Key key, Widget mark, String label, [CourseJumpTarget? jump]) {
      final onJump = this.onJump;
      if (jump == null || onJump == null) {
        return MergeSemantics(key: key, child: row(mark, label));
      }
      return Semantics(
        key: key,
        button: true,
        label: switch (jump) {
          CourseJumpTarget.start => l10n.parksMapJumpStart,
          CourseJumpTarget.finish => l10n.parksMapJumpFinish,
          CourseJumpTarget.startFinish ||
          CourseJumpTarget.course =>
            l10n.parksMapJumpStartFinish,
        },
        onTap: () => onJump(jump),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onJump(jump),
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(widthFactor: 1, child: row(mark, label)),
          ),
        ),
      );
    }

    // semantics-children: a group name, read once before the controls inside it
    return Semantics(
      container: true,
      label: l10n.parksLegendTitle,
      child: Wrap(
        key: const Key('park-course-legend'),
        spacing: 16,
        runSpacing: 8,
        children: [
          // The boxes replace the pins on the map, so the key names the boxes.
          if (zones case final z?)
            if (gateBoxParts(z.start, z.finish).layout == GateBoxLayout.shared)
              item(
                const Key('park-course-legend-start-finish-box'),
                _BoxSwatch(darkBasemap: darkBasemap, which: null),
                l10n.parksLegendStartFinish,
                CourseJumpTarget.startFinish,
              )
            else ...[
              item(
                const Key('park-course-legend-start-box'),
                _BoxSwatch(darkBasemap: darkBasemap, which: GateWhich.start),
                l10n.parksLegendStart,
                CourseJumpTarget.start,
              ),
              item(
                const Key('park-course-legend-finish-box'),
                _BoxSwatch(darkBasemap: darkBasemap, which: GateWhich.finish),
                l10n.parksLegendFinish,
                CourseJumpTarget.finish,
              ),
            ]
          else if (shared)
            item(
              const Key('park-course-legend-start-finish'),
              _EndMarker(
                icon: Icons.flag_outlined,
                fill: ends.success,
                ink: ends.onSuccess,
                ring: ring,
              ),
              l10n.parksLegendStartFinish,
              CourseJumpTarget.startFinish,
            )
          else ...[
            item(
              const Key('park-course-legend-start'),
              _EndMarker(
                icon: Icons.play_arrow,
                fill: ends.success,
                ink: ends.onSuccess,
                ring: ring,
              ),
              l10n.parksLegendStart,
              CourseJumpTarget.start,
            ),
            item(
              const Key('park-course-legend-finish'),
              _EndMarker(
                icon: Icons.flag_outlined,
                fill: ends.danger,
                ink: ends.onDanger,
                ring: ring,
              ),
              l10n.parksLegendFinish,
              CourseJumpTarget.finish,
            ),
          ],
          if (checkpointCount > 0)
            item(
              const Key('park-course-legend-checkpoints'),
              _CheckpointMarker(
                number: '1',
                fill: ring,
                ink: basemapVoidColour(darkBasemap: darkBasemap),
              ),
              l10n.parksLegendCheckpoints,
            ),
          if (hasTurn)
            item(
              const Key('park-course-legend-turnaround'),
              Center(
                child: Icon(Icons.u_turn_left,
                    size: 18, color: mapOverlayOutline(darkBasemap: darkBasemap)),
              ),
              l10n.parksLegendTurnAround,
            ),
          item(
            const Key('park-course-legend-direction'),
            const Center(child: _Chevron(0)),
            l10n.parksLegendDirection,
          ),
        ],
      ),
    );
  }
}

/// A box as the map draws it, for the key: the fill, its outline and its
/// cased timing line, solid for the start, chequered for the finish, and for
/// a box the start and finish share ([which] null) the start colour with a
/// chequered line across its middle.
class _BoxSwatch extends StatelessWidget {
  final bool darkBasemap;
  final GateWhich? which;
  const _BoxSwatch({required this.darkBasemap, required this.which});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BoxSwatchPainter(
      colour: which == GateWhich.finish
          ? mapFinishZoneColour(darkBasemap: darkBasemap)
          : mapStartZoneColour(darkBasemap: darkBasemap),
      chequered: which != GateWhich.start,
      centred: which == null,
      casing: mapOverlayOutline(darkBasemap: darkBasemap),
    ),
  );
}

class _BoxSwatchPainter extends CustomPainter {
  final Color colour;
  final bool chequered;
  final bool centred;
  final Color casing;
  const _BoxSwatchPainter({
    required this.colour,
    required this.chequered,
    required this.centred,
    required this.casing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height * 0.2;
    final bottom = size.height * 0.8;
    final edge = centred ? (top + bottom) / 2 : top;
    final band = Rect.fromLTRB(0, top, size.width, bottom);
    canvas
      ..drawRect(
        band,
        Paint()..color = colour.withValues(alpha: mapZoneFillOpacity),
      )
      ..drawRect(
        band,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      )
      ..drawLine(
        Offset(band.left, edge),
        Offset(band.right, edge),
        Paint()
          ..color = casing
          ..strokeWidth = 4,
      )
      ..drawLine(
        Offset(band.left, edge),
        Offset(band.right, edge),
        Paint()
          ..color = colour
          ..strokeWidth = 2.5,
      );
    if (chequered) {
      final white = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5;
      for (var x = band.left + 2.5; x < band.right; x += 5) {
        canvas.drawLine(
          Offset(x, edge),
          Offset((x + 2.5).clamp(0, band.right), edge),
          white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BoxSwatchPainter old) =>
      old.colour != colour ||
      old.chequered != chequered ||
      old.centred != centred ||
      old.casing != casing;
}

/// Every course line in one park over a basemap, each in its own colour
/// ([parkCourseLineColour], in the order given), with a start marker at each
/// distinct start. Static, for the park page header and the parks index card.
class ParkOverviewMap extends StatelessWidget {
  final List<List<Waypoint>> lines;
  final double aspectRatio;
  final bool showStarts;

  const ParkOverviewMap({
    super.key,
    required this.lines,
    this.aspectRatio = 1.6,
    this.showStarts = true,
  });

  @override
  Widget build(BuildContext context) {
    final drawn = [
      for (final l in lines)
        if (l.length >= 2) l,
    ];
    if (drawn.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final ends = _endPalette(darkBasemap);
    final ring = mapOverlayOutline(darkBasemap: darkBasemap);
    final starts = <Waypoint>[];
    for (final l in drawn) {
      final s = l.first;
      final near = starts.any((o) =>
          haversineMetres(o.lat, o.lng, s.lat, s.lng) <= kParkStartMergeM);
      if (!near) starts.add(s);
    }
    final all = [
      for (final l in drawn)
        for (final w in l) _ll(w),
    ];
    // semantics-children: the map's credit line keeps its own node
    return Semantics(
      container: true,
      label: l10n.parksMapParkLabel(drawn.length),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: FlutterMap(
              options: MapOptions(
                backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
                initialCameraFit: CameraFit.coordinates(
                  coordinates: all,
                  padding: const EdgeInsets.all(20),
                  maxZoom: 16,
                ),
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                basemapTileLayer(urlTemplate: currentTileUrl(context)),
                PolylineLayer(
                  key: const ValueKey('park-overview-lines'),
                  polylines: [
                    for (var i = drawn.length - 1; i >= 0; i--)
                      ...solidMapLine(
                        [for (final w in drawn[i]) _ll(w)],
                        parkCourseLineColour(i, darkBasemap: darkBasemap),
                      ),
                  ],
                ),
                if (showStarts)
                  MarkerLayer(
                    key: const ValueKey('park-overview-starts'),
                    markers: [
                      for (final s in starts)
                        Marker(
                          point: _ll(s),
                          width: 24,
                          height: 24,
                          child: _EndMarker(
                            icon: Icons.play_arrow,
                            fill: ends.success,
                            ink: ends.onSuccess,
                            ring: ring,
                          ),
                        ),
                    ],
                  ),
                MapAttribution(darkBasemap: darkBasemap),
              ],
            ),
          ),
      ),
    );
  }
}

/// One park on the parks map (decisions § 2612): where `parkMarkerPoint`
/// puts it, its name and how many courses it has.
@immutable
class ParkMapPin {
  final String id;
  final String name;
  final int courseCount;
  final ParkMapPoint point;

  const ParkMapPin({
    required this.id,
    required this.name,
    required this.courseCount,
    required this.point,
  });
}

/// Every park on one map: a pill per park with its course count in a green
/// circle and its name, which opens the park. Frames the pins until the
/// reader moves the map, and reports every settled view so the page can count
/// the parks in it.
class ParksMap extends StatefulWidget {
  final List<ParkMapPin> pins;
  final ValueChanged<String> onOpen;
  final ValueChanged<ParkMapBounds>? onView;

  const ParksMap({
    super.key,
    required this.pins,
    required this.onOpen,
    this.onView,
  });

  @override
  State<ParksMap> createState() => ParksMapState();
}

class ParksMapState extends State<ParksMap> {
  final MapController _map = MapController();
  bool _ready = false;
  bool _readerMoved = false;

  /// Centres the map on a place the reader asked for (Near me).
  void showPlace(ParkMapPoint point) {
    if (!_ready) return;
    _readerMoved = true;
    _map.move(LatLng(point.lat, point.lng), 9);
    _report();
  }

  @override
  void didUpdateWidget(ParksMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && !_samePins(oldWidget.pins, widget.pins)) {
      if (!_readerMoved) _frame();
      _report();
    }
  }

  static bool _samePins(List<ParkMapPin> a, List<ParkMapPin> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].point != b[i].point) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _frame() {
    final pins = widget.pins;
    if (pins.isEmpty) return;
    if (pins.length == 1) {
      _map.move(LatLng(pins.first.point.lat, pins.first.point.lng), 10);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [for (final p in pins) LatLng(p.point.lat, p.point.lng)],
        padding: const EdgeInsets.all(56),
        maxZoom: 12,
      ),
    );
  }

  /// Reports the view after the frame: a camera change can land inside a
  /// build (new pins arriving), where the page may not set its state.
  void _report() {
    if (widget.onView == null || !_ready) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final onView = widget.onView;
      if (!mounted || onView == null) return;
      final b = _map.camera.visibleBounds;
      onView((south: b.south, west: b.west, north: b.north, east: b.east));
    });
  }

  /// Zooms to the parks of one crowded group until their pills part.
  void _openGroup(List<ParkMapPin> group) {
    if (!_ready) return;
    _readerMoved = true;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [for (final p in group) LatLng(p.point.lat, p.point.lng)],
        padding: const EdgeInsets.all(72),
        maxZoom: _kParkPinsUngroupZoom,
      ),
    );
    _report();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    // semantics-children: each pin is its own button inside the map's name
    return Semantics(
      container: true,
      label: l10n.parksMapLabel,
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
          initialCenter: const LatLng(38, -78),
          initialZoom: 5,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: () {
            _ready = true;
            _frame();
            _report();
          },
          onPositionChanged: (_, hasGesture) {
            if (hasGesture) _readerMoved = true;
          },
          onMapEvent: (e) {
            if (e is MapEventMoveEnd ||
                e is MapEventFlingAnimationEnd ||
                e is MapEventDoubleTapZoomEnd ||
                e is MapEventScrollWheelZoom) {
              _report();
            }
          },
        ),
        children: [
          basemapTileLayer(urlTemplate: currentTileUrl(context)),
          _ParkPinsLayer(
            pins: widget.pins,
            onOpen: widget.onOpen,
            onOpenGroup: _openGroup,
          ),
        ],
      ),
    );
  }
}

/// From this zoom up every park gets its own pill, even two on one spot: a
/// crowded group's tap zooms to here at most, so it always parts.
const double _kParkPinsUngroupZoom = 14;

/// The screen box one park pill may take, its marker at the bottom centre:
/// the marker's width, and two lines of name.
const double _kParkPinWidth = 200;
const double _kParkPinHeight = 60;

/// The parks' pins at the map's current zoom: a pill per park where it has
/// room, and where pills would overlap, one "N parks" pill for the crowd
/// that zooms in on it ([groupOverlapping]). Parks with more courses are
/// placed first, so they keep their own pill. Rebuilds with the camera.
class _ParkPinsLayer extends StatelessWidget {
  final List<ParkMapPin> pins;
  final ValueChanged<String> onOpen;
  final ValueChanged<List<ParkMapPin>> onOpenGroup;

  const _ParkPinsLayer({
    required this.pins,
    required this.onOpen,
    required this.onOpenGroup,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final ordered = [...pins]..sort((a, b) {
        final byCount = b.courseCount.compareTo(a.courseCount);
        return byCount != 0 ? byCount : a.name.compareTo(b.name);
      });
    final groups = camera.zoom >= _kParkPinsUngroupZoom
        ? [
            for (var i = 0; i < ordered.length; i++) [i],
          ]
        : groupOverlapping(
            [
              for (final p in ordered)
                if (camera.projectAtZoom(LatLng(p.point.lat, p.point.lng))
                    case final o)
                  (x: o.dx, y: o.dy),
            ],
            width: _kParkPinWidth,
            height: _kParkPinHeight,
          );
    return MarkerLayer(
      key: const ValueKey('parks-map-pins'),
      markers: [
        for (final g in groups)
          if (g.length == 1)
            Marker(
              point: LatLng(ordered[g.first].point.lat, ordered[g.first].point.lng),
              width: _kParkPinWidth,
              height: 76,
              alignment: Alignment.topCenter,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _ParkPinChip(
                  key: ValueKey('parks-map-pin-${ordered[g.first].id}'),
                  pin: ordered[g.first],
                  onTap: () => onOpen(ordered[g.first].id),
                ),
              ),
            )
          else
            () {
              final members = [for (final i in g) ordered[i]];
              final lat = members.fold<double>(0, (s, p) => s + p.point.lat) /
                  members.length;
              final lng = members.fold<double>(0, (s, p) => s + p.point.lng) /
                  members.length;
              return Marker(
                point: LatLng(lat, lng),
                width: _kParkPinWidth,
                height: 76,
                alignment: Alignment.topCenter,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _ParkGroupChip(
                    key: ValueKey('parks-map-group-${members.first.id}'),
                    count: members.length,
                    onTap: () => onOpenGroup(members),
                  ),
                ),
              );
            }(),
      ],
    );
  }
}

/// A crowd of parks too close to label at this zoom: "N parks", which zooms
/// in on them.
class _ParkGroupChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ParkGroupChip({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onPrimaryContainer,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        button: true,
        label: l10n.parksMapGroupLabel(count),
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: theme.colorScheme.primaryContainer,
          elevation: 2,
          shape: StadiumBorder(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 14, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.zoom_in,
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(l10n.parksMapGroup(count), style: text),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParkPinChip extends StatelessWidget {
  final ParkMapPin pin;
  final VoidCallback onTap;

  const _ParkPinChip({super.key, required this.pin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final text = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    // The pill has a fixed box on the map, so its text scales only so far;
    // the list one tap away carries every name in full at any size.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        button: true,
        label: l10n.parksMapMarkerLabel(
          pin.name,
          l10n.parksCourseCount(pin.courseCount),
        ),
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 2,
          shape: StadiumBorder(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: semantic.success,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        '${pin.courseCount}',
                        style: text?.copyWith(color: semantic.onSuccess),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        pin.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every course of one park on a map, each in its own colour
/// ([parkCourseLineColour], which the course cards' strips repeat), with each
/// distinct start marked (decisions § 2612). A tap on a line picks its course
/// ([onSelect]); a picked course is drawn wide over the others faded, framed,
/// and its start says "Start here".
class ParkCoursesOverviewMap extends StatefulWidget {
  final List<List<Waypoint>> lines;
  final int? selected;
  final ({double lat, double lng})? selectedStart;
  final ValueChanged<int>? onSelect;

  const ParkCoursesOverviewMap({
    super.key,
    required this.lines,
    this.selected,
    this.selectedStart,
    this.onSelect,
  });

  @override
  State<ParkCoursesOverviewMap> createState() => _ParkCoursesOverviewMapState();
}

class _ParkCoursesOverviewMapState extends State<ParkCoursesOverviewMap> {
  final MapController _map = MapController();
  final LayerHitNotifier<int> _hits = ValueNotifier(null);
  bool _ready = false;

  @override
  void didUpdateWidget(ParkCoursesOverviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && oldWidget.selected != widget.selected) _frame();
  }

  @override
  void dispose() {
    _hits.dispose();
    _map.dispose();
    super.dispose();
  }

  List<LatLng> _framed() {
    final s = widget.selected;
    final lines = s != null && s >= 0 && s < widget.lines.length
        ? [widget.lines[s]]
        : widget.lines;
    return [
      for (final l in lines)
        for (final w in l) _ll(w),
    ];
  }

  void _frame() {
    final pts = _framed();
    if (pts.isEmpty) return;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: pts,
        padding: const EdgeInsets.all(28),
        maxZoom: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final darkBasemap = currentBasemapIsDark(context);
    final ends = _endPalette(darkBasemap);
    final ring = mapOverlayOutline(darkBasemap: darkBasemap);
    final lines = widget.lines;
    final drawn = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].length >= 2) i,
    ];
    if (drawn.isEmpty) return const SizedBox.shrink();
    final selected = widget.selected;
    final starts = <Waypoint>[];
    for (final i in drawn) {
      final s = lines[i].first;
      final near = starts.any((o) =>
          haversineMetres(o.lat, o.lng, s.lat, s.lng) <= kParkStartMergeM);
      if (!near) starts.add(s);
    }
    final start = widget.selectedStart;
    final onSelect = widget.onSelect;
    // semantics-children: the map's credit line keeps its own node
    return Semantics(
      container: true,
      label: l10n.parksMapParkLabel(drawn.length),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            backgroundColor: basemapVoidColour(darkBasemap: darkBasemap),
            initialCameraFit: CameraFit.coordinates(
              coordinates: _framed(),
              padding: const EdgeInsets.all(28),
              maxZoom: 16,
            ),
            // The page scrolls past the map with one finger; the map moves
            // only to frame the course the reader picked.
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
            onMapReady: () => _ready = true,
          ),
          children: [
            basemapTileLayer(urlTemplate: currentTileUrl(context)),
            PolylineLayer(
              key: const ValueKey('park-overview-lines'),
              polylines: [
                for (final i in drawn.reversed)
                  if (i != selected)
                    ...solidMapLine(
                      [for (final w in lines[i]) _ll(w)],
                      parkCourseLineColour(i, darkBasemap: darkBasemap)
                          .withValues(alpha: selected == null ? 1 : 0.3),
                    ),
                if (selected != null && drawn.contains(selected)) ...[
                  Polyline(
                    points: [for (final w in lines[selected]) _ll(w)],
                    strokeWidth: 11,
                    color: ring,
                  ),
                  Polyline(
                    points: [for (final w in lines[selected]) _ll(w)],
                    strokeWidth: 7,
                    color: parkCourseLineColour(
                      selected,
                      darkBasemap: darkBasemap,
                    ),
                  ),
                ],
              ],
            ),
            if (onSelect != null)
              GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onTap: () {
                  final hit = _hits.value?.hitValues;
                  if (hit != null && hit.isNotEmpty) onSelect(hit.first);
                },
                child: PolylineLayer<int>(
                  key: const ValueKey('park-overview-hits'),
                  hitNotifier: _hits,
                  minimumHitbox: 14,
                  polylines: [
                    for (final i in drawn)
                      Polyline<int>(
                        points: [for (final w in lines[i]) _ll(w)],
                        strokeWidth: 4,
                        color: Colors.transparent,
                        hitValue: i,
                      ),
                  ],
                ),
              ),
            if (selected == null)
              MarkerLayer(
                key: const ValueKey('park-overview-starts'),
                markers: [
                  for (final s in starts)
                    Marker(
                      point: _ll(s),
                      width: 24,
                      height: 24,
                      child: _EndMarker(
                        icon: Icons.play_arrow,
                        fill: ends.success,
                        ink: ends.onSuccess,
                        ring: ring,
                      ),
                    ),
                ],
              )
            else if (start != null)
              MarkerLayer(
                key: const ValueKey('park-overview-start-here'),
                markers: [
                  Marker(
                    point: LatLng(start.lat, start.lng),
                    width: 180,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _StartHereTag(darkBasemap: darkBasemap),
                    ),
                  ),
                ],
              ),
            MapAttribution(darkBasemap: darkBasemap),
          ],
        ),
      ),
    );
  }
}

class _StartHereTag extends StatelessWidget {
  final bool darkBasemap;
  const _StartHereTag({required this.darkBasemap});

  @override
  Widget build(BuildContext context) {
    final ink = mapBoxInk(darkBasemap: darkBasemap);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: mapStartZoneColour(darkBasemap: darkBasemap),
          shape: StadiumBorder(
            side: BorderSide(
              width: 2,
              color: mapOverlayOutline(darkBasemap: darkBasemap),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 10, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_outlined, size: 18, color: ink),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  AppLocalizations.of(context).parksStartHere,
                  key: const Key('park-overview-start-here-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
