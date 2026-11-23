// ignore_for_file: avoid_relative_lib_imports
// decisions § 2610: the Training hub's shared top chrome (the title row, the
// strip, and each tab's control row) took a third of a 412 dp phone before
// any content, and at 320 dp / 2x the Explore map was nearly hidden. These
// pin the room the change gives back, measured on the laid-out hub.
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme, HubTabBody;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/fitness_hub_screen.dart';
import '../lib/training_service.dart';
import 'three_button_nav_bar.dart' show kThreeButtonNavBar;
import 'worst_case_layout.dart';

const _statusBar = 24.0;

void main() {
  setUpAll(() => initializeDateFormatting());

  final dirs = <Directory>[];
  tearDown(() {
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    dirs.add(d);
    return d;
  }

  /// The hub with Training's four tabs and runs enough to scroll.
  Future<Widget> hub(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('room_runs_'));
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp('room_routes_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tmp('room_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tmp('room_food_'));
    await tester.runAsync(() => runStore.saveManyFromRemote([
          for (var i = 0; i < 30; i++)
            Run(
              id: 'r$i',
              startedAt: DateTime.now().subtract(Duration(minutes: 30 * i)),
              duration: const Duration(minutes: 25),
              distanceMetres: 5000,
              source: RunSource.app,
            ),
        ]));
    return FitnessHubScreen(
      apiClient: null,
      runStore: runStore,
      routeStore: routeStore,
      gymStore: gymStore,
      foodStore: foodStore,
      preferences: prefs,
      training: TrainingService(),
      selectedTab: ValueNotifier(FitnessTab.runs),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openTab(WidgetTester tester, int index) async {
    final tab = find
        .descendant(of: find.byType(TabBar), matching: find.byType(Tab))
        .at(index);
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await settle(tester);
  }

  Future<void> openExplore(WidgetTester tester) async {
    await openTab(tester, 3);
    final explore = find.byKey(const ValueKey('view-switch-segment-1'));
    await tester.ensureVisible(explore);
    await tester.tap(explore);
    await settle(tester);
  }

  Rect strip(WidgetTester tester) => tester.getRect(find.byType(TabBar));

  /// Where the showing tab's content starts: under its control row.
  double contentTop(WidgetTester tester, double width) => find
      .descendant(
          of: find.byType(HubTabBody), matching: find.byType(RefreshIndicator))
      .evaluate()
      .map((e) => tester.getRect(find.byElementPredicate((x) => x == e)))
      .firstWhere((r) => r.left >= 0 && r.left < width)
      .top;

  group('on a 412 dp phone', () {
    Future<void> pumpPhone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      tester.view.padding =
          const FakeViewPadding(top: _statusBar, bottom: kThreeButtonNavBar);
      tester.view.viewPadding =
          const FakeViewPadding(top: _statusBar, bottom: kThreeButtonNavBar);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: await hub(tester),
      ));
      await settle(tester);
    }

    // A tab with a ⋮ (Runs, Races) made the title row 72 dp and its
    // neighbours 56, so the strip moved 16 dp on every switch between them.
    testWidgets('the strip sits at one height on every tab, under a title row '
        'no taller than the compact bar', (tester) async {
      await pumpPhone(tester);
      for (var i = 0; i < 4; i++) {
        await openTab(tester, i);
        expect(strip(tester).top, _statusBar + kToolbarHeight,
            reason: 'tab $i');
      }
    });

    // decisions § 2610 (owner choice, 2026-11-22): Explore's view switch,
    // search row and chip line held 172 dp above the map; the search is an
    // icon at the chip line's end now, so it holds 116.
    testWidgets('Explore at rest gives the search row back: the search is an '
        'icon beside Filters on the chip line', (tester) async {
      await pumpPhone(tester);
      await openExplore(tester);
      expect(find.byType(TextField), findsNothing);
      final icon = find.byKey(const Key('filter-bar-search'));
      final filters = find.byKey(const Key('filter-bar-filters'));
      final line = tester.getRect(find.byKey(const Key('filter-bar-chips')));
      expect(tester.getCenter(icon).dy, moreOrLessEquals(line.center.dy));
      expect(tester.getCenter(filters).dy, moreOrLessEquals(line.center.dy));
      expect(contentTop(tester, 412) - strip(tester).bottom, 116);
    });

    // Runs' search, filters and kind chips held 116 dp above a list on the
    // move; scrolling down gives the list that height, scrolling up returns
    // it.
    testWidgets('a list on the move starts right under the strip, and the '
        'controls come back on the way up', (tester) async {
      await pumpPhone(tester);
      final rest = contentTop(tester, 412);
      expect(rest, greaterThan(strip(tester).bottom + 100));
      final gesture = await tester.startGesture(const Offset(206, 640));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
      }
      expect(contentTop(tester, 412), strip(tester).bottom,
          reason: 'the control row has gone under the strip');
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      expect(contentTop(tester, 412), strip(tester).bottom + 50,
          reason: 'it comes back in step with the finger');
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(contentTop(tester, 412), rest);
      await gesture.up();
      await settle(tester);
    });
  });

  // At 2x the title row wraps taller than the compact bar, and a map never
  // scrolls it away: Explore's map kept it above for good.
  worstCaseTestWidgets('Explore\'s map collapses the hub title into the '
      'compact bar, and every tab fits with its controls hidden',
      (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(locale: locale, home: await hub(tester)));
    await settle(tester);
    // The harness has no status bar.
    expect(strip(tester).top, greaterThan(kToolbarHeight),
        reason: 'at 2x the title row is taller than the bar');

    await openExplore(tester);
    expect(strip(tester).top, kToolbarHeight,
        reason: 'the map got the title row\'s room');
    expectNoOverflow(tester, 'Explore, title collapsed');
    // The chips and the two pinned icons share one row at 2x on 320 dp.
    final line = tester.getRect(find.byKey(const Key('filter-bar-chips')));
    for (final key in ['filter-bar-search', 'filter-bar-filters']) {
      final r = tester.getRect(find.byKey(Key(key)));
      expect(r.center.dy, moreOrLessEquals(line.center.dy), reason: key);
      expect(r.right, lessThanOrEqualTo(kWorstCasePhone.width), reason: key);
    }
    expect(find.byType(TextField), findsNothing);

    await openTab(tester, 0);
    final gesture = await tester.startGesture(
        Offset(kWorstCasePhone.width / 2, kWorstCasePhone.height * 0.75));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
    }
    expect(contentTop(tester, kWorstCasePhone.width), strip(tester).bottom,
        reason: 'Runs\' controls slid away under the strip');
    expectNoOverflow(tester, 'Runs, controls hidden');
    await gesture.up();
    await settle(tester);
  });
}
