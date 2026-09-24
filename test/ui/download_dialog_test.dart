import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/downloads.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/about_modal.dart';
import 'package:life_with_ai/ui/download_dialog.dart';
import 'package:life_with_ai/ui/home_page.dart';
import 'package:life_with_ai/ui/theme.dart';

void main() {
  Widget host(void Function(BuildContext) onOpen) => MaterialApp(
    theme: Neon.theme(),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(onPressed: () => onOpen(context), child: const Text('open')),
      ),
    ),
  );

  test('the download link always serves the latest release', () {
    expect(Downloads.macDmg.toString(), 'https://github.com/shanepkearney/life-with-ai/releases/latest/download/Life-with-AI.dmg');
  });

  testWidgets('the download dialog offers the DMG and explains opening an unsigned app', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(host((c) => showMacDownloadDialog(c, openUrl: (u) async => opened.add(u))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Life with AI for macOS'), findsOneWidget);
    expect(find.textContaining('Apple silicon and Intel'), findsOneWidget);
    expect(find.textContaining('Open Anyway'), findsOneWidget);
    expect(find.textContaining("isn't signed with an Apple Developer ID"), findsOneWidget);

    await tester.tap(find.text('Download for macOS'));
    expect(opened, [Downloads.macDmg]);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Life with AI for macOS'), findsNothing);
  });

  testWidgets('the about panel links to it only when offered', (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host((c) => showAboutModal(c, openUrl: (_) async {}, offerMacDownload: false)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Get the macOS app'), findsNothing, reason: 'off the web, you already have the app');
    await tester.pumpWidget(const SizedBox()); // a fresh screen, not a second panel over the first

    await tester.pumpWidget(host((c) => showAboutModal(c, openUrl: (_) async {}, offerMacDownload: true)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get the macOS app'));
    await tester.pumpAndSettle();
    expect(find.text('Life with AI for macOS'), findsOneWidget);
  });

  for (final (label, size) in [('desktop', const Size(1440, 900)), ('phone', const Size(390, 844))]) {
    testWidgets('the header ⬇ appears only when offered, and opens the dialog ($label)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late LifeController life;
      await tester.runAsync(() async {
        life = LifeController(await Shaders.load());
        await life.init();
      });
      for (final offer in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: Neon.theme(),
            home: HomePage(controller: life, offerMacDownload: offer),
          ),
        );
        await tester.pump();
        expect(find.byTooltip('Get the macOS app'), offer ? findsOneWidget : findsNothing);
      }
      await tester.tap(find.byTooltip('Get the macOS app'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Life with AI for macOS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      life.dispose();
    });
  }
}
