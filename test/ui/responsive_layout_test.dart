import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/main.dart';
import 'package:life_with_ai/ui/control_bar.dart';
import 'package:life_with_ai/ui/mobile_controls.dart';
import 'package:life_with_ai/ui/mobile_sheet.dart';

import 'board_only_test.dart' show FakeFullScreen;
import 'package:shared_preferences/shared_preferences.dart';

/// The layout follows the window, live: narrowing it switches to the phone
/// layout and widening switches back. (Not runnable with `--platform chrome`:
/// that harness can't load the app's shader assets.)
void main() {
  testWidgets('resizing the window switches layouts both ways', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 920);
    addTearDown(tester.view.reset);

    late LifeApp app;
    await tester.runAsync(() async => app = await bootstrap());
    await tester.pumpWidget(app);
    await tester.pump();
    expect(find.byType(ControlBar), findsOneWidget);

    for (final (size, phone) in [
      (const Size(890, 900), true), // just under the width breakpoint
      (const Size(820, 1180), true), // an iPad Air held upright
      (const Size(1180, 820), false), // the same iPad on its side
      (const Size(1024, 700), false), // the Mac app's smallest window
      (const Size(1200, 480), true), // wide but short: landscape phone
      (const Size(1200, 800), false),
      (const Size(400, 850), true),
      (const Size(1440, 920), false),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(find.byType(MobileControls), phone ? findsOneWidget : findsNothing, reason: '$size');
      expect(find.byType(MobileSheet), phone ? findsOneWidget : findsNothing, reason: '$size');
      expect(find.byType(ControlBar), phone ? findsNothing : findsOneWidget, reason: '$size');
    }
    await tester.pumpWidget(const SizedBox());
    app.controller.dispose();
  });

  // Regression: the resting sheet drew the panel's divider under its tabs, a
  // lone cyan line across the bottom of the phone layout with nothing below it.
  testWidgets('the resting phone sheet has no divider under its tabs; the open one does', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 850);
    addTearDown(tester.view.reset);

    late LifeApp app;
    await tester.runAsync(() async => app = await bootstrap());
    await tester.pumpWidget(app);
    await tester.pump();
    final dividers = find.descendant(of: find.byType(MobileSheet), matching: find.byType(Divider));
    expect(dividers, findsNothing, reason: 'resting');

    await tester.tap(find.bySemanticsLabel('Expand the assistant'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(dividers, findsWidgets, reason: 'open');
    await tester.pumpWidget(const SizedBox());
    app.controller.dispose();
  });

  // Regression: the ⇅ button made the header 17px too wide just above the
  // old 700px breakpoint, with every button showing (⬇ on a Mac, ⛶ supported).
  testWidgets('the desktop header fits just above the phone breakpoint', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(901, 900);
    addTearDown(tester.view.reset);

    late LifeApp app;
    await tester.runAsync(() async => app = await bootstrap(offerMacDownload: true, fullScreen: FakeFullScreen()));
    await tester.pumpWidget(app);
    await tester.pump();
    expect(find.byType(ControlBar), findsOneWidget, reason: 'the desktop layout');
    expect(find.byTooltip('Get the macOS app'), findsOneWidget);
    expect(find.byTooltip('Import or export RLE'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the header must not overflow');
    await tester.pumpWidget(const SizedBox());
    app.controller.dispose();
  });
}
