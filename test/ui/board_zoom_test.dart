import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/control_bar.dart';
import 'package:life_with_ai/ui/home_page.dart';
import 'package:life_with_ai/ui/life_canvas.dart';
import 'package:life_with_ai/ui/theme.dart';

import 'board_only_test.dart' show FakeFullScreen;

void main() {
  late LifeController life;

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load());
      await life.init();
      await life.clear();
    });
    await tester.pumpWidget(MaterialApp(theme: Neon.theme(), home: HomePage(controller: life, fullScreen: FakeFullScreen())));
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      life.dispose();
    });
  }

  Rect boardRect(WidgetTester tester) => tester.getRect(find.descendant(of: find.byType(LifeCanvas), matching: find.byType(RepaintBoundary)).first);

  testWidgets("a board zooms from the control bar's − Fit + and the mouse wheel, and drawing lands under the pointer", (tester) async {
    await start(tester);
    expect(life.boardView.zoom, 1);
    // − Fit + sit in the control bar, always there.
    expect(find.descendant(of: find.byType(ControlBar), matching: find.byTooltip('Zoom in (+)')), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Fit')).onPressed, isNull, reason: 'nothing to fit at ×1');

    await tester.tap(find.byTooltip('Zoom in (+)'));
    await tester.pump();
    expect(life.boardView.zoom, 2);

    final r = boardRect(tester);
    await tester.sendEventToBinding(PointerScrollEvent(position: r.center, scrollDelta: const Offset(0, -20)));
    await tester.pump();
    expect(life.boardView.zoom, 2.5, reason: 'the wheel zooms in at the pointer');

    await tester.tap(find.text('Fit'));
    await tester.pump();
    expect(life.boardView.zoom, 1);

    // At ×2, centred, a quarter of the way across the screen is 3/8 of the way across the board.
    await tester.tap(find.byTooltip('Zoom in (+)'));
    await tester.pump();
    expect(find.text('ZOOM: ×2', findRichText: true), findsOneWidget, reason: 'the HUD shows how far in');
    await tester.tapAt(r.topLeft + Offset(r.width / 4, r.height / 4));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    final g = (await tester.runAsync(() => life.engine.snapshot()))!;
    final x = (g.width * 3 / 8).floor(), y = (g.height * 3 / 8).floor();
    expect(g.population, 1);
    expect(g.get(x, y), isTrue, reason: 'the cell under the pointer, not the one at the unzoomed spot');
  });
}
