import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/main.dart';
import 'package:life_with_ai/ui/control_bar.dart';
import 'package:life_with_ai/ui/mobile_controls.dart';
import 'package:life_with_ai/ui/mobile_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone layout, end to end on the real app at phone sizes. Any layout
/// overflow fails these tests.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({'anthropic_api_key': 'sk-test'}));

  Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {String? reason, int seconds = 20}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for: ${reason ?? 'condition'}');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> frames(WidgetTester tester, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Boots the app on a screen of [size] logical pixels.
  Future<LifeApp> startOn(WidgetTester tester, Size size, {Uri? launchUri}) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const SizedBox());
    final app = await bootstrap(launchUri: launchUri);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      app.controller.dispose();
    });
    await tester.pumpWidget(app);
    await frames(tester, 200);
    return app;
  }

  const phones = {'iPhone SE': Size(375, 667), 'iPhone 15': Size(393, 852), 'Pixel 7': Size(412, 915), 'landscape': Size(852, 393)};

  for (final MapEntry(key: name, value: size) in phones.entries) {
    testWidgets('$name: phone layout, controls on one row, nothing overflows', (tester) async {
      final app = await startOn(tester, size);
      expect(find.byType(MobileControls), findsOneWidget);
      expect(find.byType(MobileSheet), findsOneWidget);
      expect(find.byType(ControlBar), findsNothing, reason: 'the desktop control bar is not used on phones');
      final strip = tester.renderObject<RenderBox>(find.byType(MobileControls));
      expect(strip.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(strip.size.width), reason: 'controls fit on one row');
      expect(app.controller.boardSize, BoardSize.portrait, reason: 'phones start on the portrait board');
      // Real fonts: all three tab labels fit whole, none cut short with an ellipsis.
      for (final label in ['Assistant', 'Favorites', 'Community']) {
        expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isFalse, reason: '"$label" is cut off');
      }
    });
  }

  testWidgets('with the ⬇ for the macOS app, the phone header still fits', (tester) async {
    for (final size in phones.values) {
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      await tester.pumpWidget(const SizedBox());
      final app = await bootstrap(offerMacDownload: true);
      await tester.pumpWidget(app);
      await frames(tester, 200);
      expect(find.byTooltip('Get the macOS app'), findsOneWidget);
      // Real fonts: the logo, ⓘ, 📷 and ⬇ fit, with the HUD scaled rather than overflowing.
      for (final tip in ['About this app', 'Save a screenshot', 'Get the macOS app']) {
        final r = tester.getRect(find.byTooltip(tip));
        expect(r.right, lessThanOrEqualTo(size.width), reason: '$tip on ${size.width}');
      }
      await tester.pumpWidget(const SizedBox());
      app.controller.dispose();
    }
    tester.view.resetPhysicalSize();
  });

  testWidgets('Board only on a phone: the bar fits, fades, and a tap brings it back', (tester) async {
    await startOn(tester, const Size(375, 667));
    await tester.tap(find.byTooltip('Board only (B)'));
    await frames(tester, 300);
    final leave = find.byTooltip('Leave board only (Esc)');
    expect(tester.getRect(leave).right, lessThanOrEqualTo(375));
    await frames(tester, 3000); // longer than the bar lingers
    bool shown() => !tester.widget<IgnorePointer>(find.ancestor(of: leave, matching: find.byType(IgnorePointer)).first).ignoring;
    expect(shown(), isFalse);
    await tester.tapAt(const Offset(187, 300));
    await frames(tester, 300);
    expect(shown(), isTrue);
    await tester.tap(leave);
    await frames(tester, 300);
    expect(find.byType(MobileControls), findsOneWidget);
  });

  testWidgets('the about panel opens from the phone header too', (tester) async {
    await startOn(tester, const Size(375, 667));
    await tester.tap(find.byTooltip('About this app'));
    await frames(tester, 400);
    expect(find.textContaining('John Horton Conway in 1970'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await frames(tester, 400);
  });

  testWidgets('desktop sizes keep the desktop layout', (tester) async {
    await startOn(tester, const Size(1440, 920));
    expect(find.byType(ControlBar), findsOneWidget);
    expect(find.byType(MobileControls), findsNothing);
    expect(find.byType(MobileSheet), findsNothing);
  });

  testWidgets('the resting sheet is three tabs, each opening the sheet on its own view', (tester) async {
    await startOn(tester, const Size(393, 852));
    final sheet = find.byType(MobileSheet);
    double sheetTop() => tester.getRect(find.descendant(of: sheet, matching: find.byType(AnimatedContainer)).first).top;
    final resting = sheetTop();

    // At rest: just the three tabs. The chat, message box and buttons wait for the sheet to open.
    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'message box hidden at rest');
    for (final tip in ['New chat', 'Settings']) {
      expect(find.byTooltip(tip), findsNothing, reason: '$tip hidden at rest');
    }

    // Favorites opens the sheet straight onto favorites.
    await tester.tap(find.text('Favorites'));
    await frames(tester, 400);
    expect(sheetTop(), lessThan(resting - 200), reason: 'opened over the board');
    expect(find.textContaining('No favorites yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'no message box on the favorites view');
    for (final tip in ['New chat', 'Settings']) {
      expect(find.byTooltip(tip), findsNothing, reason: '$tip belongs to the Assistant view, not Favorites');
    }

    // The same tabs switch views while open: Community lists the contributed seeds.
    await tester.tap(find.text('Community'));
    await frames(tester, 200);
    expect(find.text('How to contribute'), findsOneWidget);
    expect(find.textContaining('by @shanepkearney', findRichText: true), findsWidgets);
    expect(find.byType(TextField), findsNothing, reason: 'no message box on the community view');

    await tester.tap(find.text('Assistant'));
    await frames(tester, 200);
    expect(find.textContaining('Two glider fleets'), findsOneWidget, reason: 'chat view with example prompts');
    expect(find.byType(TextField), findsOneWidget);
    for (final tip in ['New chat', 'Settings']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: '$tip in the Assistant view');
    }

    // A drag down on the handle returns it to rest, where everything but the tabs hides again.
    await tester.drag(find.bySemanticsLabel('Collapse the assistant'), const Offset(0, 500));
    await frames(tester, 400);
    expect(sheetTop(), closeTo(resting, 1));
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('New chat'), findsNothing);

    // Assistant at rest opens on the chat.
    await tester.tap(find.text('Assistant'));
    await frames(tester, 400);
    expect(find.byType(TextField), findsOneWidget);

    // A half-typed message survives closing and reopening the sheet.
    await tester.enterText(find.byType(TextField), 'Two gliders, then');
    await tester.drag(find.bySemanticsLabel('Collapse the assistant'), const Offset(0, 500));
    await frames(tester, 400);
    await tester.tap(find.text('Assistant'));
    await frames(tester, 400);
    expect(find.text('Two gliders, then'), findsOneWidget);
  });

  testWidgets('saving a moment on a phone: the toast clears the controls and the sheet', (tester) async {
    final app = await startOn(tester, const Size(393, 852));
    await tester.tap(find.byTooltip('Save this moment to favorites'));
    await pumpUntil(tester, () => app.assistant.favorites.items.isNotEmpty, reason: 'saved');
    expect(app.assistant.favorites.items.single.title, startsWith('My board · gen'));
    await pumpUntil(tester, () => find.textContaining('to favorites').evaluate().isNotEmpty, reason: 'toast');
    await frames(tester, 400);
    final toast = tester.getRect(find.ancestor(of: find.textContaining('to favorites'), matching: find.byType(Container)).first);
    final controls = tester.getRect(find.byType(MobileControls));
    expect(toast.bottom, lessThanOrEqualTo(controls.top), reason: 'toast $toast vs controls $controls');
    // The resting Favorites tab shows the count without opening the sheet.
    expect(find.bySemanticsLabel('Favorites, 1 saved'), findsOneWidget);
  });

  testWidgets('on a phone, a broken link\'s dialog opens the sheet on the Community tab', (tester) async {
    await startOn(tester, const Size(393, 852), launchUri: Uri.parse('${ShareLink.site}#seed=not-a-seed&title=Oops'));
    await pumpUntil(tester, () => find.text("This seed didn't make it").evaluate().isNotEmpty, reason: 'the dialog');
    expect(find.text('How to contribute'), findsNothing, reason: 'sheet still at rest');
    await tester.tap(find.text('Explore community seeds'));
    await pumpUntil(tester, () => find.text('How to contribute').evaluate().isNotEmpty, reason: 'sheet open on Community');
  });

  testWidgets('share links work across layouts: a desktop seed on a phone, a phone seed on desktop', (tester) async {
    final desktopSeed = Grid(512, 384);
    patternLibrary['r_pentomino']!.stampOnto(desktopSeed, 250, 180);
    var app = await startOn(tester, const Size(393, 852), launchUri: Uri.parse(ShareLink.forSeed(desktopSeed, title: 'From a desktop')));
    expect(app.controller.boardSize, BoardSize.medium, reason: 'adopts the sender\'s board');
    // On a phone the sheet opens by itself, on Favorites, so the "Shared with you" card is seen.
    expect(find.text('SHARED WITH YOU'), findsOneWidget);
    expect(find.byTooltip('New chat'), findsNothing, reason: 'Favorites, not the Assistant');
    // It plays immediately, so check the seed that arrived rather than a live count.
    expect(app.assistant.shared!.seed.stateHash, desktopSeed.stateHash);
    expect(app.controller.running, isTrue);
    // The open sheet covers the control strip; close it like a person would to reach ⚙.
    await tester.drag(find.bySemanticsLabel('Collapse the assistant'), const Offset(0, 500));
    await frames(tester, 400);
    await tester.tap(find.byTooltip('Speed, glow and engine'));
    await frames(tester, 400);
    expect(find.text('512×384'), findsOneWidget);
    await tester.tapAt(const Offset(200, 60)); // dismiss the tuning sheet
    await frames(tester, 400);

    final phoneSeed = Grid(192, 256);
    patternLibrary['r_pentomino']!.stampOnto(phoneSeed, 90, 120);
    app = await startOn(tester, const Size(1440, 920), launchUri: Uri.parse(ShareLink.forSeed(phoneSeed, title: 'From a phone')));
    expect(app.controller.boardSize, BoardSize.portrait);
    expect(find.text('192×256'), findsOneWidget, reason: 'the desktop dropdown shows the adopted size');
  });
}
