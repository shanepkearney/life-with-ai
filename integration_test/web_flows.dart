// The web build, in a real browser (headless Chrome, via ChromeDriver):
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/web_flows.dart -d web-server --release
//
// Everything else in integration_test/ runs the macOS app. These cover what
// only the web build does: reading the page address, downloading through the
// browser, telling a Mac browser apart, and the shaders under the browser's
// renderer. (The name doesn't end in _test, so `flutter test integration_test`
// on macOS leaves it alone.)
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:life_with_ai/app/platform/mac_user_agent.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {required String reason, int seconds = 30}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for: $reason');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Puts [fragment] in the page's address, as a visitor opening a link would
  /// see it, and returns what the app reads at startup (`Uri.base`).
  Uri addressWith(String fragment) {
    web.window.history.replaceState(null, '', '${web.window.location.pathname}$fragment');
    return Uri.base;
  }

  Future<LifeApp> start(WidgetTester tester, {Uri? launchUri, bool autoplay = false}) async {
    await tester.pumpWidget(const SizedBox());
    final app = await bootstrap(launchUri: launchUri, autoplay: autoplay);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      app.controller.dispose();
      web.window.history.replaceState(null, '', web.window.location.pathname);
    });
    await tester.pumpWidget(app);
    await tester.pump();
    return app;
  }

  testWidgets('boots and plays, with the GPU shaders running in the browser', (tester) async {
    final app = await start(tester, autoplay: true);
    await pumpUntil(tester, () => app.controller.generation >= 20, reason: 'the board advancing');
    expect(app.controller.population, greaterThan(0));
  });

  testWidgets('a share link in the page address opens on its seed', (tester) async {
    final seed = Grid(512, 384);
    patternLibrary['r_pentomino']!.stampOnto(seed, 250, 180);
    final link = Uri.parse(ShareLink.forSeed(seed, title: 'From the address bar', note: 'A note that came with it.'));
    final app = await start(tester, launchUri: addressWith('#${link.fragment}'));
    expect(app.assistant.shared?.seed.stateHash, seed.stateHash);
    expect(app.controller.boardTitle, 'From the address bar');
    await pumpUntil(tester, () => find.text('A note that came with it.').evaluate().isNotEmpty, reason: 'the shared card with its note');
  });

  testWidgets('a broken link in the page address explains itself', (tester) async {
    await start(tester, launchUri: addressWith('#seed=1_512x384_1'));
    await pumpUntil(tester, () => find.text("This seed didn't make it").evaluate().isNotEmpty, reason: 'the broken-link dialog');
  });

  testWidgets('community seeds load over HTTP when the tab opens', (tester) async {
    await start(tester);
    await tester.tap(find.text('Community'));
    await pumpUntil(tester, () => find.text('Oscillator Garden').evaluate().isNotEmpty, reason: 'the community seeds');
  });

  testWidgets('📷 downloads a PNG through the browser', (tester) async {
    await start(tester);
    // Catch the download link's click as it happens (and stop the actual save).
    String? fileName, href;
    final onClick = ((web.Event e) {
      final target = e.target;
      if (target == null || !target.isA<web.HTMLAnchorElement>()) return;
      final anchor = target as web.HTMLAnchorElement;
      if (anchor.download.isEmpty) return;
      fileName = anchor.download;
      href = anchor.href;
      e.preventDefault();
    }).toJS;
    web.document.addEventListener('click', onClick, true.toJS);
    addTearDown(() => web.document.removeEventListener('click', onClick, true.toJS));

    await tester.tap(find.byTooltip('Save a screenshot'));
    await pumpUntil(tester, () => fileName != null, reason: 'the download');
    expect(fileName, matches(RegExp(r'^life-with-ai-\d{4}-\d{2}-\d{2}-\d{6}\.png$')));
    expect(href, startsWith('blob:'));
    await pumpUntil(tester, () => find.text('Screenshot saved to your downloads').evaluate().isNotEmpty, reason: 'the confirmation');
  });

  testWidgets("the ⬇ for the macOS app follows the browser's own Mac check", (tester) async {
    await start(tester);
    final nav = web.window.navigator;
    final mac = looksLikeMac(nav.userAgent, nav.maxTouchPoints);
    expect(find.byTooltip('Get the macOS app'), mac ? findsOneWidget : findsNothing, reason: nav.userAgent);
  });

  testWidgets('a long run, then a new board: the image chains are cut on the web too', (tester) async {
    final app = await start(tester);
    final life = app.controller;
    for (var i = 0; i < 600; i++) {
      await tester.runAsync(life.stepOnce); // crosses the 128-pass detach several times
      if (i % 25 == 0) await tester.pump(const Duration(milliseconds: 16));
    }
    expect(life.generation, 600);
    final seed = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(seed, 10, 10);
    await tester.runAsync(() => life.playSeed(seed, title: 'After a long run'));
    await pumpUntil(tester, () => life.generation > 0, reason: 'the new board playing');
  });
}
