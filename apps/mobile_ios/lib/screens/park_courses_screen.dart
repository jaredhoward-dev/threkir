import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppBarAction,
        AppInsets,
        AppRadius,
        AppSemanticColors,
        ChoiceChipOption,
        ChoiceChipRow,
        EmptyState,
        IdentityAvatar,
        DetailHero,
        DetailPage,
        DetailParentChip,
        ListCard,
        ListSkeleton,
        SectionHeader,
        StatGrid,
        StatTile,
        StatusPill,
        StatusPillSize,
        TextLane;
import 'package:url_launcher/url_launcher.dart';

import '../adaptive_width.dart';
import '../auth_error.dart';
import '../backend_timeout.dart';
import '../elevation_profile.dart' show elevationSeries;
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../main.dart' show pendingArmRunWithRoute;
import '../park_course_distance.dart';
import '../park_courses.dart';
import '../preferences.dart';
import '../route_guide.dart';
import '../route_surface_label.dart';
import '../share_sheet.dart';
import '../watch_park_courses.dart' show WatchParkCourses;
import '../widgets/course_ends_card.dart';
import '../widgets/elevation_chart.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart' show currentBasemapIsDark;
import 'help_screen.dart' show openGuide;
import 'public_route_screen.dart';
import 'run_screen.dart' show runRecordingActive;
import '../widgets/head_to_head_card.dart' show showHeadToHeadSheet;
import '../widgets/park_course_map.dart';
import '../widgets/park_course_report_sheet.dart';
import '../widgets/segments_panel.dart' show SegmentTierFilters;
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import '../widgets/old_match_note.dart';

/// One park as a card that opens it: its course lines, agency, and how many
/// courses at what distances. Shared by the park index and the Courses view
/// of Races & courses.
class ParkCard extends StatelessWidget {
  final ParkListing listing;

  /// Null while the course read is out or after it failed.
  final List<ParkCourseListing>? courses;
  final VoidCallback onTap;

  const ParkCard({
    super.key,
    required this.listing,
    required this.courses,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final park = listing.park;
    final sorted = courses == null ? null : sortedParkCourses(courses!);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final range = sorted == null
        ? null
        : courseDistanceRange(
            [for (final c in sorted) c.segment.distanceM],
            activeDistanceUnit,
          );
    final summary = sorted == null || sorted.isEmpty
        ? null
        : [l10n.parksCourseCount(sorted.length), ?range].join(' · ');
    return ListCard.flush(
      onTap: onTap,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sorted != null && sorted.isNotEmpty)
              ParkOverviewMap(
                lines: [
                  for (final c in sorted)
                    ApiClient.globalSegmentGeometry(c.segment),
                ],
                aspectRatio: 2.4,
                showStarts: false,
              ),
            Padding(
              padding: AppInsets.cardDense,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(park.name, style: theme.textTheme.titleMedium),
                        Text(parkTypeLabel(l10n, park.kind, park.agency), style: muted),
                        if (summary != null)
                          Text(
                            summary,
                            key: ValueKey('parks-park-summary-${park.id}'),
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

/// A park's name as a link to its screen, set apart from whatever card it
/// sits on: a tap target of its own, named as the park's page for a screen
/// reader, with the visible text first in that name.
class ParkNameLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const ParkNameLink({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      link: true,
      label: l10n.racesAnyTimeParkLink(label),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A park's courses in list order (shortest first, closed last).
List<ParkCourseListing> sortedParkCourses(List<ParkCourseListing> courses) =>
    sortParkCourses(
      courses,
      (c) => ParkCourseSortKey(
        distanceM: c.segment.distanceM,
        name: c.segment.name,
        slug: c.course.slug,
        status: c.course.status,
      ),
    );

/// A course distance as a course reads it: "5 km", "21.1 km", "3.1 mi".
String courseDistanceForPref(double metres) =>
    courseDistanceLabel(metres, activeDistanceUnit) ??
    formatDistanceForPref(metres);

/// What a park card and page call the place: "Trail" for a trail whoever
/// runs it, else the agency's label. Mirrors web `parkTypeKey`.
String parkTypeLabel(AppLocalizations l10n, String kind, String agency) =>
    switch (kind) {
      'trail' => l10n.parksKindTrail,
      _ => agencyLabel(l10n, agency),
    };

String agencyLabel(AppLocalizations l10n, String agency) => switch (agency) {
  'nps' => l10n.parksAgencyNps,
  'state' => l10n.parksAgencyState,
  'county' => l10n.parksAgencyCounty,
  'usfs' => l10n.parksAgencyUsfs,
  'usfws' => l10n.parksAgencyUsfws,
  _ => l10n.parksAgencyOther,
};

String courseShapeLabel(AppLocalizations l10n, String shape) => switch (shape) {
  'loop' => l10n.parksShapeLoop,
  'out_and_back' => l10n.parksShapeOutAndBack,
  'point_to_point' => l10n.parksShapePointToPoint,
  _ => shape,
};

String courseStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'open' => l10n.parksStatusOpen,
      'closed' => l10n.parksStatusClosed,
      'seasonal' => l10n.parksStatusSeasonal,
      _ => status,
    };

/// The give-way note for a course whose paths an organised group regularly
/// uses (`park_courses.shared_use`, decisions § 2460). It names no one.
String? sharedUseNotice(AppLocalizations l10n, String? sharedUse) =>
    switch (sharedUse) {
      'saturday_morning_group' => l10n.parksSharedUseSaturdayMorningGroup,
      _ => null,
    };

String? courseDifficultyLabel(AppLocalizations l10n, String? difficulty) =>
    switch (difficulty) {
      'easy' => l10n.parksDifficultyEasy,
      'moderate' => l10n.parksDifficultyModerate,
      'hard' => l10n.parksDifficultyHard,
      _ => null,
    };

String geometryAttribution(AppLocalizations l10n, String source) =>
    switch (source) {
      'osm' => l10n.parksAttributionOsm,
      'nps' => l10n.parksAttributionNps,
      'agency' => l10n.parksAttributionAgency,
      _ => l10n.parksAttributionTraced,
    };

/// The one credit line a course carries: the catalogue's own credit when it
/// has one, else the label for where its line came from.
String courseCredit(AppLocalizations l10n, ParkCourseRow course) {
  final own = course.attribution?.trim();
  return own != null && own.isNotEmpty
      ? own
      : geometryAttribution(l10n, course.geometrySource);
}

/// A course's status as a pill, or null for an open course.
Widget? courseStatusPill(BuildContext context, String status) {
  if (status == 'open') return null;
  final l10n = AppLocalizations.of(context);
  final semantic = AppSemanticColors.of(context);
  final colour = status == 'closed' ? semantic.danger : semantic.warning;
  return StatusPill(
    label: courseStatusLabel(l10n, status),
    foreground: colour,
    outline: colour,
    size: StatusPillSize.compact,
  );
}

/// A neutral fact about a course (laps, shape, climb, difficulty) as a pill.
Widget courseFactPill(BuildContext context, String label, {Key? key}) {
  final scheme = Theme.of(context).colorScheme;
  return StatusPill(
    key: key,
    label: label,
    foreground: scheme.onSurfaceVariant,
    fill: scheme.surfaceContainerHighest,
    size: StatusPillSize.compact,
  );
}

/// The pills a course carries beside its distance: laps when there is more
/// than one, the shape only when it is not a loop, the climb, the difficulty
/// and a status that is not open.
List<Widget> courseFactPills(
  BuildContext context,
  ParkCourseListing c, {
  bool includeClimb = true,
}) {
  final l10n = AppLocalizations.of(context);
  final course = c.course;
  final laps = courseLapsChip(course.laps);
  final climb = c.segment.elevationM;
  final difficulty = courseDifficultyLabel(l10n, course.difficulty);
  return [
    if (laps != null)
      courseFactPill(
        context,
        l10n.parksCourseLaps(laps),
        key: ValueKey('park-course-laps-${course.id}'),
      ),
    if (courseShapeShown(course.courseShape))
      courseFactPill(context, courseShapeLabel(l10n, course.courseShape)),
    if (includeClimb && climb != null && climb > 0)
      courseFactPill(
        context,
        l10n.parksCourseClimb(formatElevationForPref(climb)),
      ),
    if (difficulty != null) courseFactPill(context, difficulty),
    ?courseStatusPill(context, course.status),
  ];
}

String? _recordLine(AppLocalizations l10n, ParkCourseRecord? r) {
  if (r == null) return null;
  final name = r.displayName?.trim();
  return name != null && name.isNotEmpty
      ? l10n.racesAnyTimeFastestBy(
          '${r.season}', formatEffortTime(r.timeSeconds), name)
      : l10n.racesAnyTimeFastest('${r.season}', formatEffortTime(r.timeSeconds));
}

String? _monthRunnersLine(AppLocalizations l10n, int? runners) =>
    runners == null || runners <= 0 ? null : l10n.parksMonthRunners(runners);

Future<void> _openParkWebsite(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('park website: launch failed for $url: $e');
  }
  if (!ok && context.mounted) {
    showTopBanner(context, l10n.parksWebsiteOpenFailed);
  }
}

/// Loads a park course into the recorder, ready for the runner to press
/// Start at the start line: Run this course, from the course page and from
/// the park page's picked course (decisions § 2604, § 2612). It doesn't start
/// the run: this is pressed while browsing, often from home. [busy] says
/// when the read is out, for the button's spinner.
Future<void> loadParkCourseIntoRecorder(
  BuildContext context, {
  required ApiClient api,
  required ParkCourseListing course,
  required String routeId,
  required ValueChanged<bool> busy,
}) async {
  final l10n = AppLocalizations.of(context);
  // The recorder takes a new route only while idle, so mid-run this would
  // land on the live recorder with the old one and look like it worked.
  if (runRecordingActive.value) {
    showTopBanner(context, l10n.parksRunThisCourseRecording);
    return;
  }
  busy(true);
  try {
    final viewable = await loadViewableRoute(api, routeId);
    final route = viewable.route;
    if (route == null || viewable.waypoints.length < 2) {
      throw StateError('course route $routeId has no line to follow');
    }
    if (!context.mounted) return;
    // The course goes to the wrist too, so a watch-recorded run is timed
    // live there. Fire-and-forget, and only once the phone has it as well.
    unawaited(WatchParkCourses().courseNavigated(course));
    pendingArmRunWithRoute.value =
        publicRouteStartTarget(route, viewable.waypoints);
  } catch (e) {
    debugPrint('park course run load failed: $e');
    if (!context.mounted) return;
    showTopBanner(
      context,
      l10n.parksRunThisCourseFailed,
      actionLabel: l10n.errorStateRetry,
      onAction: () => loadParkCourseIntoRecorder(
        context,
        api: api,
        course: course,
        routeId: routeId,
        busy: busy,
      ),
    );
  } finally {
    busy(false);
  }
}

/// One park, map first (decisions § 2612): its name once, a map of about two
/// fifths of the screen with every course in its own colour, then roomy
/// course cards whose strip repeats that colour, each with the course's whole
/// name, its distance, climb and surface, this season's fastest time and this
/// month's runners. A card or a line picks its course: the map draws it over
/// the others faded with "Start here" at its start, and a card pinned under
/// the page offers Run this course and Board. The description, the website
/// and the notices fold into About this park at the end. Mobile mirror of web
/// `/parks/[region]/[park]`.
class ParkScreen extends StatefulWidget {
  final ApiClient? api;
  final ParkListing listing;

  const ParkScreen({super.key, required this.api, required this.listing});

  @override
  State<ParkScreen> createState() => _ParkScreenState();
}

class _ParkScreenState extends State<ParkScreen> {
  List<ParkCourseListing> _courses = const [];
  bool _loading = true;
  bool _error = false;
  Map<String, ParkCourseRecord> _records = const {};
  bool _recordsLoaded = false;
  bool _recordsFailed = false;
  // How many ran each course this month where the park is: an auxiliary read
  // of its own, like the records. A course nobody ran has no entry and no line.
  Map<String, int> _monthRunners = const {};
  bool _monthRunnersFailed = false;

  /// The picked course's index in [_courses]; null for the plain park map.
  int? _picked;
  bool _loadingRun = false;
  final _mapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    _loadRecords();
    _loadMonthRunners();
  }

  Future<void> _loadMonthRunners() async {
    final api = widget.api;
    if (api == null || api.userId == null) return;
    setState(() => _monthRunnersFailed = false);
    try {
      final counts = await api
          .fetchParkCourseMonthRunners(widget.listing.park.id)
          .timeout(kBackendLoadTimeout);
      if (mounted) setState(() => _monthRunners = counts);
    } catch (e) {
      debugPrint('park page: month runners read failed: $e');
      if (mounted) setState(() => _monthRunnersFailed = true);
    }
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
      final courses = await api
          .fetchParkCourses(widget.listing.park.id)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _courses = sortedParkCourses(courses);
        _picked = null;
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

  Future<void> _loadRecords() async {
    // The board behind the records refuses an anonymous caller, so a
    // signed-out reader gets the courses without the line, not a failure.
    final api = widget.api;
    if (api == null || api.userId == null) return;
    setState(() => _recordsFailed = false);
    try {
      final records =
          await api.fetchParkCourseRecords().timeout(kBackendLoadTimeout);
      if (mounted) {
        setState(() {
          _records = records;
          _recordsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('park page: course records read failed: $e');
      if (mounted) setState(() => _recordsFailed = true);
    }
  }

  void _openBoard(ParkCourseListing c) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParkCourseScreen(
            api: widget.api,
            listing: widget.listing,
            course: c,
            fromPark: true,
          ),
        ),
      );

  /// Picks a course from its card or its line, and brings the map into view
  /// so the highlighted line is seen; the pinned card keeps the name in sight.
  void _pick(int index) {
    setState(() => _picked = index);
    final map = _mapKey.currentContext;
    if (map != null) {
      Scrollable.ensureVisible(
        map,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  String? _record(AppLocalizations l10n, ParkCourseListing c) =>
      widget.api?.userId != null && !_recordsFailed
          ? _recordLine(l10n, _records[c.course.id])
          : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final park = widget.listing.park;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final signedIn = widget.api?.userId != null;
    final names = courseDisplayNames([
      for (final c in _courses) c.segment.name,
    ], park.name);
    final darkBasemap = currentBasemapIsDark(context);
    final picked = _picked;
    final pickedCourse =
        picked != null && picked < _courses.length ? _courses[picked] : null;
    final mapHeight =
        (MediaQuery.sizeOf(context).height * 0.4).clamp(220.0, 460.0);
    if (_loading) {
      return DetailPage.placeholder(
        title: park.name,
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [ListSkeleton.section(label: l10n.parksLoading, rows: 3)],
        ),
      );
    }
    if (_error) {
      return DetailPage.placeholder(
        title: park.name,
        child: AppErrorState(message: l10n.parksLoadFailed, onRetry: _load),
      );
    }
    return DetailPage(
      title: park.name,
      bottomBar: pickedCourse == null
          ? null
          : _PickedCourseCard(
              key: const Key('park-picked-course'),
              course: pickedCourse,
              title: names[picked!],
              colour: parkCourseLineColour(picked, darkBasemap: darkBasemap),
              recordLine: _record(l10n, pickedCourse),
              api: widget.api,
              loadingRun: _loadingRun,
              onRun: (api, routeId) => loadParkCourseIntoRecorder(
                context,
                api: api,
                course: pickedCourse,
                routeId: routeId,
                busy: (v) {
                  if (mounted) setState(() => _loadingRun = v);
                },
              ),
              onBoard: () => _openBoard(pickedCourse),
              onClose: () => setState(() => _picked = null),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          contentColumn(
            context,
            maxWidth: 960,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailHero(
                  title: park.name,
                  padding: const EdgeInsets.only(bottom: 12),
                  meta: [
                    Text(
                      '${regionName(park.regionCode)} · '
                      '${parkTypeLabel(l10n, park.kind, park.agency)}',
                      key: const Key('park-header-meta'),
                      style: muted,
                    ),
                  ],
                ),
                if (_courses.isEmpty)
                  Text(l10n.parksNoCourses)
                else ...[
                  SizedBox(
                    key: _mapKey,
                    height: mapHeight,
                    child: ParkCoursesOverviewMap(
                      key: const Key('park-overview-map'),
                      lines: [
                        for (final c in _courses)
                          ApiClient.globalSegmentGeometry(c.segment),
                      ],
                      selected: picked,
                      selectedStart: pickedCourse == null
                          ? null
                          : _startOf(pickedCourse),
                      onSelect: _pick,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 4),
                    child: SectionHeader.title(
                      label: l10n.parksCourseCount(_courses.length),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(l10n.parksPreviewHint, style: muted),
                  ),
                  for (var i = 0; i < _courses.length; i++)
                    _ParkCourseCard(
                      key: ValueKey('park-course-${_courses[i].course.id}'),
                      course: _courses[i],
                      colour: parkCourseLineColour(i, darkBasemap: darkBasemap),
                      picked: picked == i,
                      recordLine: _record(l10n, _courses[i]),
                      monthRunnersLine: _monthRunnersLine(
                        l10n,
                        _monthRunners[_courses[i].course.id],
                      ),
                      title: names[i],
                      onTap: () => _pick(i),
                    ),
                  // Below the cards, so a line that arrives late never moves
                  // a card under a finger about to tap it. One line for the
                  // park rather than "no time yet" on every card.
                  if (signedIn &&
                      _recordsLoaded &&
                      !_recordsFailed &&
                      !_courses.any((c) => _records.containsKey(c.course.id)))
                    Padding(
                      key: const Key('park-no-times-yet'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(l10n.parksNoTimesYet, style: muted),
                    ),
                  if (_recordsFailed)
                    Padding(
                      key: const Key('park-records-failed'),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(l10n.racesAnyTimeFastestFailed),
                          OutlinedButton.icon(
                            onPressed: _loadRecords,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.parksRetry),
                          ),
                        ],
                      ),
                    ),
                  if (_monthRunnersFailed)
                    Padding(
                      key: const Key('park-month-runners-failed'),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(l10n.parksMonthRunnersFailed),
                          OutlinedButton.icon(
                            onPressed: _loadMonthRunners,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.parksRetry),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                _AboutPark(listing: widget.listing),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({double lat, double lng})? _startOf(ParkCourseListing c) {
    final line = ApiClient.globalSegmentGeometry(c.segment);
    return courseEnds(
      line: [for (final w in line) (lat: w.lat, lng: w.lng)],
      startGate: (lat: c.segment.startGateLat, lng: c.segment.startGateLng),
      endGate: (lat: c.segment.endGateLat, lng: c.segment.endGateLng),
      shape: c.course.courseShape,
    )?.start;
  }
}

/// The park's own words and link, and the notices park_courses.md requires on
/// every park page, folded into one row at the end of the park page.
class _AboutPark extends StatelessWidget {
  final ParkListing listing;
  const _AboutPark({required this.listing});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final park = listing.park;
    final description = park.description?.trim();
    final website = park.websiteUrl;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('park-about'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: const Icon(Icons.info_outline),
        title: Text(l10n.parksAboutPark),
        children: [
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(description, key: const Key('park-description')),
            ),
          if (website != null && website.startsWith('https://'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                key: const Key('park-website'),
                onPressed: () => _openParkWebsite(context, website),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l10n.parksWebsite),
              ),
            ),
          _ParkFootNote(
            key: const Key('park-not-affiliated'),
            text: l10n.parksNotAffiliated,
          ),
          const SizedBox(height: 4),
          _ParkFootNote(
            key: const Key('park-group-permit'),
            text: l10n.parksGroupPermitNotice,
          ),
        ],
      ),
    );
  }
}

/// The facts after a course's distance: its climb and its surface.
List<String> _statsAfterDistance(
  AppLocalizations l10n,
  ParkCourseListing course,
) {
  final climb = course.segment.elevationM;
  final surface = course.segment.surface;
  return [
    if (climb != null && climb > 0)
      l10n.parksCourseClimb(formatElevationForPref(climb)),
    // A stored `road` surface is a paved course (decisions § 2582).
    surface == 'road'
        ? l10n.parksSurfacePaved
        : routeSurfaceLabel(l10n, surface),
  ];
}

/// The strip down a course card's edge, in its line's colour on the map.
class _CourseColourStrip extends StatelessWidget {
  final Color colour;
  const _CourseColourStrip({required this.colour});

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      );
}

class _ParkCourseCard extends StatelessWidget {
  final ParkCourseListing course;
  final String title;
  final Color colour;
  final bool picked;
  final String? recordLine;
  final String? monthRunnersLine;
  final VoidCallback onTap;

  const _ParkCourseCard({
    super.key,
    required this.course,
    required this.title,
    required this.colour,
    required this.picked,
    required this.recordLine,
    required this.monthRunnersLine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final segment = course.segment;
    final pills = courseFactPills(context, course, includeClimb: false);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListCard(
      onTap: onTap,
      selected: picked,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CourseColourStrip(colour: colour),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: ValueKey('park-course-name-${course.course.id}'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: courseDistanceForPref(segment.distanceM),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final fact in _statsAfterDistance(l10n, course))
                          TextSpan(text: ' · $fact'),
                      ],
                    ),
                    key: ValueKey('park-course-stats-${course.course.id}'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (pills.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: pills),
                  ],
                  if (recordLine != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      recordLine!,
                      key: ValueKey('park-course-record-${course.course.id}'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (monthRunnersLine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      monthRunnersLine!,
                      key: ValueKey(
                        'park-course-month-runners-${course.course.id}',
                      ),
                      style: muted,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picked course, pinned under the park page: its whole name, its stats,
/// this season's fastest time, Run this course and Board, and a close that
/// returns to the plain park map.
class _PickedCourseCard extends StatelessWidget {
  final ParkCourseListing course;
  final String title;
  final Color colour;
  final String? recordLine;
  final ApiClient? api;
  final bool loadingRun;
  final void Function(ApiClient api, String routeId) onRun;
  final VoidCallback onBoard;
  final VoidCallback onClose;

  const _PickedCourseCard({
    super.key,
    required this.course,
    required this.title,
    required this.colour,
    required this.recordLine,
    required this.api,
    required this.loadingRun,
    required this.onRun,
    required this.onBoard,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final api = this.api;
    final routeId = course.course.routeId;
    final canRun =
        api != null && routeId != null && courseOffersWayfinding(course.course.status);
    final run = canRun
        ? FilledButton.icon(
            key: const Key('park-picked-run'),
            onPressed: loadingRun ? null : () => onRun(api, routeId),
            icon: loadingRun
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.directions_run),
            label: Text(l10n.parksRunThisCourse),
          )
        : null;
    final board = canRun
        ? OutlinedButton.icon(
            key: const Key('park-picked-board'),
            onPressed: onBoard,
            icon: const Icon(Icons.emoji_events_outlined),
            label: Text(l10n.parksBoard),
          )
        : FilledButton.icon(
            key: const Key('park-picked-board'),
            onPressed: onBoard,
            icon: const Icon(Icons.emoji_events_outlined),
            label: Text(l10n.parksBoard),
          );
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.45,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        height: 24,
                        child: _CourseColourStrip(colour: colour),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            key: const Key('park-picked-name'),
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('park-picked-close'),
                      tooltip: l10n.parksPreviewClose,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          courseDistanceForPref(course.segment.distanceM),
                          ..._statsAfterDistance(l10n, course),
                        ].join(' · '),
                        key: const Key('park-picked-stats'),
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (recordLine != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          recordLine!,
                          key: const Key('park-picked-record'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [?run, board],
                      ),
                    ],
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

class _ParkFootNote extends StatelessWidget {
  final String text;
  const _ParkFootNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

enum ParkBoardKind { fastest, completions }

/// One park course: stats, map with its legend, the elevation profile, one
/// credit line, the notices, the actions and the fastest / most-completions
/// boards for a month, this season or all time. Mobile mirror of web
/// `/parks/[region]/[park]/[course]`.
class ParkCourseScreen extends StatefulWidget {
  final ApiClient? api;
  final ParkListing listing;
  final ParkCourseListing course;

  /// Opened from its own park's screen, so the park link goes back there
  /// rather than stacking a second copy of it.
  final bool fromPark;

  /// The board period to open on, as a month-close notice opens on its month;
  /// null opens on this year. Web carries it as `?period=`.
  final BoardPeriod? initialPeriod;

  /// Test seam for the start and finish directions; production opens the
  /// maps app.
  final Future<bool> Function(Uri uri)? launch;

  const ParkCourseScreen({
    super.key,
    required this.api,
    required this.listing,
    required this.course,
    this.fromPark = false,
    this.initialPeriod,
    this.launch,
  });

  @override
  State<ParkCourseScreen> createState() => _ParkCourseScreenState();
}

class _ParkCourseScreenState extends State<ParkCourseScreen> {
  /// The course map, which the key's start and finish entries move.
  final _map = GlobalKey<ParkCourseMapState>();
  ParkBoardKind _kind = ParkBoardKind.fastest;
  late BoardPeriod _period =
      widget.initialPeriod ?? BoardPeriod.year(widget.listing.season);
  String? _gender;
  String? _ageBand;
  List<GlobalSegmentLeaderboardEntry>? _fastest;
  List<GlobalSegmentCompletionsEntry>? _completions;
  bool _boardFailed = false;

  /// Whether nobody has a time on this course at all, in any season. Null
  /// until known. While true the board is an invitation and its controls stay
  /// hidden, since there is nothing for them to sort or filter.
  bool? _neverRun;

  ParkNow get _parkNow =>
      (season: widget.listing.season, month: widget.listing.month);

  bool get _defaultSelection =>
      _kind == ParkBoardKind.fastest &&
      _period.kind == BoardPeriodKind.year &&
      _gender == null &&
      _ageBand == null;

  void _setPeriod(BoardPeriod next) {
    setState(() => _period = next);
    _refreshBoard();
  }

  @override
  void initState() {
    super.initState();
    _refreshBoard();
  }

  Future<void> _refreshBoard() async {
    final api = widget.api;
    if (api == null || api.userId == null) return;
    setState(() {
      _fastest = null;
      _completions = null;
      _boardFailed = false;
    });
    final segmentId = widget.course.segment.id;
    final args = boardPeriodArgs(_period);
    try {
      if (_kind == ParkBoardKind.fastest) {
        final board = await api
            .fetchGlobalSegmentLeaderboard(
              segmentId,
              gender: _gender,
              ageBand: _ageBand,
              season: args.season,
              month: args.month,
            )
            .timeout(kBackendLoadTimeout);
        if (!mounted) return;
        setState(() {
          _fastest = board;
          if (board.isNotEmpty) _neverRun = false;
        });
        if (board.isEmpty && _defaultSelection && _neverRun == null) {
          await _checkNeverRun();
        }
      } else {
        final board = await api
            .fetchGlobalSegmentCompletions(
              segmentId,
              season: args.season,
              month: args.month,
            )
            .timeout(kBackendLoadTimeout);
        if (!mounted) return;
        setState(() => _completions = board);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _boardFailed = true);
    }
  }

  /// An empty board this season can still have times from earlier ones; the
  /// all-time completions board says whether anyone has ever run the course.
  /// A failed check keeps the controls, which still work.
  Future<void> _checkNeverRun() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final all = await api
          .fetchGlobalSegmentCompletions(
            widget.course.segment.id,
            season: null,
            limit: 1,
          )
          .timeout(kBackendLoadTimeout);
      if (mounted) setState(() => _neverRun = all.isEmpty);
    } catch (e) {
      debugPrint('park course: all-time check failed: $e');
      if (mounted) setState(() => _neverRun = false);
    }
  }

  /// Shares the course line as GPX with its checkpoints and the geometry
  /// credit, which has to travel with the file (OpenStreetMap's licence asks
  /// for it on the exported work).
  Future<void> _shareGpx(BuildContext anchor) async {
    final l10n = AppLocalizations.of(context);
    final course = widget.course.course;
    final segment = widget.course.segment;
    final park = widget.listing.park;
    final guide = parseRouteGuide(course.routeGuide);
    try {
      final gpx = parkCourseGpx(
        name: segment.name,
        waypoints: [
          for (final w in ApiClient.globalSegmentGeometry(segment))
            (lat: w.lat, lng: w.lng, ele: w.elevationMetres),
        ],
        checkpoints: parseCourseCheckpoints(course.checkpoints),
        attribution: courseAttribution(
          course.geometrySource,
          parkName: park.name,
          parkWebsiteUrl: park.websiteUrl,
        ),
        guide: guide == null
            ? null
            : (guide: guide, checkedAt: _isoDay(course.routeGuideCheckedAt)),
      );
      final safe = segment.name
          .replaceAll(RegExp(r'[^a-zA-Z0-9-_ ]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/${safe.isEmpty ? 'course' : safe}.gpx');
      await file.writeAsString(gpx);
      if (!anchor.mounted) return;
      await shareFilesFrom(
        anchor,
        files: [XFile(file.path, mimeType: 'application/gpx+xml')],
        text: segment.name,
      );
    } catch (e) {
      debugPrint('park course share GPX failed: $e');
      if (mounted) {
        showTopBanner(
          context,
          l10n.routeDetailShareFailed('GPX', friendlyError(l10n, e)),
        );
      }
    }
  }

  bool _loadingRun = false;

  Future<void> _runThisCourse(ApiClient api, String routeId) async {
    if (_loadingRun) return;
    await loadParkCourseIntoRecorder(
      context,
      api: api,
      course: widget.course,
      routeId: routeId,
      busy: (v) {
        if (mounted) setState(() => _loadingRun = v);
      },
    );
  }

  void _openPark() {
    if (widget.fromPark) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParkScreen(api: widget.api, listing: widget.listing),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final course = widget.course.course;
    final segment = widget.course.segment;
    final park = widget.listing.park;
    final geometry = ApiClient.globalSegmentGeometry(segment);
    final checkpoints =
        parseCourseCheckpoints(course.checkpoints) ?? const <CourseCheckpoint>[];
    final elevation = segment.elevationM;
    final difficulty = courseDifficultyLabel(l10n, course.difficulty);
    final pills = courseFactPills(context, widget.course, includeClimb: false);
    final description = segment.description?.trim();
    final guide = parseRouteGuide(course.routeGuide);
    final api = widget.api;
    final routeId = course.routeId;
    final wayfinding = courseOffersWayfinding(course.status);
    final canNavigate = api != null && routeId != null && wayfinding;
    final canShare = geometry.length >= 2 && wayfinding;
    // Where the course starts and finishes, as the matcher times it: its line
    // centres, else the ends of the drawn line.
    final ends = courseEnds(
      line: [for (final w in geometry) (lat: w.lat, lng: w.lng)],
      startGate: (lat: segment.startGateLat, lng: segment.startGateLng),
      endGate: (lat: segment.endGateLat, lng: segment.endGateLng),
      shape: course.courseShape,
    );
    // The stored start and finish lines, drawn as a green start box and a red
    // finish box with one plain sentence; null when the segment lacks either,
    // and the map shows its pins as before.
    final zones = courseBoxGates(segment);
    // An out-and-back's last checkpoint is its turn, and checkpoints close
    // enough to hide each other share a marker.
    final marks = checkpointMarks(
      checkpoints: [for (final c in checkpoints) (lat: c.lat, lng: c.lng)],
      line: [for (final w in geometry) (lat: w.lat, lng: w.lng)],
      shape: course.courseShape,
    );
    final hasTurn = marks.any((k) => k.isTurn);
    return DetailPage(
      title: segment.name,
      actions: [
        AppBarAction(
          key: const Key('park-course-help'),
          icon: const Icon(Icons.help_outline),
          label: l10n.infoTipReadGuide,
          onPressed: () => openGuide(context, 'park-courses'),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          contentColumn(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailHero(
                  title: segment.name,
                  padding: EdgeInsets.zero,
                  parent: DetailParentChip(
                    key: const Key('park-course-park-link'),
                    icon: Icons.park_outlined,
                    label: park.name,
                    semanticsLabel: l10n.racesAnyTimeParkLink(
                        '${park.name} · ${regionName(park.regionCode)}'),
                    onPressed: _openPark,
                  ),
                  badges: pills,
                ),
                if (course.status == 'closed') ...[
                  const SizedBox(height: 12),
                  ListCard(
                    key: const Key('park-course-closed'),
                    dense: true,
                    color: theme.colorScheme.errorContainer,
                    child: Text(
                      l10n.parksClosedBanner,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                StatGrid(
                  cells: [
                    StatTile.medium(
                      label: l10n.parksStatDistance,
                      value: courseDistanceForPref(segment.distanceM),
                    ),
                    if (elevation != null && elevation > 0)
                      StatTile.medium(
                        label: l10n.parksStatElevation,
                        value: formatElevationForPref(elevation),
                      ),
                    StatTile.medium(
                      label: l10n.parksStatSurface,
                      // A stored `road` surface is a paved course: it reads
                      // "Paved", never as a run on a road (decisions § 2582).
                      value: segment.surface == 'road'
                          ? l10n.parksSurfacePaved
                          : routeSurfaceLabel(l10n, segment.surface),
                    ),
                    if (difficulty != null)
                      StatTile.medium(
                        label: l10n.parksStatDifficulty,
                        value: difficulty,
                      ),
                  ],
                ),
                if (course.status != 'open' &&
                    course.statusNote != null &&
                    course.statusNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(course.statusNote!),
                ],
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(description, key: const Key('park-course-description')),
                ],
                if (ends != null) ...[
                  const SizedBox(height: 16),
                  CourseEndsCard(
                    ends: ends,
                    launch: widget.launch,
                    // One filled action: Run this course when there is
                    // one, the way to the start otherwise.
                    primary: !canNavigate,
                    instruction:
                        zones == null
                            ? null
                            : courseBoxInstruction(l10n, zones,
                                hasTurn: hasTurn, laps: course.laps),
                  ),
                ],
                // Right under the way to the start, so the one filled
                // action is in reach without scrolling past the page.
                if (canNavigate || canShare) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (canNavigate)
                        FilledButton.icon(
                          key: const Key('park-course-run'),
                          onPressed: _loadingRun
                              ? null
                              : () => _runThisCourse(api, routeId),
                          icon: _loadingRun
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.directions_run),
                          label: Text(l10n.parksRunThisCourse),
                        ),
                      if (canShare)
                        Builder(
                          builder: (anchor) => canNavigate || zones != null
                              ? OutlinedButton.icon(
                                  key: const Key('park-course-share-gpx'),
                                  onPressed: () => _shareGpx(anchor),
                                  icon: const Icon(Icons.ios_share),
                                  label: Text(l10n.parksShareGpx),
                                )
                              : FilledButton.icon(
                                  key: const Key('park-course-share-gpx'),
                                  onPressed: () => _shareGpx(anchor),
                                  icon: const Icon(Icons.ios_share),
                                  label: Text(l10n.parksShareGpx),
                                ),
                        ),
                    ],
                  ),
                ],
                if (geometry.length >= 2) ...[
                  const SizedBox(height: 16),
                  KeyedSubtree(
                    key: const Key('park-course-map'),
                    child: ParkCourseMap(
                      key: _map,
                      line: geometry,
                      checkpoints: checkpoints,
                      shape: course.courseShape,
                      zones: zones,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ParkCourseMapLegend(
                    line: geometry,
                    checkpointCount: marks.where((k) => !k.isTurn).length,
                    hasTurn: hasTurn,
                    zones: zones,
                    onJump: (target) => _map.currentState?.jumpTo(target),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    courseCredit(l10n, course),
                    key: const Key('park-course-attribution'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (elevationSeries(geometry) != null) ...[
                  const SizedBox(height: 20),
                  SectionHeader.title(label: l10n.parksElevationProfile),
                  const SizedBox(height: 8),
                  ElevationChart(
                    key: const Key('park-course-elevation'),
                    track: geometry,
                    theme: theme,
                    unit: activeDistanceUnit,
                  ),
                ],
                if (guide != null && wayfinding) ...[
                  const SizedBox(height: 20),
                  _CourseRouteGuide(
                    guide: guide,
                    checkedAt: course.routeGuideCheckedAt,
                  ),
                ],
                const SizedBox(height: 20),
                _CourseNotices(
                  notices: courseNotices(
                    parkKind: widget.listing.kind,
                    surface: segment.surface,
                    distanceM: segment.distanceM,
                    guide: guide,
                  ),
                  sharedUse: parseSharedUse(course.sharedUse),
                ),
                const SizedBox(height: 24),
                _buildBoards(context, l10n),
                if (api != null) ...[
                  const SizedBox(height: 24),
                  // At the foot of the page, away from Navigate: it is for the
                  // rare runner or land manager with a problem (decisions § 2449).
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const Key('park-course-report'),
                      onPressed: () => showParkCourseReportSheet(
                        context,
                        api: api,
                        courseId: course.id,
                        courseName: segment.name,
                      ),
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(l10n.parkCourseReportAction),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoards(BuildContext context, AppLocalizations l10n) {
    final api = widget.api;
    if (api == null || api.userId == null) {
      return SizedBox(
        height: 220,
        child: SignInRequiredState(
          api: api,
          message: l10n.parksSignInForBoards,
          onSignedIn: _refreshBoard,
        ),
      );
    }
    final theme = Theme.of(context);
    if (_neverRun == true && !_boardFailed) {
      return EmptyState(
        key: const Key('park-board-invitation'),
        icon: Icons.emoji_events_outlined,
        title: l10n.parksBoardEmptyTitle,
      );
    }
    final settledEmptyDefault = _defaultSelection &&
        !_boardFailed &&
        _fastest != null &&
        _fastest!.isEmpty &&
        _neverRun == null;
    if (settledEmptyDefault) {
      return Text(
        l10n.segmentsPanelLeaderboardLoading,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      key: const Key('park-board-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceChipRow<ParkBoardKind>(
          key: const Key('park-board-kind'),
          options: [
            ChoiceChipOption(
              value: ParkBoardKind.fastest,
              label: l10n.parksBoardFastest,
            ),
            ChoiceChipOption(
              value: ParkBoardKind.completions,
              label: l10n.parksBoardCompletions,
            ),
          ],
          selected: _kind,
          onChanged: (k) {
            setState(() => _kind = k);
            _refreshBoard();
          },
        ),
        const SizedBox(height: 8),
        ChoiceChipRow<BoardPeriodKind>(
          key: const Key('park-board-season'),
          options: [
            ChoiceChipOption(
              value: BoardPeriodKind.month,
              label: l10n.parksPeriodThisMonth,
            ),
            ChoiceChipOption(
              value: BoardPeriodKind.year,
              label: l10n.parksSeasonThisYear(widget.listing.season),
            ),
            ChoiceChipOption(
              value: BoardPeriodKind.all,
              label: l10n.parksSeasonAllTime,
            ),
          ],
          selected: _period.kind,
          onChanged: (kind) => _setPeriod(switch (kind) {
            BoardPeriodKind.month =>
              BoardPeriod.month(widget.listing.season, widget.listing.month),
            BoardPeriodKind.year => BoardPeriod.year(widget.listing.season),
            BoardPeriodKind.all => const BoardPeriod.all(),
          }),
        ),
        if (_period.kind == BoardPeriodKind.month)
          _BoardMonthNav(
            key: const Key('park-board-month-nav'),
            period: _period,
            previous: stepBoardMonth(_period, -1, _parkNow),
            next: stepBoardMonth(_period, 1, _parkNow),
            onChanged: _setPeriod,
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => showHeadToHeadSheet(
              context,
              api: api,
              kind: 'global_segment',
              targetId: widget.course.segment.id,
            ),
            icon: const Icon(Icons.people_outline, size: 18),
            label: Text(l10n.headToHeadCompare),
          ),
        ),
        if (_kind == ParkBoardKind.fastest)
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
        if (_kind == ParkBoardKind.fastest && !_boardFailed)
          OldMatchNote(api: api, segment: widget.course.segment),
        ..._boardBody(theme, l10n, api.userId),
      ],
    );
  }

  List<Widget> _boardBody(
    ThemeData theme,
    AppLocalizations l10n,
    String? viewerId,
  ) {
    if (_boardFailed) {
      return [
        AppErrorState(message: l10n.parksBoardFailed, onRetry: _refreshBoard),
      ];
    }
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_kind == ParkBoardKind.fastest) {
      final board = _fastest;
      if (board == null) {
        return [Text(l10n.segmentsPanelLeaderboardLoading, style: muted)];
      }
      if (board.isEmpty) return [Text(l10n.parksNoEfforts, style: muted)];
      return [
        for (final e in board)
          _ParkBoardRow(
            rank: e.rank,
            athlete: e.athlete,
            value: formatEffortTime(e.effort.timeSeconds),
            isViewer: e.effort.userId == viewerId,
          ),
      ];
    }
    final board = _completions;
    if (board == null) {
      return [Text(l10n.segmentsPanelLeaderboardLoading, style: muted)];
    }
    if (board.isEmpty) return [Text(l10n.parksNoEfforts, style: muted)];
    return [
      for (final e in board)
        _ParkBoardRow(
          rank: e.rank,
          athlete: e.athlete,
          value: l10n.parksCompletionDays(e.completions),
          isViewer: e.athlete.id == viewerId,
        ),
    ];
  }
}

/// The month a park course board shows, with arrows to the month before and
/// after; an arrow with no month to go to (past the park's current month, or
/// before the boards' first season) is disabled. Mirrors web's month row.
class _BoardMonthNav extends StatelessWidget {
  final BoardPeriod period;
  final BoardPeriod? previous;
  final BoardPeriod? next;
  final ValueChanged<BoardPeriod> onChanged;

  const _BoardMonthNav({
    super.key,
    required this.period,
    required this.previous,
    required this.next,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final label = formatMonthYear(DateTime(period.season!, period.month!), tag);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('park-board-month-prev'),
            tooltip: l10n.parksPeriodPrevMonth,
            onPressed: previous == null ? null : () => onChanged(previous!),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                label,
                key: const Key('park-board-month-label'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          IconButton(
            key: const Key('park-board-month-next'),
            tooltip: l10n.parksPeriodNextMonth,
            onPressed: next == null ? null : () => onChanged(next!),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// `route_guide_checked_at` as the `YYYY-MM-DD` it is stored as.
String? _isoDay(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

/// A course's route guide (#1344): a short numbered list a runner reads in
/// seconds (the start, the laps, the turns where the trail changes, the
/// finish), with every step folded away under it, grouped by lap or by
/// stretch ([routeGuideView], decisions § 2582), in the reader's language and
/// unit, under a note saying whether a person has walked it at the park yet.
/// Mirrors web's `ParkCourseRouteGuide`.
class _CourseRouteGuide extends StatelessWidget {
  final RouteGuide guide;
  final DateTime? checkedAt;
  const _CourseRouteGuide({required this.guide, required this.checkedAt});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tag = localeToTag(Localizations.localeOf(context));
    final fmt = GuideFormat(
      message: (key, params) => guideLineMessage(l10n, key, params),
      distance: formatDistanceForPref,
      short: formatElevationForPref,
    );
    final view = routeGuideView(guide);
    final lines = [for (final l in view.summary) formatGuideLine(l, fmt)];
    final checked = checkedAt;
    final gettingThere = guide.gettingThere;
    return Column(
      key: const Key('park-course-guide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.title(label: l10n.parkGuideTitle),
        const SizedBox(height: 8),
        if (checked != null)
          Text(
            l10n.parkGuideChecked(formatDateMed(
                DateTime(checked.year, checked.month, checked.day), tag)),
            key: const Key('park-course-guide-checked'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          Container(
            key: const Key('park-course-guide-pending'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: BorderDirectional(
                start: BorderSide(
                  color: AppSemanticColors.of(context).warning,
                  width: 4,
                ),
              ),
            ),
            child: Text(l10n.parkGuidePending,
                style: theme.textTheme.bodyMedium),
          ),
        if (gettingThere != null) ...[
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(l10n.parkGuideGettingThere,
                style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 4),
          Text(gettingThere, key: const Key('park-course-guide-getting-there')),
        ],
        const SizedBox(height: 12),
        Column(
          key: const Key('park-course-guide-steps'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
                    const SizedBox(width: 8),
                    Expanded(child: Text(lines[i])),
                  ],
                ),
              ),
          ],
        ),
        ExpansionTile(
          key: const Key('park-course-guide-all'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: Text(l10n.parkGuideShowAll),
          children: [
            for (final section in view.sections) ...[
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: Text(
                  section.lap != null
                      ? l10n.parkGuideLapHeader(section.lap!)
                      : l10n.parkGuideKmHeader(
                          formatDistanceForPref(section.from.toDouble()),
                          formatDistanceForPref(section.to.toDouble())),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 4),
              for (final l in section.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(formatGuideLine(l, fmt)),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The course page's one notices callout: the safety rules first, the
/// give-way note when an organised group shares the paths, the park-permit
/// line every course carries, the long-course warning when it applies, then
/// the times and not-affiliated notes.
class _CourseNotices extends StatelessWidget {
  /// The lines the course's data supports ([courseNotices]).
  final List<CourseNotice> notices;
  final String? sharedUse;
  const _CourseNotices({required this.notices, required this.sharedUse});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget row(Key key, IconData icon, String text, TextStyle? style) => Row(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: style)),
          ],
        );
    return ListCard(
      key: const Key('park-course-notices'),
      color: scheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      dense: true,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              const Key('park-course-safety'),
              Icons.health_and_safety,
              l10n.parksSafetyNotice,
              theme.textTheme.bodyMedium,
            ),
            if (sharedUseNotice(l10n, sharedUse) case final note?) ...[
              const SizedBox(height: 10),
              row(
                const Key('park-course-shared-use'),
                Icons.groups_outlined,
                note,
                theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 10),
            row(
              const Key('park-course-group-permit'),
              Icons.assignment_outlined,
              l10n.parksGroupPermitNotice,
              theme.textTheme.bodyMedium,
            ),
            for (final n in notices) ...[
              const SizedBox(height: 10),
              switch (n) {
                CourseNotice.ford => row(const Key('park-course-ford'),
                    Icons.water, l10n.parksNoticeFord, theme.textTheme.bodyMedium),
                CourseNotice.pavedTrail => row(
                    const Key('park-course-paved-trail'),
                    Icons.directions_bike,
                    l10n.parksNoticePavedTrail,
                    theme.textTheme.bodyMedium),
                CourseNotice.longTrail => row(const Key('park-course-long'),
                    Icons.schedule, l10n.parksNoticeLongTrail, theme.textTheme.bodyMedium),
                CourseNotice.parkHours => row(const Key('park-course-hours'),
                    Icons.schedule, l10n.parksNoticeParkHours, theme.textTheme.bodyMedium),
                CourseNotice.parkHoursLong => row(
                    const Key('park-course-long'),
                    Icons.schedule,
                    l10n.parksNoticeParkHoursLong,
                    theme.textTheme.bodyMedium),
              },
            ],
            const SizedBox(height: 12),
            // The required notices, as one smaller line under the two that
            // matter to a runner (decisions § 2582).
            Text.rich(
              key: const Key('park-course-fine-print'),
              TextSpan(
                children: [
                  TextSpan(text: l10n.parksNoticeOpenTrail),
                  const TextSpan(text: ' '),
                  TextSpan(text: l10n.parksTimesNotEventResults),
                  const TextSpan(text: ' '),
                  TextSpan(text: l10n.parksNotAffiliated),
                ],
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
    );
  }
}

class _ParkBoardRow extends StatelessWidget {
  final int rank;
  final PublicProfile athlete;
  final String value;
  final bool isViewer;

  const _ParkBoardRow({
    required this.rank,
    required this.athlete,
    required this.value,
    required this.isViewer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
          TextLane(
            width: 32,
            child: Text(
              '#$rank',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IdentityAvatar(
            seed: athlete.id,
            name: athlete.displayName,
            size: 24,
            imageUrl: athlete.avatarUrl,
          ),
          const SizedBox(width: 8),
          // The "You" marker sits under the name, not beside it: inline at
          // 320 dp and 2x it and the time left the name no width at all.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  athlete.displayName ?? l10n.segmentsPanelRunnerFallback,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isViewer ? FontWeight.w700 : null,
                  ),
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
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
