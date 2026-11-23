import 'package:flutter/material.dart';
import 'dart:ui' show SemanticsFlag;

import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('a toggle that is on fills, swaps its glyph and is heard as on',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var on = false;
    await tester.pumpWidget(_app(StatefulBuilder(
      builder: (context, setState) => MapControlButton(
        label: 'Near me',
        icon: Icons.near_me_outlined,
        selectedIcon: Icons.near_me,
        selected: on,
        onPressed: () => setState(() => on = !on),
      ),
    )));
    final button = find.byType(ElevatedButton);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48),
        reason: 'a 48 dp target');
    expect(find.text('Near me'), findsOneWidget);
    expect(find.byIcon(Icons.near_me_outlined), findsOneWidget);
    expect(tester.getSemantics(find.text('Near me')),
        matchesSemantics(
            label: 'Near me',
            isButton: true,
            hasToggledState: true,
            isToggled: false,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true));
    Color fill() => tester
        .widget<Material>(find.descendant(of: button, matching: find.byType(Material)))
        .color!;
    final offFill = fill();

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.near_me), findsOneWidget);
    expect(fill(), isNot(offFill));
    expect(fill(), AppTheme.light.colorScheme.primary);
    expect(
        tester
            .getSemantics(find.text('Near me'))
            .hasFlag(SemanticsFlag.isToggled),
        isTrue);
    semantics.dispose();
  });

  testWidgets('a long label wraps rather than leaving a narrow map',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: Scaffold(
        body: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: MapControlButton(
            label: 'Wo du schon gelaufen bist',
            icon: Icons.person_pin_circle_outlined,
            onPressed: () {},
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(ElevatedButton)).right,
        lessThanOrEqualTo(320));
  });

  testWidgets('compact draws about 36 dp high, keeps its label and a 48 dp '
      'target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(MapControlButton(
      label: "Where you've run",
      icon: Icons.person_pin_circle_outlined,
      compact: true,
      onPressed: () => taps++,
    )));
    final button = find.byType(ElevatedButton);
    expect(find.text("Where you've run"), findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48),
        reason: 'the padded target stays 48 dp');
    final drawn = tester.getSize(
        find.descendant(of: button, matching: find.byType(Material)));
    expect(drawn.height, inInclusiveRange(32, 40));
    await tester.tap(button);
    expect(taps, 1);
  });
}
