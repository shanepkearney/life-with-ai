import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/render/board_palette.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/favorites_view.dart';
import 'package:life_with_ai/ui/home_page.dart';
import 'package:life_with_ai/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'board_only_test.dart' show FakeFullScreen;

void main() {
  late LifeController life;
  late List<BoardPalette> saved;

  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load());
      await life.init();
    });
    saved = [];
    life.onPaletteChosen = saved.add;
  }

  Future<void> start(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await boot(tester);
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the swatch beside Glow opens the colors, and a preset recolors the board at once', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('Board colors · Neon'));
    await settle(tester);
    expect(find.text('Board colors'), findsOneWidget);
    for (final p in BoardPalette.presets) {
      expect(find.text(p.name), findsOneWidget);
    }
    final reset = find.widgetWithText(TextButton, 'Reset to Neon');
    expect(tester.widget<TextButton>(reset).onPressed, isNull, reason: 'already Neon');

    await tester.tap(find.text('Ember'));
    await settle(tester);
    expect(life.palette, BoardPalette.ember);
    expect(life.pipeline.palette, BoardPalette.ember, reason: 'the shader draws it straight away');
    expect(saved, [BoardPalette.ember], reason: 'kept on the device');

    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('Board colors'), findsNothing);
    expect(find.byTooltip('Board colors · Ember'), findsOneWidget);
  });

  testWidgets('any color can be edited, by hex too, and Reset to Neon puts the theme back', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('Board colors · Neon'));
    await settle(tester);

    await tester.tap(find.byTooltip('Background'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '#102030');
    await settle(tester);
    expect(BoardPalette.hex(life.palette.background), '102030');
    expect(life.palette.isPreset, isFalse);
    expect(find.text('EDIT A COLOR · CUSTOM'), findsOneWidget);
    expect(BoardPalette.hex(life.palette.heat[1]), BoardPalette.hex(BoardPalette.neon.heat[1]), reason: 'the rest untouched');

    final hue = find.descendant(
      of: find.ancestor(of: find.text('Hue'), matching: find.byType(Row)).first,
      matching: find.byType(Slider),
    );
    await tester.drag(hue, const Offset(60, 0));
    await settle(tester);
    expect(BoardPalette.hex(life.palette.background), isNot('102030'));

    await tester.tap(find.text('Reset to Neon'));
    await settle(tester);
    expect(life.palette, BoardPalette.neon);
    expect(saved.last, BoardPalette.neon);
  });

  testWidgets('on a phone the colors are in the ⚙ sheet, and the dialog fits', (tester) async {
    await start(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('Speed, glow and engine'));
    await settle(tester);
    await tester.tap(find.text('Colors'));
    await settle(tester);
    expect(find.text('Board colors'), findsOneWidget);
    expect(find.text('Speed · 15 generations/s'), findsNothing, reason: 'the sheet made way for the board');

    await tester.tap(find.text('Aurora'));
    await settle(tester);
    expect(life.palette, BoardPalette.aurora);
    expect(tester.takeException(), isNull, reason: 'no overflow at phone width');
  });

  testWidgets("a shared link's colors: Keep makes them yours, Use mine goes back", (tester) async {
    SharedPreferences.setMockInitialValues({});
    await boot(tester);
    addTearDown(life.dispose);
    final favorites = FavoritesStore();
    await tester.runAsync(favorites.load);
    final seed = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(seed, 100, 100);
    life.choosePalette(BoardPalette.forest);
    await tester.pumpWidget(
      MaterialApp(
        theme: Neon.theme(),
        home: Scaffold(
          body: FavoritesView(favorites: favorites, life: life, shared: (seed: seed, title: 'A glider', note: null, palette: BoardPalette.ember)),
        ),
      ),
    );

    expect(find.text("Sender's colors"), findsNothing, reason: 'nothing to offer until the colors are showing');
    life.showSharedPalette(BoardPalette.ember, seed: seed);
    await tester.pump();
    expect(find.text("Sender's colors"), findsOneWidget);

    await tester.tap(find.text('Use mine'));
    await tester.pump();
    expect((life.palette, life.ownPalette), (BoardPalette.forest, BoardPalette.forest));
    expect(find.text("Sender's colors"), findsNothing);

    life.showSharedPalette(BoardPalette.ember, seed: seed);
    await tester.pump();
    await tester.tap(find.text('Keep'));
    await tester.pump();
    expect((life.palette, life.ownPalette), (BoardPalette.ember, BoardPalette.ember));
    expect(saved.last, BoardPalette.ember);
    await tester.pumpWidget(const SizedBox());
  });
}
