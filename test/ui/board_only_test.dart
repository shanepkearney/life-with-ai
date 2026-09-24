import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/app/platform/full_screen.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/board_only.dart';
import 'package:life_with_ai/ui/control_bar.dart';
import 'package:life_with_ai/ui/home_page.dart';
import 'package:life_with_ai/ui/theme.dart';

/// Records what the page asks for; can refuse, like a browser without a click.
class FakeFullScreen extends NoFullScreen {
  FakeFullScreen({this.supported = true, this.refuse = false});

  @override
  final bool supported;
  final bool refuse;
  final calls = <bool>[];

  @override
  Future<void> set(bool on) async {
    calls.add(on);
    if (!refuse) active.value = on;
  }
}

void main() {
  late LifeController life;

  Future<void> start(WidgetTester tester, FakeFullScreen fullScreen, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load());
      await life.init();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Neon.theme(),
        home: HomePage(controller: life, fullScreen: fullScreen),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      life.dispose();
    });
  }

  bool barShown(WidgetTester tester) => !tester.widget<IgnorePointer>(
    find.ancestor(of: find.byTooltip('Leave board only (Esc)'), matching: find.byType(IgnorePointer)).first,
  ).ignoring;

  testWidgets('Board only shows just the board, goes full screen, and the ✕ brings everything back', (tester) async {
    final fs = FakeFullScreen();
    await start(tester, fs);
    expect(find.byType(ControlBar), findsOneWidget);

    await tester.tap(find.byTooltip('Board only (B)'));
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsOneWidget);
    expect(find.byType(ControlBar), findsNothing, reason: 'nothing but the board');
    expect(find.byTooltip('Save a screenshot'), findsNothing);
    expect(fs.calls, [true]);
    expect(barShown(tester), isTrue, reason: 'shown on entry, so it is clear how to leave');

    await tester.tap(find.byTooltip('Leave board only (Esc)'));
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsNothing);
    expect(find.byType(ControlBar), findsOneWidget);
    expect(fs.calls, [true, false], reason: 'it went full screen by itself, so it leaves it too');
  });

  testWidgets('the bar fades after a moment of stillness and comes back with the mouse', (tester) async {
    await start(tester, FakeFullScreen());
    await tester.tap(find.byTooltip('Board only (B)'));
    await tester.pump();
    await tester.pump(BoardOnlyView.linger + const Duration(milliseconds: 400));
    expect(barShown(tester), isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 300));
    await mouse.moveTo(const Offset(720, 320));
    await tester.pump();
    expect(barShown(tester), isTrue);
    await mouse.removePointer();
  });

  testWidgets('a tap wakes the bar instead of drawing', (tester) async {
    await start(tester, FakeFullScreen());
    if (life.running) life.toggleRunning(); // paused, so any change would be a drawn cell
    await tester.tap(find.byTooltip('Board only (B)'));
    await tester.pump();
    await tester.pump(BoardOnlyView.linger + const Duration(milliseconds: 400));
    final before = life.population;
    await tester.tapAt(const Offset(720, 450));
    await tester.pump();
    expect(barShown(tester), isTrue);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(life.population, before, reason: 'no cell drawn');
  });

  testWidgets("the bar's playback buttons work", (tester) async {
    await start(tester, FakeFullScreen());
    await tester.tap(find.byTooltip('Board only (B)'));
    await tester.pump();
    if (life.running) {
      await tester.tap(find.byTooltip('Pause (space)'));
      await tester.pump();
    }
    expect(life.running, isFalse);
    final gen = life.generation;
    await tester.tap(find.byTooltip('Step one generation (→)'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(life.generation, gen + 1);
    await tester.tap(find.byTooltip('Play (space)'));
    await tester.pump();
    expect(life.running, isTrue);
  });

  testWidgets('Esc and B leave it; B enters it', (tester) async {
    await start(tester, FakeFullScreen());
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsNothing);
  });

  testWidgets('leaving full screen some other way (Esc in a browser, the green button) leaves Board only too', (tester) async {
    final fs = FakeFullScreen();
    await start(tester, fs);
    await tester.tap(find.byTooltip('Board only (B)'));
    await tester.pump();
    fs.active.value = false; // the browser or window left full screen by itself
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsNothing);
  });

  testWidgets('if full screen is refused, Board only still fills the window', (tester) async {
    final fs = FakeFullScreen(refuse: true);
    await start(tester, fs);
    await tester.tap(find.byTooltip('Board only (B)'));
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsOneWidget);
    await tester.tap(find.byTooltip('Leave board only (Esc)'));
    await tester.pump();
    expect(fs.calls, [true], reason: "it never went full screen, so there's nothing to leave");
  });

  testWidgets('without full screen (an iPhone), there is no ⛶ and Board only just fills the window', (tester) async {
    final fs = FakeFullScreen(supported: false);
    await start(tester, fs);
    expect(find.byTooltip('Full screen (F)'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.tap(find.byTooltip('Board only (B)'));
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsOneWidget);
    expect(fs.calls, isEmpty);
  });

  testWidgets('⛶ and F toggle full screen for the whole app', (tester) async {
    final fs = FakeFullScreen();
    await start(tester, fs);
    await tester.tap(find.byTooltip('Full screen (F)'));
    await tester.pump();
    expect(fs.active.value, isTrue);
    expect(find.byTooltip('Exit full screen (F)'), findsOneWidget);
    expect(find.byType(ControlBar), findsOneWidget, reason: 'the whole app, not Board only');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(fs.active.value, isFalse);
    expect(fs.calls, [true, false]);
  });

  testWidgets('on a phone: the header offers Board only, and it works', (tester) async {
    final fs = FakeFullScreen();
    await start(tester, fs, size: const Size(390, 844));
    expect(find.byTooltip('Full screen (F)'), findsNothing, reason: 'Board only goes full screen itself; the header is tight');
    await tester.tap(find.byTooltip('Board only (B)'));
    await tester.pump();
    expect(find.byType(BoardOnlyView), findsOneWidget);
    expect(fs.calls, [true]);
  });
}
