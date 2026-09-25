import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/engine/giant_runner.dart';
import 'package:life_with_ai/engine/life_engine.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/home_page.dart';
import 'package:life_with_ai/ui/theme.dart';

import '../core/rle_test.dart' show forumSamples, gosperGun;
import 'board_only_test.dart' show FakeFullScreen;

void main() {
  late LifeController life;

  Future<void> start(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load())..newGiantRunner = GiantRunner.inline;
      await life.init();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Neon.theme(),
        home: HomePage(controller: life, fullScreen: FakeFullScreen()),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      life.dispose();
    });
  }

  /// Lets the engine's async work (snapshots, loads) finish, then draws.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // the dialog's fade
  }

  Future<void> playGlider(WidgetTester tester) async {
    final g = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(g, 100, 100);
    await tester.runAsync(() => life.playSeed(g, title: 'A lonely glider'));
    await tester.pump();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Import or export RLE'));
    await settle(tester);
    expect(find.text('Pattern as RLE'), findsOneWidget);
  }

  String fieldText(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('shows the board as RLE, paused, and plays on when closed', (tester) async {
    await start(tester);
    await playGlider(tester);
    expect(life.running, isTrue);

    await openDialog(tester);
    expect(life.running, isFalse, reason: 'what you copy is what you saw');
    final text = fieldText(tester);
    expect(text, startsWith('#N A lonely glider\n#C Generation '));
    expect(text, contains('#C Open it in Life with AI: https://shanepkearney.github.io/life-with-ai/#seed='));
    expect(text, endsWith('x = 3, y = 3, rule = B3/S23\nbo\$2bo\$3o!'));

    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(find.text('Pattern as RLE'), findsNothing);
    expect(life.running, isTrue, reason: 'it was playing before');
  });

  testWidgets('Copy puts the RLE on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await start(tester);
    await playGlider(tester);
    await openDialog(tester);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, fieldText(tester));
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('a pasted pattern loads centered, named, and playing', (tester) async {
    await start(tester);
    await playGlider(tester);
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), gosperGun);
    await tester.tap(find.text('Load'));
    await settle(tester);

    expect(find.text('Pattern as RLE'), findsNothing);
    expect(find.text('Loaded "Gosper glider gun".'), findsOneWidget);
    expect(life.boardTitle, 'Gosper glider gun');
    expect(life.originGeneration, 0);
    expect(life.running, isTrue);
    final board = life.timeline!.origin; // it has been playing since: check generation 0
    expect(board.population, 36);
    expect(board.boundingBox, (x: 238, y: 187, width: 36, height: 9), reason: 'centered on the 512x384 board');
  });

  testWidgets('a pattern too big for the board moves up to a board that holds it', (tester) async {
    await start(tester);
    await tester.runAsync(() => life.setBoardSize(BoardSize.small));
    await tester.pump();
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'x = 300, y = 1\n300o!');
    await tester.tap(find.text('Load'));
    await settle(tester);
    expect(life.boardSize, BoardSize.medium);
    expect(find.text('Loaded "Pasted pattern".'), findsOneWidget);
  });

  testWidgets('a forum pattern made for a small torus plays on exactly that board', (tester) async {
    await start(tester);
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), forumSamples.last.rle);
    await tester.tap(find.text('Load'));
    await settle(tester);
    expect((life.boardSize.width, life.boardSize.height), (48, 12));
    expect(life.timeline!.origin.population, 32);
  });

  testWidgets('a pattern it can not run says why and stays open', (tester) async {
    await start(tester);
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'x = 3, y = 3, rule = B34twz/S23\nbob\$2bo\$3o!');
    await tester.tap(find.text('Load'));
    await settle(tester);
    expect(find.text('Pattern as RLE'), findsOneWidget);
    expect(find.textContaining('uses the rule B34twz/S23'), findsOneWidget);

    // Bigger than the endless plane allows, by its header alone.
    await tester.enterText(find.byType(TextField), 'x = 99999999, y = 1\n3o!');
    await tester.tap(find.text('Load'));
    await settle(tester);
    expect(find.textContaining('This pattern is 99,999,999 × 1 cells, too big even for the endless plane'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bo');
    await tester.pump();
    expect(find.textContaining('endless plane'), findsNothing, reason: 'editing clears the message');
  });

  testWidgets('a pattern too big for any board opens on the endless plane instead', (tester) async {
    await start(tester);
    await openDialog(tester);
    // The Turing machine's own header, with its first rows: 12,699 x 12,652 by the header.
    await tester.enterText(find.byType(TextField), '#N Turing machine\nx = 12699, y = 12652, rule = b3/s23\n144b2o\$145bo\$145bobo\$146b2o3\$151b2o\$150b2o\$152bo!');
    await tester.tap(find.text('Load'));
    // The plane runs in a background isolate: give it real time to start.
    for (var i = 0; i < 50 && life.giant == null; i++) {
      await settle(tester);
    }
    await settle(tester);

    expect(find.text('Pattern as RLE'), findsNothing);
    expect(life.giant, isNotNull);
    expect(life.giant!.name, 'Turing machine');
    expect(life.running, isTrue, reason: 'it plays at once, like any loaded pattern');
    expect(life.population, greaterThan(0));
    expect(life.engineKind, EngineKind.hashlife);
    expect(life.canStepBack, isFalse, reason: 'no rewind history on the plane');
    expect(find.textContaining('on an endless plane, run by HashLife'), findsOneWidget);

    // Anything that puts a normal board down leaves the plane.
    await tester.tap(find.byTooltip('Randomize'));
    for (var i = 0; i < 20 && life.giant != null; i++) {
      await settle(tester);
    }
    expect(life.giant, isNull);
    expect(life.engineKind, isNot(EngineKind.hashlife), reason: 'back on the engine it was using');
  });

  testWidgets('on a phone it lives in the ⚙ sheet, and fits the screen', (tester) async {
    await start(tester, size: const Size(390, 844));
    await playGlider(tester);
    expect(find.byTooltip('Import or export RLE'), findsNothing, reason: 'the strip is full');

    await tester.tap(find.byTooltip('Speed, glow and engine'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Import or export RLE'));
    await settle(tester);

    expect(find.text('Pattern as RLE'), findsOneWidget);
    // It played on while the sheet opened, so the glider may be in another phase.
    expect(fieldText(tester), contains('x = 3, y = 3, rule = B3/S23\n'));
    expect(tester.takeException(), isNull, reason: 'no overflow at phone width');
  });
}
