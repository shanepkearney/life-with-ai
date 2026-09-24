import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/app/palette_store.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/render/board_palette.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Grid glider() {
    final g = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(g, 210, 150);
    return g;
  }

  group('BoardPalette', () {
    test("Neon is exactly the shader's original colors", () {
      const original = [
        [0.16, 0.06, 0.55],
        [0.00, 0.85, 1.00],
        [1.00, 0.12, 0.72],
        [1.00, 0.62, 0.08],
        [1.00, 0.98, 0.88],
        [0.008, 0.01, 0.03], // background
      ];
      final all = BoardPalette.neon.all;
      for (var i = 0; i < 6; i++) {
        expect([all[i].r, all[i].g, all[i].b], [for (final v in original[i]) closeTo(v, 1e-6)], reason: 'color $i');
      }
    });

    test('presets have five heat stops, a unique id and a name', () {
      final ids = {for (final p in BoardPalette.presets) p.id};
      expect(ids, hasLength(BoardPalette.presets.length));
      for (final p in BoardPalette.presets) {
        expect(p.heat, hasLength(5), reason: p.name);
        expect(p.isPreset, isTrue);
        expect(BoardPalette.fromWire(p.wire ?? 'neon'), p, reason: 'round trip');
      }
    });

    test('Neon travels as nothing, a preset by name, a custom palette as six hex colors', () {
      expect(BoardPalette.neon.wire, isNull);
      expect(BoardPalette.ember.wire, 'ember');
      final custom = BoardPalette.ember.withColor(5, const Color(0xFF102030));
      expect(custom.isPreset, isFalse);
      expect(custom.name, 'Custom');
      expect(custom.wire, '4a0d06.b8230f.ff5a1f.ffb627.fff4d6.102030');
      expect(BoardPalette.fromWire(custom.wire), custom);
      expect(BoardPalette.fromWire('EMBER'), BoardPalette.ember, reason: 'case-insensitive');
    });

    test('changing one color leaves the others alone', () {
      final p = BoardPalette.neon.withColor(2, const Color(0xFF00FF00));
      expect(BoardPalette.hex(p.heat[2]), '00ff00');
      for (final i in [0, 1, 3, 4, 5]) {
        expect(BoardPalette.hex(p.all[i]), BoardPalette.hex(BoardPalette.neon.all[i]));
      }
    });

    test('untrusted colors from a link are refused, never guessed at', () {
      for (final bad in [
        '',
        'sunset',
        '4a0d06.b8230f',
        '4a0d06.b8230f.ff5a1f.ffb627.fff4d6.10203',
        'zzzzzz.b8230f.ff5a1f.ffb627.fff4d6.102030',
        '<script>',
        '1.2.3.4.5.6.7',
      ]) {
        expect(BoardPalette.fromWire(bad), isNull, reason: bad);
      }
      expect(BoardPalette.parseHex('#A1b2C3'), const Color(0xFFA1B2C3));
      expect(BoardPalette.parseHex('a1b2c'), isNull);
    });
  });

  group('share links', () {
    test('carry the colors, Neon included, and read them back', () {
      final seed = glider();
      final neon = ShareLink.forSeed(seed, title: 'One glider', palette: BoardPalette.neon);
      expect(neon, contains('&colors=neon'), reason: 'so a receiver in other colors sees what a Neon sender saw');
      expect(ShareLink.parse(Uri.parse(neon))!.palette, BoardPalette.neon);
      expect(ShareLink.parse(Uri.parse(ShareLink.forSeed(seed, title: 'One glider')))!.palette, isNull, reason: 'old links have none');

      final ember = ShareLink.forSeed(seed, title: 'One glider', palette: BoardPalette.ember);
      expect(ember, contains('&colors=ember'));
      expect(ShareLink.parse(Uri.parse(ember))!.palette, BoardPalette.ember);

      final custom = BoardPalette.ocean.withColor(0, const Color(0xFF123456));
      expect(ShareLink.parse(Uri.parse(ShareLink.forSeed(seed, palette: custom)))!.palette, custom);
    });

    test('a link whose colors are bad still opens its seed, in the viewer\'s own colors', () {
      final link = '${ShareLink.forSeed(glider(), title: 'One glider')}&colors=not-a-palette';
      final shared = ShareLink.parse(Uri.parse(link))!;
      expect(shared.seed.population, 5);
      expect(shared.palette, isNull);
    });

    test('the colors never cost the seed: long notes still fit the link', () {
      final link = ShareLink.forSeed(glider(), title: 'One glider', note: 'x' * 3000, palette: BoardPalette.ocean.withColor(1, const Color(0xFF000000)));
      expect(link.length, lessThanOrEqualTo(ShareLink.comfortableLength));
      expect(ShareLink.parse(Uri.parse(link))!.palette, isNotNull);
    });
  });

  group('PaletteStore', () {
    test('keeps the choice, stores Neon as nothing, and survives bad storage', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PaletteStore.load(), BoardPalette.neon);
      await PaletteStore.save(BoardPalette.forest);
      expect(await PaletteStore.load(), BoardPalette.forest);
      await PaletteStore.save(BoardPalette.neon);
      expect((await SharedPreferences.getInstance()).getString('board_palette'), isNull);
      SharedPreferences.setMockInitialValues({'board_palette': 'garbage'});
      expect(await PaletteStore.load(), BoardPalette.neon);
    });
  });

  group('LifeController colors', () {
    testWidgets("a link's colors show without becoming the user's own, until kept", (tester) async {
      late LifeController life;
      await tester.runAsync(() async {
        life = LifeController(await Shaders.load());
        await life.init();
      });
      addTearDown(life.dispose);
      final saved = <BoardPalette>[];
      life.onPaletteChosen = saved.add;

      life.choosePalette(BoardPalette.forest);
      expect((life.palette, life.ownPalette), (BoardPalette.forest, BoardPalette.forest));
      expect(saved, [BoardPalette.forest]);
      expect(life.pipeline.palette, BoardPalette.forest, reason: 'what the shader draws');

      final shared = glider();
      life.showSharedPalette(BoardPalette.ember, seed: shared);
      expect((life.palette, life.ownPalette), (BoardPalette.ember, BoardPalette.forest));
      expect(saved, hasLength(1), reason: 'showing is not saving');

      life.dropSharedPalette();
      expect(life.palette, BoardPalette.forest);

      life.showSharedPalette(BoardPalette.ember, seed: shared);
      life.keepSharedPalette();
      expect((life.palette, life.ownPalette, life.sharedPalette), (BoardPalette.ember, BoardPalette.ember, null));
      expect(saved.last, BoardPalette.ember);
    });

    testWidgets("the sender's colors stay with their seed: replaying keeps them, anything else drops them", (tester) async {
      late LifeController life;
      await tester.runAsync(() async {
        life = LifeController(await Shaders.load());
        await life.init();
      });
      addTearDown(life.dispose);
      final shared = glider();
      await tester.runAsync(() => life.playSeed(shared, title: 'Shared'));
      life.showSharedPalette(BoardPalette.ember, seed: shared);

      await tester.runAsync(() => life.playSeed(shared.copy(), title: 'Shared')); // the card's Replay
      expect(life.palette, BoardPalette.ember);

      final other = Grid(512, 384);
      patternLibrary['blinker']!.stampOnto(other, 50, 50);
      await tester.runAsync(() => life.playSeed(other, title: 'A favorite'));
      expect((life.palette, life.sharedPalette), (BoardPalette.neon, null), reason: 'back to their own colors');
      expect(life.pipeline.palette, BoardPalette.neon);

      life.showSharedPalette(BoardPalette.ember, seed: shared);
      await tester.runAsync(() => life.randomize());
      expect(life.sharedPalette, isNull, reason: 'a random board is something else too');
    });
  });
}
