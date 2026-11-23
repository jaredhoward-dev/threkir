import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// A two-tab hub shaped like the app's: one strip, a TabBarView of scoped
/// bodies, the active tab's action as the hub's FAB and its menu as the
/// hub's ⋮.
class _Hub extends StatefulWidget {
  const _Hub({required this.bodies});

  final List<Widget> bodies;

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: widget.bodies.length, vsync: this)
        ..addListener(() => setState(() {}));
  final _actions = HubPrimaryActions();

  /// What a hub's host does on Back: the active tab's body first.
  bool consumeBack() => _actions.consumeBack(_tabs.index);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          key: const Key('hub-bar'),
          actions: [HubMenu(actions: _actions, tab: _tabs.index)],
          bottom: TabBar(
            controller: _tabs,
            tabs: [for (var i = 0; i < widget.bodies.length; i++) Tab(text: 'tab $i')],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            for (var i = 0; i < widget.bodies.length; i++)
              HubTabScope(tab: i, actions: _actions, child: widget.bodies[i]),
          ],
        ),
        floatingActionButton: HubFab(actions: _actions, tab: _tabs.index),
      );
}

void main() {
  testWidgets('on its own it is a pushed page: titled app bar, actions, FAB',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: HubTabBody(
        title: 'Plans',
        actions: [IconButton(icon: const Icon(Icons.sort), tooltip: 'Sort', onPressed: () {})],
        primary: PrimaryAction(
            label: 'New plan', icon: Icons.add, onPressed: () => pressed++),
        body: const Text('content'),
      ),
    ));
    expect(find.widgetWithText(AppBar, 'Plans'), findsOneWidget);
    expect(find.byTooltip('Sort'), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New plan'));
    expect(pressed, 1);
  });

  testWidgets('in a hub it draws no app bar or title, and the hub shows the '
      'active tab\'s action as its one FAB', (tester) async {
    var first = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [
        HubTabBody(
          title: 'Runs',
          actions: [IconButton(icon: const Icon(Icons.sort), tooltip: 'Sort', onPressed: () {})],
          primary: PrimaryAction(
              label: 'Add past run', icon: Icons.add, onPressed: () => first++),
          body: const Text('runs'),
        ),
        const HubTabBody(title: 'Segments', body: Text('segments')),
      ]),
    ));
    await tester.pump();
    expect(find.text('Runs'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget, reason: 'only the hub\'s');
    expect(find.byTooltip('Sort'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.text('Add past run'));
    expect(first, 1);

    await tester.tap(find.text('tab 1'));
    await tester.pumpAndSettle();
    expect(find.text('segments'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing,
        reason: 'a tab with no primary action shows no FAB');
  });

  testWidgets('the FAB calls the body\'s newest callback', (tester) async {
    var which = '';
    Widget body(String tag) => HubTabBody(
          title: 't',
          primary: PrimaryAction(
              label: 'Go', icon: Icons.add, onPressed: () => which = tag),
          body: const SizedBox(),
        );
    final key = GlobalKey<_SwapState>();
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [_Swap(key: key, a: body('old'), b: body('new'))]),
    ));
    await tester.pump();
    key.currentState!.swap();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Go'));
    expect(which, 'new');
  });

  testWidgets('selecting replaces the controls and hides the FAB',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [
        HubTabBody(
          title: 'Runs',
          filters: const Text('controls'),
          primary:
              PrimaryAction(label: 'Add', icon: Icons.add, onPressed: () {}),
          selection: HubSelection(
              title: '2 selected', onClose: () {}, closeTooltip: 'Cancel'),
          body: const SizedBox(),
        ),
      ]),
    ));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(find.text('controls'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('turning refresh off keeps the state under the body',
      (tester) async {
    final key = GlobalKey<_SwapState>();
    Widget host(bool refreshable) => HubTabBody(
          title: 't',
          onRefresh: refreshable ? () async {} : null,
          body: _Swap(key: key, a: const Text('a'), b: const Text('b')),
        );
    await tester.pumpWidget(MaterialApp(home: host(true)));
    key.currentState!.swap();
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: host(false)));
    expect(find.text('b'), findsOneWidget, reason: 'the body was remounted');
  });

  testWidgets('it owns pull-to-refresh', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [
        HubTabBody(
          title: 'Routes',
          onRefresh: () async => refreshed++,
          body: ListView(children: const [SizedBox(height: 2000, child: Text('row'))]),
        ),
      ]),
    ));
    await tester.pump();
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, 1);
  });

  // Issue #1374 NS-2 / NS-3: Back in select mode cleared the selection and
  // also left the tab, and Routes' selection ignored Back altogether.
  group('Back', () {
    Widget selecting(String title, VoidCallback onClose) => HubTabBody(
          title: title,
          body: ListView(children: [Text('$title row')]),
          selection: HubSelection(
            title: '1 selected',
            closeTooltip: 'Close',
            onClose: onClose,
          ),
        );

    testWidgets('in a hub, Back goes to the active tab\'s selection only',
        (tester) async {
      var closed0 = 0;
      var closed1 = 0;
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          selecting('zero', () => closed0++),
          selecting('one', () => closed1++),
        ]),
      ));
      final hub = tester.state<_HubState>(find.byType(_Hub));
      expect(hub.consumeBack(), isTrue);
      expect((closed0, closed1), (1, 0));
    });

    testWidgets('a tab with nothing selected leaves Back to the host',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          const HubTabBody(title: 'zero', body: SizedBox()),
        ]),
      ));
      expect(tester.state<_HubState>(find.byType(_Hub)).consumeBack(), isFalse);
    });

    testWidgets('a selection that ends withdraws its handler', (tester) async {
      Widget hub(bool selected) => MaterialApp(
            home: _Hub(bodies: [
              selected
                  ? selecting('zero', () {})
                  : const HubTabBody(title: 'zero', body: SizedBox()),
            ]),
          );
      await tester.pumpWidget(hub(true));
      await tester.pumpWidget(hub(false));
      expect(tester.state<_HubState>(find.byType(_Hub)).consumeBack(), isFalse);
    });

    testWidgets('pushed on its own, Back closes the selection, not the page',
        (tester) async {
      var closed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => selecting('pushed', () => closed++))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(find.text('pushed row'), findsOneWidget);
    });
  });

  testWidgets('the FAB shows its icon only while the list scrolls down, and '
      'its label again on the way up or at rest at the end', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [
        HubTabBody(
          title: 'Routes',
          primary:
              PrimaryAction(label: 'Build', icon: Icons.add, onPressed: () {}),
          body: ListView(children: [
            for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i')),
          ]),
        ),
      ]),
    ));
    await tester.pump();
    final fab = find.byType(FloatingActionButton);
    expect(find.descendant(of: fab, matching: find.text('Build')), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(find.descendant(of: fab, matching: find.text('Build')), findsNothing,
        reason: 'collapsed to its icon while the list moves down');
    expect(find.byTooltip('Build'), findsOneWidget,
        reason: 'the label becomes the tooltip, so the button keeps its name');
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(find.descendant(of: fab, matching: find.text('Build')), findsOneWidget,
        reason: 'scrolling back up brings the label back');
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, -3000), 3000);
    await tester.pumpAndSettle();
    expect(find.descendant(of: fab, matching: find.text('Build')), findsOneWidget,
        reason: 'at rest at the end the list has scrolled clear of it');
  });

  // decisions § 2610: the control row held its height above a list on the
  // move; it slides away while the content scrolls down and comes back the
  // moment it scrolls up, or rests at its top.
  group('Control row', () {
    final search = TextEditingController();
    tearDownAll(search.dispose);
    Widget hub({int rows = 40, HubSelection? selection}) => MaterialApp(
          home: _Hub(bodies: [
            HubTabBody(
              title: 'Runs',
              selection: selection,
              filters: FilterBar(
                search: AppSearchField(
                    controller: search, hint: 'Search', clearTooltip: 'Clear'),
              ),
              body: ListView(children: [
                for (var i = 0; i < rows; i++)
                  SizedBox(height: 60, child: Text('row $i')),
              ]),
            ),
          ]),
        );
    final row = find.byKey(const Key('hub-tab-controls'));
    double rowHeight(WidgetTester tester) => tester.getSize(row).height;
    double listTop(WidgetTester tester) =>
        tester.getRect(find.byType(ListView)).top;
    int searchNodes(WidgetTester tester) {
      var count = 0;
      bool visit(SemanticsNode node) {
        if (node.label.contains('Search') || node.hint.contains('Search')) {
          count++;
        }
        node.visitChildren(visit);
        return true;
      }

      visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      return count;
    }

    testWidgets('slides away pixel for pixel with the drag, the row under '
        'the finger moving exactly as far as the finger', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(hub());
      await tester.pump();
      final shown = rowHeight(tester);
      final top = listTop(tester);
      expect(searchNodes(tester), 1);
      expect(shown, 60);
      double rowY(int i) => tester.getTopLeft(find.text('row $i')).dy;
      final row3 = rowY(3);

      // Past the drag slop first, so every later move is a scroll.
      final gesture = await tester.startGesture(const Offset(200, 400));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      final row3Start = rowY(3);
      final hiddenStart = shown - rowHeight(tester);
      for (final step in [8.0, 6.0, 10.0]) {
        final rowBefore = rowY(3);
        final hiddenBefore = shown - rowHeight(tester);
        await gesture.moveBy(Offset(0, -step));
        await tester.pump();
        expect(shown - rowHeight(tester), moreOrLessEquals(hiddenBefore + step),
            reason: 'the row moved by the drag, not by a timed jump');
        expect(rowY(3), moreOrLessEquals(rowBefore - step),
            reason: 'the list stayed under the finger');
      }
      expect(rowY(3), moreOrLessEquals(row3Start - 24));
      expect(hiddenStart + 24, lessThan(shown));
      expect(row3, greaterThan(rowY(3)));

      await gesture.moveBy(const Offset(0, -200));
      await tester.pump();
      expect(rowHeight(tester), 0, reason: 'clamped at fully hidden');
      expect(listTop(tester), moreOrLessEquals(top - shown),
          reason: 'the list takes the height the row held');
      expect(find.byType(AppSearchField).hitTestable(), findsNothing);
      expect(searchNodes(tester), 0, reason: 'a hidden control is not read');

      final rowBefore = rowY(5);
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      expect(rowHeight(tester), moreOrLessEquals(25),
          reason: 'scrolling up brings it back in step with the finger');
      expect(rowY(5), moreOrLessEquals(rowBefore + 25));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rowHeight(tester), anyOf(0.0, shown),
          reason: 'released part way, it settles at an end');
      semantics.dispose();
    });

    testWidgets('released part way it settles at the nearer end',
        (tester) async {
      await tester.pumpWidget(hub());
      await tester.pump();
      // Scroll the list well down first, so the top rule does not apply.
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(rowHeight(tester), 0);
      // Past the slop, then up until 40 of the row's 60 show.
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(Offset(0, 40 - rowHeight(tester)));
      await tester.pump();
      expect(rowHeight(tester), moreOrLessEquals(40));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rowHeight(tester), 60, reason: '40 of 60 shown: settles shown');

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(rowHeight(tester), 0);
      final g2 = await tester.startGesture(const Offset(200, 300));
      await g2.moveBy(const Offset(0, 20));
      await tester.pump();
      await g2.moveBy(Offset(0, 20 - rowHeight(tester)));
      await tester.pump();
      expect(rowHeight(tester), moreOrLessEquals(20));
      await g2.up();
      await tester.pumpAndSettle();
      expect(rowHeight(tester), 0, reason: '20 of 60 shown: settles hidden');
    });

    testWidgets('after a fling it rests fully shown or fully hidden',
        (tester) async {
      await tester.pumpWidget(hub());
      await tester.pump();
      await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
      await tester.pumpAndSettle();
      expect(rowHeight(tester), 0);
      await tester.fling(find.byType(ListView), const Offset(0, 150), 1500);
      await tester.pumpAndSettle();
      expect(rowHeight(tester), anyOf(0.0, 60.0));
    });

    testWidgets('with reduced motion it settles at once', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: hub(),
      ));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(Offset(0, 40 - rowHeight(tester)));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(rowHeight(tester), 60, reason: 'no ease to wait for');
    });

    testWidgets('a live query keeps it on screen', (tester) async {
      search.text = 'hill';
      addTearDown(search.clear);
      await tester.pumpWidget(hub());
      await tester.pump();
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(rowHeight(tester), 60);
    });

    testWidgets('stays while its search has focus', (tester) async {
      await tester.pumpWidget(hub());
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(rowHeight(tester), greaterThan(0));
    });

    testWidgets('stays over a list too short to need its height',
        (tester) async {
      // Eight rows scroll less than the row is tall.
      await tester.pumpWidget(hub(rows: 8));
      await tester.pump();
      final shown = rowHeight(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(rowHeight(tester), moreOrLessEquals(shown));
    });

    testWidgets('a selection stands in its place and, closed, leaves the row '
        'on screen', (tester) async {
      await tester.pumpWidget(hub());
      await tester.pump();
      final shown = rowHeight(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(rowHeight(tester), 0);
      await tester.pumpWidget(hub(
          selection: HubSelection(
              title: '1 selected', onClose: () {}, closeTooltip: 'Close')));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.pumpWidget(hub());
      await tester.pumpAndSettle();
      expect(rowHeight(tester), moreOrLessEquals(shown));
    });

    testWidgets('a map sheet raised to read its list makes room, and '
        'lowered back to where it opened brings the row back', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          HubTabBody(
            title: 'Explore',
            filters: FilterBar(
              search: AppSearchField(
                  controller: search, hint: 'Search', clearTooltip: 'Clear'),
            ),
            body: DraggableScrollableSheet(
              initialChildSize: 0.4,
              minChildSize: 0.2,
              builder: (context, scroll) => ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < 3; i++)
                    SizedBox(height: 60, child: Text('route $i')),
                ],
              ),
            ),
          ),
        ]),
      ));
      await tester.pump();
      final shown = rowHeight(tester);
      await tester.drag(find.text('route 0'), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(rowHeight(tester), 0, reason: 'the raised sheet takes the room');
      await tester.drag(find.text('route 0'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(rowHeight(tester), moreOrLessEquals(shown),
          reason: 'with the map the subject again, its search is back');
    });

    // decisions § 2610 (UX critique 6): the row hiding resized the page the
    // sheet is a fraction of, so the sheet's edge jumped ahead of the thumb.
    // Over a map it lies on the page, and the sheet keeps below it.
    testWidgets('over a map the row lies on the page: the sheet\'s edge moves '
        'exactly with the drag while the row hides', (tester) async {
      tester.view.physicalSize = const Size(412, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          HubTabBody(
            title: 'Explore',
            collapsesHubTitle: true,
            filters: FilterBar(
              search: AppSearchField(
                  controller: search, hint: 'Search', clearTooltip: 'Clear'),
            ),
            body: MapFirstPage(
              map: const ColoredBox(color: Colors.green),
              sheet: MapFirstSheet(
                initialSize: 0.4,
                minSize: 0.2,
                maxSize: 0.85,
                slivers: [
                  SliverList.list(children: [
                    for (var i = 0; i < 30; i++)
                      SizedBox(height: 60, child: Text('route $i')),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ));
      await tester.pump();
      await tester.pump();
      final sheet = find.byKey(const ValueKey('map-first-sheet'));
      double edge() => tester
          .getRect(find
              .descendant(of: sheet, matching: find.byType(Material))
              .first)
          .top;
      final shown = rowHeight(tester);
      expect(shown, greaterThan(0));
      expect(edge(), greaterThan(tester.getRect(row).bottom),
          reason: 'at rest the sheet starts below the row');

      final g = await tester.startGesture(
          Offset(206, edge() + 30));
      await g.moveBy(const Offset(0, -20));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        final before = edge();
        await g.moveBy(const Offset(0, -15));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(edge(), moreOrLessEquals(before - 15),
            reason: 'step $i: the edge stays under the thumb');
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(rowHeight(tester), 0, reason: 'the raised sheet hid the row');
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Back closes a search opened from its icon before the hub '
        'leaves the tab', (tester) async {
      final store = HubPrimaryActions();
      addTearDown(store.dispose);
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HubTabScope(
            tab: 'explore',
            actions: store,
            child: HubTabBody(
              title: 'Explore',
              filters: FilterBar(
                collapsibleSearch: true,
                search: AppSearchField(
                    controller: ctl, hint: 'Search', clearTooltip: 'Clear'),
                chips: [FilterChip(label: const Text('Routes'), onSelected: (_) {})],
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(store.consumeBack('explore'), isFalse,
          reason: 'closed, Back is the host\'s');
      await tester.tap(find.byKey(const Key('filter-bar-search')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(store.consumeBack('explore'), isTrue);
      await tester.pump();
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(store.consumeBack('explore'), isFalse);
    });

    testWidgets('on its own the row scrolls away with the heading, as before',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: HubTabBody(
          title: 'Runs',
          filters: FilterBar(
            search: AppSearchField(
                controller: search, hint: 'Search', clearTooltip: 'Clear'),
          ),
          body: const SizedBox.shrink(),
        ),
      ));
      expect(row, findsNothing);
    });
  });

  testWidgets('a map body asks for the hub\'s compact bar only while it is '
      'the view showing', (tester) async {
    final store = HubPrimaryActions();
    addTearDown(store.dispose);
    Widget views(int index) => MaterialApp(
          home: Scaffold(
            body: HubTabScope(
              tab: 'routes',
              actions: store,
              child: IndexedStack(index: index, children: const [
                HubTabBody(title: 'Mine', body: SizedBox.expand()),
                HubTabBody(
                    title: 'Explore',
                    collapsesHubTitle: true,
                    body: SizedBox.expand()),
              ]),
            ),
          ),
        );
    await tester.pumpWidget(views(0));
    await tester.pump();
    expect(store.wantsCompactTitle('routes'), isFalse);
    await tester.pumpWidget(views(1));
    await tester.pump();
    expect(store.wantsCompactTitle('routes'), isTrue);
    await tester.pumpWidget(views(0));
    await tester.pump();
    expect(store.wantsCompactTitle('routes'), isFalse,
        reason: 'hidden under the stack, it lets the title be');
    await tester.pumpWidget(views(1));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(store.wantsCompactTitle('routes'), isFalse,
        reason: 'gone, it takes its request with it');
  });

  group('Menu', () {
    final menuButton = find.byKey(const Key('hub-menu'));
    HubMenuItem item(String label, VoidCallback onSelected) => HubMenuItem(
          label: label,
          icon: Icons.add,
          onSelected: onSelected,
          itemKey: Key('item-$label'),
        );

    testWidgets('the hub shows the active tab\'s menu in its bar, and none on '
        'a tab without one', (tester) async {
      var added = 0;
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          HubTabBody(
            title: 'Runs',
            menu: [item('Add past run', () => added++)],
            body: const Text('runs'),
          ),
          const HubTabBody(title: 'Plans', body: Text('plans')),
        ]),
      ));
      await tester.pump();
      expect(
        find.descendant(
            of: find.byKey(const Key('hub-bar')), matching: menuButton),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing,
          reason: 'a menu entry is not a primary action');
      expect(find.byTooltip('Show menu'), findsOneWidget);

      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-Add past run')));
      await tester.pumpAndSettle();
      expect(added, 1);

      await tester.tap(find.text('tab 1'));
      await tester.pumpAndSettle();
      expect(find.text('plans'), findsOneWidget);
      expect(menuButton, findsNothing);

      await tester.tap(find.text('tab 0'));
      await tester.pumpAndSettle();
      expect(menuButton, findsOneWidget);
    });

    testWidgets('a hub can name its ⋮', (tester) async {
      final actions = HubPrimaryActions()
        ..publishMenu(0, [item('Import', () {})]);
      addTearDown(actions.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
              actions: [HubMenu(actions: actions, tab: 0, tooltip: 'More')]),
        ),
      ));
      expect(find.byTooltip('More'), findsOneWidget);
    });

    testWidgets('selecting hides the menu, and closing the selection brings '
        'it back', (tester) async {
      final key = GlobalKey<_SelectableState>();
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          _Selectable(key: key, menu: [item('Import', () {})]),
        ]),
      ));
      await tester.pump();
      expect(menuButton, findsOneWidget);

      key.currentState!.select(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(menuButton, findsNothing);

      key.currentState!.select(false);
      await tester.pump();
      await tester.pump();
      expect(menuButton, findsOneWidget);
    });

    testWidgets('an entry calls the body\'s newest callback', (tester) async {
      var which = '';
      Widget body(String tag) => HubTabBody(
            title: 't',
            menu: [item('Go', () => which = tag)],
            body: const SizedBox(),
          );
      final key = GlobalKey<_SwapState>();
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [_Swap(key: key, a: body('old'), b: body('new'))]),
      ));
      await tester.pump();
      key.currentState!.swap();
      await tester.pump();
      await tester.pump();
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-Go')));
      await tester.pumpAndSettle();
      expect(which, 'new');
    });

    testWidgets('a body that leaves the hub takes its menu with it',
        (tester) async {
      final key = GlobalKey<_SwapState>();
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          _Swap(
            key: key,
            a: HubTabBody(
              title: 't',
              menu: [item('Go', () {})],
              body: const SizedBox(),
            ),
            b: const SizedBox(),
          ),
        ]),
      ));
      await tester.pump();
      expect(menuButton, findsOneWidget);
      key.currentState!.swap();
      await tester.pump();
      await tester.pump();
      expect(menuButton, findsNothing);
    });

    testWidgets('on its own the menu is the app bar\'s ⋮', (tester) async {
      var imported = 0;
      await tester.pumpWidget(MaterialApp(
        home: HubTabBody(
          title: 'Runs',
          menu: [item('Import', () => imported++)],
          body: const Text('content'),
        ),
      ));
      expect(
        find.descendant(of: find.byType(AppBar), matching: menuButton),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-Import')));
      await tester.pumpAndSettle();
      expect(imported, 1);
    });
  });
}

class _Selectable extends StatefulWidget {
  const _Selectable({super.key, required this.menu});

  final List<HubMenuItem> menu;

  @override
  State<_Selectable> createState() => _SelectableState();
}

class _SelectableState extends State<_Selectable> {
  bool _selecting = false;

  void select(bool on) => setState(() => _selecting = on);

  @override
  Widget build(BuildContext context) => HubTabBody(
        title: 'Runs',
        menu: widget.menu,
        selection: _selecting
            ? HubSelection(
                title: '1 selected',
                closeTooltip: 'Close',
                onClose: () => select(false),
              )
            : null,
        body: const SizedBox(),
      );
}

class _Swap extends StatefulWidget {
  const _Swap({super.key, required this.a, required this.b});

  final Widget a;
  final Widget b;

  @override
  State<_Swap> createState() => _SwapState();
}

class _SwapState extends State<_Swap> {
  bool _b = false;

  void swap() => setState(() => _b = true);

  @override
  Widget build(BuildContext context) => _b ? widget.b : widget.a;
}
