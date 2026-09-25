import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/control_bar.dart';
import 'package:life_with_ai/ui/theme.dart';

void main() {
  group('BoardSize', () {
    test('Fit screen matches the screen shape at about 2 pixels a cell', () {
      final mac = BoardSize.fitScreen(1512, 982);
      expect((mac.width, mac.height), (756, 491));
      expect(mac.fitsScreen, isTrue);
      expect(mac.label, 'Fit screen · 756×491');
      expect(mac.shortLabel, 'Fit screen');
      expect(mac.width / mac.height, closeTo(1512 / 982, 0.01), reason: 'the same shape as the screen');
    });

    test("a huge screen is capped so the board stays manageable; a tiny one isn't degenerate", () {
      final huge = BoardSize.fitScreen(6000, 3000);
      expect((huge.width, huge.height), (2048, 1500));
      final tiny = BoardSize.fitScreen(50, 50);
      expect((tiny.width, tiny.height), (64, 64));
    });

    test('equality: presets are themselves; a screen-shaped board differs from a preset of the same size', () {
      expect(BoardSize.of(512, 384), same(BoardSize.medium));
      expect(BoardSize.of(700, 400).label, '700×400');
      expect(BoardSize.of(700, 400).fitsScreen, isFalse);
      expect(BoardSize.fitScreen(1400, 800), isNot(BoardSize.of(700, 400)));
      expect(BoardSize.fitScreen(1400, 800), BoardSize.fitScreen(1400, 800));
      expect({BoardSize.medium, BoardSize.of(512, 384)}, hasLength(1));
    });
  });

  group('the board', () {
    late LifeController life;
    setUp(() async {
      life = LifeController(await Shaders.load());
      await life.init();
    });
    tearDown(() => life.dispose());

    testWidgets('switches to a screen-shaped board', (tester) async {
      await tester.runAsync(() => life.setBoardSize(BoardSize.fitScreen(1512, 982)));
      expect((life.width, life.height), (756, 491));
      expect(life.population, greaterThan(0), reason: 'the board it had, on the new size');
    });

    testWidgets('a new size keeps the pattern, centered, and its name', (tester) async {
      final glider = Grid(512, 384)
        ..set(11, 10, true)
        ..set(12, 11, true)
        ..set(10, 12, true)
        ..set(11, 12, true)
        ..set(12, 12, true);
      await tester.runAsync(() => life.playSeed(glider, title: 'Glider'));
      await tester.runAsync(() => life.setBoardSize(BoardSize.small));
      final g = await tester.runAsync(() => life.engine.snapshot());
      expect((g!.width, g.height), (BoardSize.small.width, BoardSize.small.height));
      expect(g.population, 5, reason: 'the same glider, not a random board');
      final box = g.boundingBox!;
      expect((box.x, box.y), ((g.width - 3) ~/ 2, (g.height - 3) ~/ 2), reason: 'in the middle');
      expect(life.boardTitle, 'Glider');
    });

    testWidgets("a shared seed keeps its exact size, and a screen-shaped board keeps its name for its own seeds", (tester) async {
      await tester.runAsync(() => life.playSeed(Grid(700, 400)..set(3, 3, true), title: 'Odd'));
      expect(life.boardSize.label, '700×400');
      final fit = BoardSize.fitScreen(1512, 982);
      await tester.runAsync(() => life.setBoardSize(fit));
      await tester.runAsync(() => life.playSeed(Grid(756, 491)..set(3, 3, true), title: 'Mine'));
      expect(life.boardSize, fit);
      await tester.runAsync(() => life.playSeed(Grid(512, 384)..set(3, 3, true), title: 'Preset'));
      expect(life.boardSize, BoardSize.medium);
    });

    testWidgets("the size icon's popup offers Fit screen for this display, and applies it", (tester) async {
      tester.view.physicalSize = const Size(1600, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: Neon.theme(),
          home: Scaffold(
            // Along the bottom, as in the app: the popup opens above it.
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ListenableBuilder(
                listenable: life,
                builder: (_, _) => ControlBar(controller: life, erase: false, onEraseChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pump();
      expect(find.text('512×384'), findsOneWidget, reason: 'the current size, among the choices');
      final fit = find.textContaining('Fit screen · ').last;
      expect(fit, findsOneWidget);
      await tester.tap(fit);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(life.boardSize.fitsScreen, isTrue);
      expect(find.text('512×384'), findsNothing, reason: 'choosing closes the popup');
    });
  });
}
