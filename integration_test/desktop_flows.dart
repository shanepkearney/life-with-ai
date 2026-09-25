import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:life_with_ai/app/platform/full_screen.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/core/rle.dart';
import 'package:life_with_ai/engine/life_engine.dart';
import 'package:life_with_ai/main.dart';
import 'package:life_with_ai/render/board_palette.dart';
import 'package:life_with_ai/ui/control_bar.dart';
import 'package:life_with_ai/ui/life_canvas.dart';
import 'package:life_with_ai/ui/hud.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end: the real app (real shaders, isolate, storage and clipboard) with
/// only the Anthropic API scripted. Run with:
///
///   flutter test integration_test -d macos   (runs via all_test.dart)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A fresh, isolated store per test: never touch the developer's real key or favorites.
  setUp(() => SharedPreferences.setMockInitialValues({'anthropic_api_key': 'sk-test'}));

  /// Pumps real frames until [condition] holds (the ticker never settles, so
  /// pumpAndSettle can't be used).
  Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {String? reason, int seconds = 20}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for: ${reason ?? 'condition'}');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Real frames for [ms] of wall-clock time, e.g. to let an animation finish.
  Future<void> frames(WidgetTester tester, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Taps a snackbar action once its message has finished sliding in: the old
  /// message animates out first, and a tap mid-animation can miss.
  Future<void> tapSnackBarAction(WidgetTester tester, String label) async {
    await pumpUntil(tester, () => find.text(label).evaluate().isNotEmpty, reason: '"$label" shown');
    await frames(tester, 500);
    await tester.tap(find.text(label));
  }

  Future<LifeApp> start(WidgetTester tester, {Uri? launchUri, http.Client? api, EngineKind engine = EngineKind.gpu, FullScreen? fullScreen}) async {
    // Tear down the previous test's app first. Pumping a new LifeApp over the
    // old one would let Flutter reuse the existing Navigator, whose screen is
    // still wired to the previous test's board and favorites.
    await tester.pumpWidget(const SizedBox());
    final app = await bootstrap(launchUri: launchUri, httpClient: api, engine: engine, fullScreen: fullScreen);
    // Unmount before disposing: a mounted board would paint with freed GPU images.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      app.controller.dispose();
    });
    await tester.pumpWidget(app);
    await tester.pump();
    return app;
  }

  // Regression: every GPU pass used to chain onto the image before it, and
  // freeing a chain thousands of links long overflowed the raster thread's
  // stack, so loading a favorite after a few minutes' play crashed the app.
  // A crash kills the test process, so getting to the end is the assertion.
  testWidgets('after a long run, loading another board does not crash', (tester) async {
    final app = await start(tester);
    final life = app.controller;
    for (var i = 0; i < 4000; i++) {
      await tester.runAsync(life.stepOnce); // each step also chains a glow-trail pass
      if (i % 25 == 0) await tester.pump(const Duration(milliseconds: 16));
    }
    expect(life.generation, 4000);
    final seed = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(seed, 10, 10);
    await tester.runAsync(() => life.playSeed(seed, title: 'A favorite'));
    await frames(tester, 500);
    expect(life.boardTitle, 'A favorite');
    expect(life.generation, greaterThan(0), reason: 'the new board is playing');
  });

  testWidgets('macOS full screen, for real: the window enters and leaves it through the channel', (tester) async {
    final fullScreen = FullScreen.platform();
    addTearDown(fullScreen.dispose);
    expect(fullScreen.supported, isTrue);
    await pumpUntil(tester, () => !fullScreen.active.value, reason: 'starts windowed');
    await fullScreen.set(true);
    await pumpUntil(tester, () => fullScreen.active.value, reason: 'the window reports full screen', seconds: 15);
    await fullScreen.set(false);
    await pumpUntil(tester, () => !fullScreen.active.value, reason: 'the window reports windowed again', seconds: 15);
  });

  testWidgets('Board only: just the board, a bar that fades, and back', (tester) async {
    // Windowed (no full screen): this checks the view; the test above checks
    // the real window, and the widget tests check how the two go together.
    final app = await start(tester, fullScreen: NoFullScreen());
    await tester.tap(find.byTooltip('Board only (B)'));
    await frames(tester, 300);
    expect(find.byType(ControlBar), findsNothing);
    expect(find.byTooltip('Leave board only (Esc)'), findsOneWidget);
    // Real fonts: the bar's five buttons sit within the window.
    final bar = tester.getRect(find.byTooltip('Leave board only (Esc)'));
    expect(bar.right, lessThanOrEqualTo(tester.view.physicalSize.width / tester.view.devicePixelRatio));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester, 300);
    expect(find.byType(ControlBar), findsOneWidget);
    expect(app.controller.generation, greaterThanOrEqualTo(0));
  });

  testWidgets('boots, plays on the GPU engine, and hot-swaps to the CPU engine', (tester) async {
    final app = await start(tester);
    final life = app.controller;
    expect(find.text('Assistant'), findsOneWidget);
    expect(life.population, greaterThan(1000), reason: 'starts on a random board');

    await tester.tap(find.byTooltip('Play (space)'));
    await pumpUntil(tester, () => life.generation >= 20, reason: 'GPU engine advancing');

    await tester.tap(find.text('CPU'));
    await pumpUntil(tester, () => life.engineKind == EngineKind.cpu, reason: 'engine swap');
    final genAtSwap = life.generation;
    await pumpUntil(tester, () => life.generation >= genAtSwap + 20, reason: 'CPU engine advancing');
    expect(find.textContaining('CPU · isolate'), findsWidgets);

    await tester.tap(find.text('HashLife'));
    await pumpUntil(tester, () => life.engineKind == EngineKind.hashlife, reason: 'swap to HashLife');
    final genAtHash = life.generation;
    await pumpUntil(tester, () => life.generation >= genAtHash + 20, reason: 'HashLife advancing');
    expect(find.textContaining('HashLife · tree'), findsWidgets);
  });

  testWidgets('at the default window size the controls fit on one row', (tester) async {
    // The size MainFlutterWindow.swift opens at (a restored window may differ, so set it).
    tester.view.physicalSize = const Size(1440, 920) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await start(tester);
    await tester.pump();
    // Every control sits on the same row: with centered wrapping, one row means one center line.
    final wrap = tester.renderObject<RenderWrap>(find.descendant(of: find.byType(ControlBar), matching: find.byType(Wrap)));
    final rows = <double>{};
    wrap.visitChildren((c) {
      final b = c as RenderBox;
      rows.add(((b.parentData! as WrapParentData).offset.dy + b.size.height / 2).roundToDouble());
    });
    expect(rows, hasLength(1), reason: 'the control bar wraps onto ${rows.length} rows');
    final hud = tester.renderObject<RenderBox>(find.byType(Hud));
    expect(hud.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(hud.size.width), reason: 'Hud would wrap');
    // Real fonts: all three tab labels fit whole, none cut short with an ellipsis.
    for (final label in ['Assistant', 'Favorites', 'Community']) {
      expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isFalse, reason: '"$label" is cut off');
    }
  });

  testWidgets('messages never cover the controls, even when the controls wrap', (tester) async {
    // Narrow enough that the control bar wraps onto two rows (as in the bug report).
    tester.view.physicalSize = const Size(1100, 900) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await start(tester);
    final wrap = tester.renderObject<RenderWrap>(find.descendant(of: find.byType(ControlBar), matching: find.byType(Wrap)));
    final rows = <double>{};
    wrap.visitChildren((c) {
      final b = c as RenderBox;
      rows.add(((b.parentData! as WrapParentData).offset.dy + b.size.height / 2).roundToDouble());
    });
    expect(rows.length, greaterThan(1), reason: 'precondition: controls wrap');

    await tester.tap(find.byTooltip('Save this moment to favorites'));
    await pumpUntil(tester, () => find.textContaining('to favorites').evaluate().isNotEmpty, reason: 'toast shown');
    await frames(tester, 400); // let it finish sliding in

    final toast = tester.getRect(find.ancestor(of: find.textContaining('to favorites'), matching: find.byType(Container)).first);
    final controls = tester.getRect(find.byType(ControlBar));
    expect(toast.overlaps(controls), isFalse, reason: 'toast $toast overlaps controls $controls');
    expect(toast.bottom, lessThanOrEqualTo(controls.top));
    // The panel beside the board is left alone too.
    final panel = tester.getRect(find.text('Assistant'));
    expect(toast.right, lessThan(panel.left));
  });

  testWidgets('rewind: step back, back to the start, arrow keys, and drawing sets a new beginning', (tester) async {
    final app = await start(tester);
    final life = app.controller;
    Future<int> board() async => (await life.captureMoment()).seed.stateHash;
    final origin = await board();
    // Taps wait for the previous step's frame, as any real click does; a tap in
    // the same instant a step finishes can be dropped by the test harness.
    Future<void> tapSettled(WidgetTester tester, Finder f) async {
      await frames(tester, 150);
      await tester.tap(f);
    }

    // The desktop bar wraps each IconButton in a Tooltip (the phone strip is the other way round).
    bool enabled(String tip) =>
        tester.widget<IconButton>(find.descendant(of: find.byTooltip(tip), matching: find.byType(IconButton))).onPressed != null;
    expect(enabled('Back to the start'), isFalse);
    expect(enabled('Step back one generation (←)'), isFalse);

    // Five steps forward, five back: the same board as the start.
    for (var i = 0; i < 5; i++) {
      await tapSettled(tester, find.byTooltip('Step one generation (→)'));
      await pumpUntil(tester, () => life.generation == i + 1, reason: 'forward ${i + 1}');
    }
    for (var i = 4; i >= 0; i--) {
      await tapSettled(tester, find.byTooltip('Step back one generation (←)'));
      await pumpUntil(tester, () => life.generation == i, reason: 'back to $i');
    }
    expect(await board(), origin);

    // Arrow keys scrub while paused.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await pumpUntil(tester, () => life.generation == 2, reason: 'arrow right twice');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await pumpUntil(tester, () => life.generation == 1, reason: 'arrow left');

    // Back to the start while running keeps it running.
    await tapSettled(tester, find.byTooltip('Play (space)'));
    await pumpUntil(tester, () => life.generation > 20, reason: 'running');
    await tapSettled(tester, find.byTooltip('Back to the start'));
    await pumpUntil(tester, () => life.generation < 5, reason: 'rewound');
    expect(life.running, isTrue);
    await tapSettled(tester, find.byTooltip('Pause (space)'));
    await tester.pump();

    // Drawing is a new beginning: the start is now the edited board.
    for (var i = 0; i < 3; i++) {
      await tapSettled(tester, find.byTooltip('Step one generation (→)'));
      await pumpUntil(tester, () => !life.atBeginning && life.generation >= 1, reason: 'stepped');
    }
    final canvas = find.byType(LifeCanvas);
    await frames(tester, 150);
    await tester.tapAt(tester.getCenter(canvas));
    await pumpUntil(tester, () => life.atBeginning, reason: 'the edit became the beginning');
    final edited = await board();
    await tapSettled(tester, find.byTooltip('Step one generation (→)'));
    await pumpUntil(tester, () => !life.atBeginning, reason: 'step after edit');
    await tapSettled(tester, find.byTooltip('Back to the start'));
    await pumpUntil(tester, () => life.atBeginning, reason: 'back to the edit');
    expect(await board(), edited);
  });

  testWidgets('a pattern too big for any board runs on the endless plane, with pan, zoom, jumps and rewind', (tester) async {
    // The Mac app's smallest window, where the board area is tightest (CI's screen is small too).
    tester.view.physicalSize = const Size(1024, 700) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final app = await start(tester);
    final life = app.controller;
    // A gun and a blinker 5,000 cells apart: far wider than the largest board.
    final far = Grid(5000, 40);
    patternLibrary['gosper_glider_gun']!.stampOnto(far, 2, 2);
    patternLibrary['blinker']!.stampOnto(far, 4990, 30);
    final text = Rle.encode(far, name: 'Far apart');

    await tester.tap(find.byTooltip('Import or export RLE'));
    await pumpUntil(tester, () => find.text('Pattern as RLE').evaluate().isNotEmpty, reason: 'dialog open');
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.text('Load'));
    await pumpUntil(tester, () => (life.giant?.population ?? 0) > 0, reason: 'loaded on the plane');
    // Loaded is not yet drawn: wait for the board area to switch to the plane's view.
    await pumpUntil(tester, () => find.textContaining('endless plane').evaluate().isNotEmpty, reason: 'the plane on screen');

    final g = life.giant!;
    expect(g.name, 'Far apart');
    expect(life.engineKind, EngineKind.hashlife);
    expect(g.zoom, lessThan(0), reason: 'fitted: 5,000 cells across needs several cells a pixel');
    expect(find.textContaining('endless plane'), findsWidgets); // the corner label; the HUD may be scaled or compact on a small screen
    expect(find.textContaining('Jump ×'), findsOneWidget, reason: 'the speed slider is the jump size');

    // Jumps: pause, then one step of 2^10.
    if (life.running) life.toggleRunning();
    await frames(tester, 300);
    life.setGiantJump(10);
    await frames(tester, 100);
    final before = life.generation;
    await tester.tap(find.byTooltip('Jump ×1,024 generations (→)'));
    await pumpUntil(tester, () => life.generation == before + 1024, reason: 'one jump of 1,024');

    // Zoom in with the + button, pan by dragging, and Fit brings it all back.
    final zoom = g.zoom;
    await tester.tap(find.byTooltip('Zoom in (+)'));
    await frames(tester, 200);
    expect(g.zoom, zoom + 1);
    final x = g.centreX;
    await tester.dragFrom(tester.getCenter(find.byType(LifeCanvas)), const Offset(-200, 0));
    await frames(tester, 300);
    expect(g.centreX, greaterThan(x), reason: 'dragging left moves the view right');
    await tester.tap(find.text('Fit'));
    await frames(tester, 300);
    expect(g.zoom, zoom);

    // Back to the start is generation 0 of the pattern; there's no stepping back.
    expect(life.canStepBack, isFalse);
    await tester.tap(find.byTooltip('Back to the start'));
    await pumpUntil(tester, () => life.generation == 0, reason: 'restarted');

    // Randomize puts a normal board down and leaves the plane.
    await tester.tap(find.byTooltip('Randomize'));
    await pumpUntil(tester, () => life.giant == null, reason: 'left the plane');
    expect(life.engineKind, isNot(EngineKind.hashlife));
    expect(life.population, greaterThan(1000));
  });

  testWidgets('the logo and the ⓘ open the about panel', (tester) async {
    await start(tester);
    // Wait for the panel to finish opening, not a fixed time: until its route's
    // transition completes it doesn't hold focus, so an Escape sent early goes
    // to the board instead (CI's slower runners caught exactly that).
    bool fullyOpen() {
      final close = find.byTooltip('Close');
      if (close.evaluate().isEmpty) return false;
      return ModalRoute.of(tester.element(close))?.animation?.isCompleted ?? false;
    }

    bool closed() => find.textContaining('John Horton Conway').evaluate().isEmpty;

    await tester.tap(find.bySemanticsLabel('About Life with AI'));
    await pumpUntil(tester, fullyOpen, reason: 'the about panel open, from the logo');
    expect(find.textContaining('John Horton Conway in 1970'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await pumpUntil(tester, closed, reason: 'closed by its ✕');

    await tester.tap(find.byTooltip('About this app'));
    await pumpUntil(tester, fullyOpen, reason: 'the about panel open, from the ⓘ');
    expect(find.textContaining('Shane Kearney'), findsOneWidget);
    await frames(tester, 100); // one more beat for focus to land in the panel
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpUntil(tester, closed, reason: 'closed by Escape');
  });

  testWidgets("a share link shows the sender's colors, and Keep makes them yours", (tester) async {
    final seed = Grid(512, 384);
    patternLibrary['r_pentomino']!.stampOnto(seed, 250, 180);
    final app = await start(tester, launchUri: Uri.parse(ShareLink.forSeed(seed, title: 'Warm', palette: BoardPalette.ember)));
    final life = app.controller;
    expect(life.palette, BoardPalette.ember, reason: 'drawn in the sender\'s colors');
    expect(life.ownPalette, BoardPalette.neon, reason: 'but not made the viewer\'s own');
    expect(find.byTooltip('Board colors · Ember'), findsOneWidget);

    await tester.tap(find.text('Keep'));
    await pumpUntil(tester, () => life.sharedPalette == null, reason: 'kept');
    expect(life.ownPalette, BoardPalette.ember);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); // the save is async
    expect((await SharedPreferences.getInstance()).getString('board_palette'), 'ember', reason: 'kept on the device');
  });

  testWidgets('a share link plays its seed, and its card can replay it and save it', (tester) async {
    // Not a pulsar: it repeats every 3 generations, so a "moment" saved at
    // generation 3 would be the very seed already hearted (and rightly refused).
    final seed = Grid(512, 384);
    patternLibrary['r_pentomino']!.stampOnto(seed, 250, 180);
    final app = await start(tester, launchUri: Uri.parse(ShareLink.forSeed(seed, title: 'A restless R-pentomino')));
    final life = app.controller;

    expect(life.running, isTrue);
    expect(life.population, seed.population);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Loaded a shared seed'), findsOneWidget);
    // The panel opens on Favorites, where the shared seed's card is pinned at the top.
    expect(find.text('SHARED WITH YOU'), findsOneWidget);
    expect(find.text('A restless R-pentomino'), findsOneWidget);
    expect(find.byTooltip('New chat'), findsNothing, reason: 'on the Favorites tab, not the Assistant');
    expect(app.assistant.favorites.items, isEmpty, reason: 'opening a link never saves it by itself');

    // The board moves on; the card's Replay puts the shared seed back at generation 0.
    await tester.tap(find.byTooltip('Clear'));
    await pumpUntil(tester, () => life.population == 0, reason: 'board cleared');
    await tester.tap(find.text('Replay seed'));
    await pumpUntil(tester, () => life.population == seed.population, reason: 'shared seed replayed');
    expect(life.generation, lessThan(5));

    // One tap saves it, titled with the sender's prompt.
    await tester.tap(find.byTooltip('Add to favorites'));
    await pumpUntil(tester, () => app.assistant.favorites.items.isNotEmpty, reason: 'saved');
    expect(app.assistant.favorites.items.single.title, 'A restless R-pentomino');

    // Heart the board mid-run: titled after the shared seed and its generation.
    await pumpUntil(tester, () => life.generation >= 3, reason: 'running on');
    await tester.tap(find.byTooltip('Save this moment to favorites'));
    await pumpUntil(tester, () => app.assistant.favorites.items.length == 2, reason: 'moment saved');
    expect(app.assistant.favorites.items.first.title, matches(RegExp(r'^A restless R-pentomino · gen \d+$')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Saved "A restless R-pentomino · gen'), findsOneWidget);

    // It isn't part of the conversation with Claude...
    await tester.tap(find.text('Assistant'));
    await tester.pump();
    expect(find.text('SHARED WITH YOU'), findsNothing);
    // ...it stays pinned at the top of Favorites, above the saved seeds.
    await tester.tap(find.bySemanticsLabel('Favorites, 2 saved'));
    await tester.pump();
    final savedMoment = find.textContaining(RegExp(r'^A restless R-pentomino · gen \d+$')); // not the toast
    expect(tester.getTopLeft(find.text('SHARED WITH YOU')).dy, lessThan(tester.getTopLeft(savedMoment).dy));
  });

  testWidgets('a broken share link falls back to a normal start and points to the Community tab', (tester) async {
    final app = await start(tester, launchUri: Uri.parse('${ShareLink.site}#seed=1_10x10_0_0_999o'));
    expect(app.controller.running, isFalse);
    expect(app.controller.population, greaterThan(0), reason: 'a normal random board instead');
    expect(find.textContaining('Loaded a shared seed'), findsNothing);
    await pumpUntil(tester, () => find.text("This seed didn't make it").evaluate().isNotEmpty, reason: 'the dialog');

    // "Just play" closes it, leaving the random board.
    await tester.tap(find.text('Just play'));
    await frames(tester, 400);
    expect(find.text("This seed didn't make it"), findsNothing);
    expect(find.text('Oscillator Garden'), findsNothing, reason: 'still on the Assistant tab');
  });

  testWidgets("a broken link's dialog can take you to the Community tab", (tester) async {
    await start(tester, launchUri: Uri.parse('${ShareLink.site}#seed=1_512x384_1'));
    await pumpUntil(tester, () => find.text("This seed didn't make it").evaluate().isNotEmpty, reason: 'the dialog');
    await tester.tap(find.text('Explore community seeds'));
    await pumpUntil(tester, () => find.text('Oscillator Garden').evaluate().isNotEmpty, reason: 'the Community tab open, seeds loaded');
    expect(find.text("This seed didn't make it"), findsNothing);
  });

  testWidgets('an ordinary visit says nothing about links', (tester) async {
    await start(tester, launchUri: Uri.parse(ShareLink.site.toString()));
    await frames(tester, 300);
    expect(find.text("This seed didn't make it"), findsNothing);
  });

  testWidgets('any moment of a hand-made board can be hearted, and an empty one is refused', (tester) async {
    final app = await start(tester);
    final life = app.controller;
    final favorites = app.assistant.favorites;

    // A random board, paused at a known generation.
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byTooltip('Step one generation (→)'));
      await pumpUntil(tester, () => life.generation == i + 1, reason: 'step ${i + 1}');
    }
    await tester.tap(find.byTooltip('Save this moment to favorites'));
    await pumpUntil(tester, () => favorites.items.isNotEmpty, reason: 'moment saved');
    expect(favorites.items.single.title, 'My board · gen 7');
    // Compare with an exact reading: the GPU engine refreshes its population count lazily.
    expect(favorites.items.single.seed.stateHash, (await life.captureMoment()).seed.stateHash);

    // Saving the identical board again is a no-op.
    await tester.tap(find.byTooltip('Save this moment to favorites'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('already in your favorites'), findsOneWidget);
    expect(favorites.items, hasLength(1));

    // Undo from a fresh save removes it again.
    await tester.tap(find.byTooltip('Step one generation (→)'));
    await pumpUntil(tester, () => life.generation == 8, reason: 'step 8');
    await tester.tap(find.byTooltip('Save this moment to favorites'));
    await pumpUntil(tester, () => favorites.items.length == 2, reason: 'second moment');
    await tapSnackBarAction(tester, 'Undo');
    await pumpUntil(tester, () => favorites.items.length == 1, reason: 'undo');

    // An empty board has nothing to keep.
    await tester.tap(find.byTooltip('Clear'));
    await pumpUntil(tester, () => life.population == 0, reason: 'cleared');
    await tester.tap(find.byTooltip('Save this moment to favorites'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('nothing to save'), findsOneWidget);
    expect(favorites.items, hasLength(1));
  });

  testWidgets('assistant run: experiment replays, then heart, recall and share the seed', (tester) async {
    Map<String, dynamic> reply(List<Map<String, dynamic>> content) => {
      'content': content,
      'stop_reason': 'tool_use',
      'usage': {'input_tokens': 100, 'output_tokens': 20},
    };
    final responses = [
      reply([
        {'type': 'text', 'text': 'Two gliders on a collision course.'},
        {'type': 'tool_use', 'id': 't1', 'name': 'clear_board', 'input': {}},
        {
          'type': 'tool_use',
          'id': 't2',
          'name': 'place_pattern',
          'input': {'name': 'glider', 'x': 100, 'y': 100},
        },
        {
          'type': 'tool_use',
          'id': 't3',
          'name': 'place_pattern',
          'input': {'name': 'glider', 'x': 130, 'y': 100, 'rotation': 90},
        },
        {
          'type': 'tool_use',
          'id': 't4',
          'name': 'simulate',
          'input': {'generations': 60},
        },
      ]),
      reply([
        {
          'type': 'tool_use',
          'id': 't5',
          'name': 'finish',
          'input': {'summary': 'Two gliders meet and annihilate.'},
        },
      ]),
    ];
    final requests = <Map<String, dynamic>>[];
    final api = MockClient((req) async {
      requests.add(jsonDecode(req.body) as Map<String, dynamic>);
      // A little latency, like the real API, so the experiment replay can be seen.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return http.Response(jsonEncode(responses.removeAt(0)), 200);
    });
    final app = await start(tester, api: api);
    final life = app.controller;

    await tester.enterText(find.byType(TextField), 'Make two gliders collide');
    await tester.testTextInput.receiveAction(TextInputAction.done);

    // The experiment replays on the board while "Claude" thinks.
    await pumpUntil(tester, () => find.textContaining('EXPERIMENT 1').evaluate().isNotEmpty, reason: 'experiment overlay');
    // Then the finish card appears and the final seed plays.
    await pumpUntil(tester, () => find.text('Two gliders meet and annihilate.').evaluate().isNotEmpty, reason: 'finish card');
    await pumpUntil(tester, () => life.experiment == null && life.running, reason: 'hand-off to the final seed', seconds: 30);
    expect(requests, hasLength(2));
    expect(requests.first['messages'][0]['content'][0]['text'], 'Make two gliders collide');

    // Replay the seed after the board has moved on.
    await pumpUntil(tester, () => life.generation > 10, reason: 'seed running');
    await tester.tap(find.text('Replay seed'));
    await pumpUntil(tester, () => life.generation < 5, reason: 'replay from generation 0');
    expect(life.population, 10);

    // Heart it, then recall it from Favorites after clearing the board.
    await tester.tap(find.byTooltip('Add to favorites'));
    await pumpUntil(tester, () => find.bySemanticsLabel('Favorites, 1 saved').evaluate().isNotEmpty, reason: 'favorite saved');
    await tester.tap(find.byTooltip('Clear'));
    await pumpUntil(tester, () => life.population == 0, reason: 'board cleared');
    await tester.tap(find.bySemanticsLabel('Favorites, 1 saved'));
    await tester.pump();
    await tester.tap(find.text('Make two gliders collide'));
    // Wait for the seed itself: a cleared board keeps running, so the generation alone proves nothing.
    await pumpUntil(tester, () => life.population == 10, reason: 'favorite played');
    await tester.pump();
    expect(find.text('▶ Playing on the board'), findsOneWidget);

    // Its share link round-trips through the real clipboard.
    await tester.tap(find.byTooltip('Copy share link'));
    await tester.pump(const Duration(milliseconds: 200));
    final copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    final link = ShareLink.parse(Uri.parse(copied!))!;
    expect(link.seed.population, 10);
    expect(link.title, 'Make two gliders collide');
  });
}
