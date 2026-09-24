import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/engine/life_engine.dart';
import 'package:life_with_ai/main.dart';
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

  // A fresh, isolated store per test: never touch the developer's real key or favourites.
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

  Future<LifeApp> start(WidgetTester tester, {Uri? launchUri, http.Client? api, EngineKind engine = EngineKind.gpu}) async {
    // Tear down the previous test's app first. Pumping a new LifeApp over the
    // old one would let Flutter reuse the existing Navigator, whose screen is
    // still wired to the previous test's board and favourites.
    await tester.pumpWidget(const SizedBox());
    final app = await bootstrap(launchUri: launchUri, httpClient: api, engine: engine);
    // Unmount before disposing: a mounted board would paint with freed GPU images.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      app.controller.dispose();
    });
    await tester.pumpWidget(app);
    await tester.pump();
    return app;
  }

  testWidgets('boots, plays on the GPU engine, and hot-swaps to the CPU engine', (tester) async {
    final app = await start(tester);
    final life = app.controller;
    expect(find.text('Assistant'), findsOneWidget);
    expect(life.population, greaterThan(1000), reason: 'starts on a random board');

    await tester.tap(find.byTooltip('Play (space)'));
    await pumpUntil(tester, () => life.generation >= 20, reason: 'GPU engine advancing');

    await tester.tap(find.text('CPU · isolate'));
    await pumpUntil(tester, () => life.engineKind == EngineKind.cpu, reason: 'engine swap');
    final genAtSwap = life.generation;
    await pumpUntil(tester, () => life.generation >= genAtSwap + 20, reason: 'CPU engine advancing');
    expect(find.textContaining('CPU · isolate'), findsWidgets);
  });

  testWidgets('at the default window size the controls fit on one row', (tester) async {
    // The size MainFlutterWindow.swift opens at (a restored window may differ, so set it).
    tester.view.physicalSize = const Size(1440, 920) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await start(tester);
    await tester.pump();
    // Every control sits on the same row: with centred wrapping, one row means one centre line.
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
    for (final label in ['Assistant', 'Favourites', 'Community']) {
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

    await tester.tap(find.byTooltip('Save this moment to favourites'));
    await pumpUntil(tester, () => find.textContaining('to favourites').evaluate().isNotEmpty, reason: 'toast shown');
    await frames(tester, 400); // let it finish sliding in

    final toast = tester.getRect(find.ancestor(of: find.textContaining('to favourites'), matching: find.byType(Container)).first);
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

  testWidgets('the logo and the ⓘ open the about panel', (tester) async {
    await start(tester);
    await tester.tap(find.bySemanticsLabel('About Life with AI'));
    await frames(tester, 400);
    expect(find.textContaining('John Horton Conway in 1970'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await frames(tester, 400);
    await tester.tap(find.byTooltip('About this app'));
    await frames(tester, 400);
    expect(find.textContaining('Shane Kearney'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester, 400);
    expect(find.textContaining('John Horton Conway'), findsNothing);
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
    // The panel opens on Favourites, where the shared seed's card is pinned at the top.
    expect(find.text('SHARED WITH YOU'), findsOneWidget);
    expect(find.text('A restless R-pentomino'), findsOneWidget);
    expect(find.byTooltip('New chat'), findsNothing, reason: 'on the Favourites tab, not the Assistant');
    expect(app.assistant.favorites.items, isEmpty, reason: 'opening a link never saves it by itself');

    // The board moves on; the card's Replay puts the shared seed back at generation 0.
    await tester.tap(find.byTooltip('Clear'));
    await pumpUntil(tester, () => life.population == 0, reason: 'board cleared');
    await tester.tap(find.text('Replay seed'));
    await pumpUntil(tester, () => life.population == seed.population, reason: 'shared seed replayed');
    expect(life.generation, lessThan(5));

    // One tap saves it, titled with the sender's prompt.
    await tester.tap(find.byTooltip('Add to favourites'));
    await pumpUntil(tester, () => app.assistant.favorites.items.isNotEmpty, reason: 'saved');
    expect(app.assistant.favorites.items.single.title, 'A restless R-pentomino');

    // Heart the board mid-run: titled after the shared seed and its generation.
    await pumpUntil(tester, () => life.generation >= 3, reason: 'running on');
    await tester.tap(find.byTooltip('Save this moment to favourites'));
    await pumpUntil(tester, () => app.assistant.favorites.items.length == 2, reason: 'moment saved');
    expect(app.assistant.favorites.items.first.title, matches(RegExp(r'^A restless R-pentomino · gen \d+$')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Saved "A restless R-pentomino · gen'), findsOneWidget);

    // It isn't part of the conversation with Claude...
    await tester.tap(find.text('Assistant'));
    await tester.pump();
    expect(find.text('SHARED WITH YOU'), findsNothing);
    // ...it stays pinned at the top of Favourites, above the saved seeds.
    await tester.tap(find.bySemanticsLabel('Favourites, 2 saved'));
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
    await tester.tap(find.byTooltip('Save this moment to favourites'));
    await pumpUntil(tester, () => favorites.items.isNotEmpty, reason: 'moment saved');
    expect(favorites.items.single.title, 'My board · gen 7');
    // Compare with an exact reading: the GPU engine refreshes its population count lazily.
    expect(favorites.items.single.seed.stateHash, (await life.captureMoment()).seed.stateHash);

    // Saving the identical board again is a no-op.
    await tester.tap(find.byTooltip('Save this moment to favourites'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('already in your favourites'), findsOneWidget);
    expect(favorites.items, hasLength(1));

    // Undo from a fresh save removes it again.
    await tester.tap(find.byTooltip('Step one generation (→)'));
    await pumpUntil(tester, () => life.generation == 8, reason: 'step 8');
    await tester.tap(find.byTooltip('Save this moment to favourites'));
    await pumpUntil(tester, () => favorites.items.length == 2, reason: 'second moment');
    await tapSnackBarAction(tester, 'Undo');
    await pumpUntil(tester, () => favorites.items.length == 1, reason: 'undo');

    // An empty board has nothing to keep.
    await tester.tap(find.byTooltip('Clear'));
    await pumpUntil(tester, () => life.population == 0, reason: 'cleared');
    await tester.tap(find.byTooltip('Save this moment to favourites'));
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

    // Heart it, then recall it from Favourites after clearing the board.
    await tester.tap(find.byTooltip('Add to favourites'));
    await pumpUntil(tester, () => find.bySemanticsLabel('Favourites, 1 saved').evaluate().isNotEmpty, reason: 'favourite saved');
    await tester.tap(find.byTooltip('Clear'));
    await pumpUntil(tester, () => life.population == 0, reason: 'board cleared');
    await tester.tap(find.bySemanticsLabel('Favourites, 1 saved'));
    await tester.pump();
    await tester.tap(find.text('Make two gliders collide'));
    // Wait for the seed itself: a cleared board keeps running, so the generation alone proves nothing.
    await pumpUntil(tester, () => life.population == 10, reason: 'favourite played');
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
