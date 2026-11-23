import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 700),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: Column(children: [child])),
    ),
  ));
}

List<Widget> _bands(String selected, ValueChanged<String> onChanged) => [
      for (final b in ['All', '5K', '10K', 'Half', 'Marathon', 'Ultra', 'Trail'])
        Builder(
          builder: (context) => buildChoiceChip(
              context, ChoiceChipOption(value: b, label: b), selected, onChanged),
        ),
    ];

void main() {
  testWidgets('the search field clears with one tap and reports the empty '
      'query', (tester) async {
    final ctl = TextEditingController();
    final seen = <String>[];
    await _pump(
      tester,
      FilterBar(
        search: AppSearchField(
          controller: ctl,
          hint: 'Search runs',
          clearTooltip: 'Clear search',
          onChanged: seen.add,
        ),
      ),
    );
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Richmond');
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(ctl.text, isEmpty);
    expect(seen.last, '');
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('chips stay on one line at 320 dp and ${scale}x, and the '
        'Filters button with its count sits beside the search',
        (tester) async {
      var opened = 0;
      var removed = 0;
      await _pump(
        tester,
        width: 320,
        textScale: scale,
        FilterBar(
          search: AppSearchField(
            controller: TextEditingController(),
            hint: 'Search races',
            clearTooltip: 'Clear',
          ),
          chips: _bands('All', (_) {}),
          activeFilters: [
            ActiveFilter(
                label: 'Near Richmond',
                onRemove: () => removed++,
                removeTooltip: 'Remove Near Richmond'),
          ],
          filtersLabel: 'Filters',
          filtersSemanticLabel: 'Filters, 2 active',
          activeFilterCount: 2,
          onOpenFilters: () => opened++,
        ),
      );
      expect(tester.takeException(), isNull);
      final tops = {
        for (final e in find.byType(ChoiceChip).evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      };
      expect(tops, hasLength(1), reason: 'the chips wrapped to a second line');
      final button = find.byKey(const Key('filter-bar-filters'));
      expect(tester.getRect(button).right, lessThanOrEqualTo(320 - 16));
      expect(tester.getCenter(button).dy,
          closeTo(tester.getCenter(find.byType(TextField)).dy, 1));
      expect(find.text('2'), findsOneWidget);
      expect(find.byTooltip('Filters'), findsOneWidget);
      expect(find.bySemanticsLabel('Filters, 2 active'), findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.tap(button);
      expect(opened, 1);
      await tester.ensureVisible(find.byTooltip('Remove Near Richmond'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove Near Richmond'));
      expect(removed, 1);
    });
  }

  testWidgets('with no search, Filters leads the chip line', (tester) async {
    await _pump(
      tester,
      FilterBar(
        chips: _bands('All', (_) {}),
        filtersLabel: 'Filters',
        onOpenFilters: () {},
      ),
    );
    final button = find.byKey(const Key('filter-bar-filters'));
    expect(tester.getRect(button).left, 16);
    expect(tester.getCenter(button).dy,
        closeTo(tester.getCenter(find.byType(ChoiceChip).first).dy, 4));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
  });

  testWidgets('withTrailing appends a host\'s actions to the search row',
      (tester) async {
    await _pump(
      tester,
      FilterBar(
        search: AppSearchField(
          controller: TextEditingController(),
          hint: 'Search',
          clearTooltip: 'Clear',
        ),
      ).withTrailing([
        IconButton(icon: const Icon(Icons.sort), tooltip: 'Sort', onPressed: () {}),
      ]),
    );
    expect(find.byTooltip('Sort'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('with no search, the actions stand at the chip line\'s end, '
        'outside its scroll, at 320 dp and ${scale}x (issue #1374: Plans\' '
        'Browse library alone on a row)', (tester) async {
      await _pump(
        tester,
        width: 320,
        textScale: scale,
        FilterBar(
          chips: _bands('All', (_) {}),
          chipsLabel: 'Distance',
          trailing: [
            IconButton(
                icon: const Icon(Icons.public),
                tooltip: 'Library',
                onPressed: () {}),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      final library = find.byTooltip('Library');
      expect(tester.getCenter(library).dy,
          closeTo(tester.getCenter(find.byType(ChoiceChip).first).dy, 4),
          reason: 'the action shares the chip line');
      expect(tester.getRect(library).right, closeTo(320 - AppInsets.gutter, 8));
      expect(
          find.descendant(
              of: find.byKey(const Key('filter-bar-chips')), matching: library),
          findsNothing,
          reason: 'it does not scroll away with the chips');
      expect(
          tester.getSize(find.widgetWithIcon(IconButton, Icons.public)).height,
          greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(find.bySemanticsLabel('Distance'), findsOneWidget);
    });
  }

  testWidgets('with neither a search nor a chip line, the actions take a row',
      (tester) async {
    await _pump(
      tester,
      FilterBar(trailing: [
        IconButton(
            icon: const Icon(Icons.qr_code), tooltip: 'Scan', onPressed: () {}),
      ]),
    );
    expect(find.byTooltip('Scan'), findsOneWidget);
    expect(find.byKey(const Key('filter-bar-line-actions')), findsNothing);
  });

  test('trailingOnLine: only with no search and a line to stand on', () {
    expect(
        FilterBar.trailingOnLine(
            hasSearch: false, hasTrailing: true, hasLine: true),
        isTrue);
    expect(
        FilterBar.trailingOnLine(
            hasSearch: true, hasTrailing: true, hasLine: true),
        isFalse);
    expect(
        FilterBar.trailingOnLine(
            hasSearch: false, hasTrailing: true, hasLine: false),
        isFalse);
  });

  group('a chip line that overflows fades at the edge with more beyond it',
      () {
    test('fadesFor: the start once scrolled, the end while there is more', () {
      expect(EdgeFadeScrollState.fadesFor(pixels: 0, min: 0, max: 100),
          (start: false, end: true));
      expect(EdgeFadeScrollState.fadesFor(pixels: 50, min: 0, max: 100),
          (start: true, end: true));
      expect(EdgeFadeScrollState.fadesFor(pixels: 100, min: 0, max: 100),
          (start: true, end: false));
      expect(EdgeFadeScrollState.fadesFor(pixels: 0, min: 0, max: 0),
          (start: false, end: false),
          reason: 'a line that fits does not fade');
    });

    EdgeFadeScrollState state(WidgetTester tester) =>
        tester.state<EdgeFadeScrollState>(find.byType(EdgeFadeScroll));

    testWidgets('at 320 dp the end fades, then the start once scrolled to '
        'the end', (tester) async {
      await _pump(tester, width: 320, FilterBar(chips: _bands('All', (_) {})));
      await tester.pump();
      expect(state(tester).fadesEnd, isTrue);
      expect(state(tester).fadesStart, isFalse);
      await tester.drag(
          find.byKey(const Key('filter-bar-chips')), const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(state(tester).fadesEnd, isFalse);
      expect(state(tester).fadesStart, isTrue);
    });

    // decisions § 2610 (issue #1374 owner finding 6): a gutter outside the
    // scroll cut the line 16 dp short of the screen, so the chip beyond read
    // as clipped ("Near Me fading off the right edge") and the last could
    // never scroll clear of the edge.
    testWidgets('the line runs to the screen edges with the gutter inside its '
        'scroll, and the last chip scrolls clear', (tester) async {
      await _pump(tester, width: 320, FilterBar(chips: _bands('All', (_) {})));
      await tester.pump();
      final scroller = tester.getRect(find.byKey(const Key('filter-bar-chips')));
      expect(scroller.left, 0);
      expect(scroller.right, 320);
      expect(tester.getRect(find.widgetWithText(ChoiceChip, 'All')).left,
          AppInsets.gutter);
      await tester.drag(
          find.byKey(const Key('filter-bar-chips')), const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.widgetWithText(ChoiceChip, 'Trail')).right,
          lessThanOrEqualTo(320 - AppInsets.gutter));
    });

    testWidgets('a line that fits does not fade', (tester) async {
      await _pump(
        tester,
        width: 700,
        FilterBar(chips: [
          for (final l in ['All', 'Mine'])
            FilterChip(label: Text(l), onSelected: (_) {}),
        ]),
      );
      await tester.pump();
      expect(state(tester).fadesEnd, isFalse);
      expect(state(tester).fadesStart, isFalse);
    });
  });

  // decisions § 2610 (owner choice, 2026-11-22): under a map the search is
  // an icon at the end of the chip line, so the bar is one row.
  group('a collapsible search', () {
    Widget bar(TextEditingController ctl, {List<String>? seen}) => FilterBar(
          collapsibleSearch: true,
          search: AppSearchField(
            controller: ctl,
            hint: 'Search routes by name…',
            clearTooltip: 'Clear search',
            onChanged: seen?.add,
          ),
          chips: _bands('All', (_) {}).take(3).toList(),
          filtersLabel: 'Filters',
          onOpenFilters: () {},
        );
    final icon = find.byKey(const Key('filter-bar-search'));
    final filters = find.byKey(const Key('filter-bar-filters'));

    for (final (width, scale) in [(412.0, 1.0), (320.0, 2.0)]) {
      testWidgets('folds into an icon beside Filters at the end of the chip '
          'line, one row, at $width dp and ${scale}x', (tester) async {
        final ctl = TextEditingController();
        addTearDown(ctl.dispose);
        await _pump(tester, bar(ctl), width: width, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byType(TextField), findsNothing);
        expect(icon, findsOneWidget);
        expect(find.byTooltip('Search routes by name…'), findsOneWidget,
            reason: 'the icon is named by the field\'s hint');
        final chips = tester.getRect(find.byKey(const Key('filter-bar-chips')));
        final i = tester.getRect(icon);
        final f = tester.getRect(filters);
        expect(i.center.dy, moreOrLessEquals(chips.center.dy));
        expect(f.center.dy, moreOrLessEquals(chips.center.dy));
        expect(i.left, greaterThanOrEqualTo(chips.right - 0.5));
        expect(f.left, greaterThanOrEqualTo(i.right - 0.5),
            reason: 'search, then Filters');
        expect(f.right, lessThanOrEqualTo(width - AppInsets.gutter + 0.5));
        expect(i.width, greaterThanOrEqualTo(48));
        expect(i.height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('the icon opens the field in the line\'s place, focused, and '
        'its clear empties it and closes back to the icon', (tester) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      final seen = <String>[];
      await _pump(tester, bar(ctl, seen: seen));
      final lineTop = tester.getRect(find.byKey(const Key('filter-bar-chips'))).top;
      await tester.tap(icon);
      await tester.pump();
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const Key('filter-bar-chips')), findsNothing);
      expect(tester.getRect(find.byType(TextField)).top,
          moreOrLessEquals(lineTop, epsilon: 4),
          reason: 'in the line\'s place, not a row of its own');
      expect(
          tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
          isTrue,
          reason: 'focused, so the keyboard comes up');
      expect(filters, findsOneWidget, reason: 'Filters stays in reach');

      await tester.enterText(find.byType(TextField), 'hill');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      await tester.pump();
      expect(ctl.text, isEmpty);
      expect(seen.last, '');
      expect(find.byType(TextField), findsNothing);
      expect(icon, findsOneWidget);
      expect(Focus.of(tester.element(find.byIcon(Icons.search))).hasFocus,
          isTrue,
          reason: 'focus goes back to the icon it came from');
    });

    testWidgets('an open field with no query closes from its clear button',
        (tester) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      await _pump(tester, bar(ctl));
      await tester.tap(icon);
      await tester.pump();
      expect(find.byTooltip('Clear search'), findsOneWidget,
          reason: 'the way back shows before anything is typed');
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a live query keeps the field open', (tester) async {
      final ctl = TextEditingController(text: 'hill');
      addTearDown(ctl.dispose);
      await _pump(tester, bar(ctl));
      expect(find.byType(TextField), findsOneWidget);
      expect(icon, findsNothing);
      expect(
          tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
          isFalse,
          reason: 'shown, but the keyboard does not pop up on its own');
    });
  });

  testWidgets('the filter sheet\'s Done closes it and Reset resets',
      (tester) async {
    var reset = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showFilterSheet(
              context: context,
              title: 'Filters',
              doneLabel: 'Done',
              resetLabel: 'Reset',
              onReset: () => reset++,
              builder: (_, _) => const Text('controls'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('controls'), findsOneWidget);
    expect(find.byType(SheetScaffold), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(reset, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('controls'), findsNothing);
  });

  group('a lone quick chip never takes a line of its own (issue #1374)', () {
    Widget search() => AppSearchField(
          controller: TextEditingController(),
          hint: 'Search routes',
          clearTooltip: 'Clear search',
        );
    Widget starred(bool on, ValueChanged<bool> onChanged) => FilterToggle(
          label: 'Starred',
          icon: Icons.star_border,
          selectedIcon: Icons.star,
          selected: on,
          onChanged: onChanged,
        );
    Widget views() => ViewSwitch<bool>(
          label: 'Show',
          options: const [
            ChoiceChipOption(value: false, label: 'Mine'),
            ChoiceChipOption(value: true, label: 'Explore'),
          ],
          selected: false,
          onChanged: (_) {},
        );

    test('placement: the search row, else the line, never the views', () {
      LoneChipPlacement at(int n,
              {bool toggle = true,
              bool top = true,
              bool filtersOnLine = false}) =>
          FilterBar.loneChipPlacement(
              chipCount: n,
              isToggle: toggle,
              hasTopRow: top,
              filtersOnLine: filtersOnLine);
      expect(at(1), LoneChipPlacement.searchRow);
      expect(at(1, toggle: false), LoneChipPlacement.line,
          reason: 'only an on/off toggle can become an icon button');
      expect(at(1, top: false), LoneChipPlacement.line,
          reason: 'with no other row the chip is the whole bar');
      expect(at(1, filtersOnLine: true), LoneChipPlacement.line,
          reason: 'the Filters button already shares its line');
      expect(at(2), LoneChipPlacement.line);
      expect(at(0), LoneChipPlacement.line);
    });

    testWidgets('with views and a search, Starred is a toggle in the search '
        'row under the views, never beside them (the owner\'s Routes '
        'screenshot)', (tester) async {
      await _pump(
        tester,
        FilterBar(
            views: views(),
            search: search(),
            chips: [starred(false, (_) {})]),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final toggle = find.byKey(const Key('filter-bar-toggle'));
      expect(toggle, findsOneWidget);
      expect(tester.getCenter(toggle).dy,
          closeTo(tester.getCenter(find.byType(TextField)).dy, 1));
      expect(tester.getRect(toggle).top,
          greaterThanOrEqualTo(tester.getRect(find.byKey(const Key('view-switch'))).bottom));
      expect(find.byKey(const Key('filter-bar-chips')), findsNothing);
    });

    testWidgets('with two chips they keep their own scrolling line',
        (tester) async {
      await _pump(
        tester,
        FilterBar(views: views(), chips: [
          starred(false, (_) {}),
          FilterChip(label: const Text('Near me'), onSelected: (_) {}),
        ]),
        width: 320,
      );
      expect(find.byKey(const Key('filter-bar-chips')), findsOneWidget);
      expect(
          tester.getCenter(find.widgetWithText(FilterChip, 'Starred')).dy,
          greaterThan(tester.getCenter(find.text('Mine')).dy));
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('a lone toggle is an icon button in the search row, at '
          '320 dp and ${scale}x', (tester) async {
        var on = false;
        Future<void> pump() => _pump(
              tester,
              FilterBar(
                search: search(),
                chips: [starred(on, (v) => on = v)],
                filtersLabel: 'Filters',
                onOpenFilters: () {},
              ),
              width: 320,
              textScale: scale,
            );
        await pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(FilterChip), findsNothing);
        final button = find.byKey(const Key('filter-bar-toggle'));
        expect(button, findsOneWidget);
        expect(tester.getCenter(button).dy,
            tester.getCenter(find.byType(TextField)).dy,
            reason: 'it sits in the search row');
        expect(tester.getSize(button).height,
            greaterThanOrEqualTo(kMinInteractiveDimension));
        expect(find.byTooltip('Starred'), findsOneWidget);
        expect(find.byIcon(Icons.star_border), findsOneWidget);

        final handle = tester.ensureSemantics();
        expect(
            tester.getSemantics(button),
            containsSemantics(
              label: 'Starred',
              isButton: true,
              hasToggledState: true,
              isToggled: false,
              hasTapAction: true,
            ));
        await tester.tap(button);
        expect(on, isTrue);
        await pump();
        expect(find.byIcon(Icons.star), findsOneWidget,
            reason: 'on is a filled glyph, not only a colour');
        expect(tester.getSemantics(button),
            containsSemantics(isToggled: true, hasToggledState: true));
        handle.dispose();
      });
    }
  });
}
