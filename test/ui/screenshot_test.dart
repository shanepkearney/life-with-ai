import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/app/screenshot/screenshot.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/home_page.dart';
import 'package:life_with_ai/ui/theme.dart';

void main() {
  test('file names sort by time and are safe everywhere', () {
    expect(screenshotFileName(DateTime(2026, 9, 4, 7, 3, 9)), 'life-with-ai-2026-09-04-070309.png');
  });

  for (final (label, size) in [('desktop', const Size(1440, 900)), ('phone', const Size(390, 844))]) {
    testWidgets('the camera button saves the whole window as a PNG ($label)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late LifeController life;
      await tester.runAsync(() async {
        life = LifeController(await Shaders.load());
        await life.init();
      });
      final saved = <(Uint8List, String)>[];
      final toastsInShot = <int>[];
      Future<SavedPng?> save(Uint8List png, String name) async {
        saved.add((png, name));
        toastsInShot.add(find.text('Loaded a shared seed.').evaluate().length);
        return (label: 'Downloads', file: null);
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: Neon.theme(),
          home: HomePage(controller: life, notice: const LaunchNotice('Loaded a shared seed.'), saveScreenshot: save),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Loaded a shared seed.'), findsOneWidget);
      await tester.tap(find.byTooltip('Save a screenshot'));
      for (var i = 0; i < 20 && saved.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pump();

      expect(saved, hasLength(1));
      expect(toastsInShot, [0], reason: 'toasts are left out of the picture');
      final (png, name) = saved.single;
      expect(name, startsWith('life-with-ai-'));
      final image = await tester.runAsync(() async => (await (await ui.instantiateImageCodec(png)).getNextFrame()).image);
      // The whole window, at 2× even on a 1× screen.
      expect((image!.width, image.height), (size.width * 2, size.height * 2));
      expect(find.text('Screenshot saved to Downloads'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      life.dispose();
    });
  }
}
