import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/hashlife.dart';
import 'package:life_with_ai/core/life_rule.dart';
import 'package:life_with_ai/core/timeline.dart';

final highLife = LifeRule.parse('B36/S23')!;
final seeds = LifeRule.parse('B2/S')!;
final dayAndNight = LifeRule.parse('B3678/S34678')!;
final lifeWithoutDeath = LifeRule.parse('B3/S012345678')!;

Grid soup(int w, int h, int seed, [double density = 0.35]) {
  final g = Grid(w, h);
  final rnd = Random(seed);
  for (var i = 0; i < g.cells.length; i++) {
    if (rnd.nextDouble() < density) g.cells[i] = 1;
  }
  return g;
}

void main() {
  group('LifeRule', () {
    test("Conway's rule, however it's written", () {
      for (final text in ['B3/S23', 'b3/s23', 'S23/B3', '23/3', ' B3 / S23 ']) {
        expect(LifeRule.parse(text), LifeRule.conway, reason: text);
      }
      expect(LifeRule.conway.notation, 'B3/S23');
      expect(LifeRule.conway.isConway, isTrue);
    });

    test('other rules read and write back', () {
      for (final text in ['B36/S23', 'B2/S', 'B3678/S34678', 'B3/S012345678', 'B0/S8', 'B/S']) {
        expect(LifeRule.parse(text)!.notation, text);
      }
      expect(seeds.survival, 0);
      expect(LifeRule.parse('B0/S8')!.birthFromNothing, isTrue);
      expect(highLife.birthFromNothing, isFalse);
    });

    test('anything else is not a rule of this kind', () {
      for (final text in ['B9/S23', 'B3/S23/C3', 'LifeHistory', 'B3a/S23', 'B3S23', '', 'W110']) {
        expect(LifeRule.parse(text), isNull, reason: text);
      }
    });

    test('next and the lookup table agree for every case', () {
      for (final rule in [LifeRule.conway, highLife, seeds, dayAndNight]) {
        final t = rule.table;
        for (var n = 0; n <= 8; n++) {
          expect(t[n] == 1, rule.next(false, n));
          expect(t[9 + n] == 1, rule.next(true, n));
        }
      }
      expect(highLife.next(false, 6), isTrue, reason: 'HighLife: born with 6');
      expect(LifeRule.conway.next(false, 6), isFalse);
    });
  });

  group('the table-driven step', () {
    test('each rule names its processor once: Conway its own code, every other rule the table', () {
      expect(LifeRule.conway.processor, RuleProcessor.conway);
      for (final r in [highLife, seeds, dayAndNight, lifeWithoutDeath]) {
        expect(r.processor, RuleProcessor.anyRule, reason: r.notation);
      }
      // The two processors agree where they overlap: the table, given Conway's rule, is Conway's own loop.
      var a = soup(83, 59, 7), b = a.copy();
      for (var i = 0; i < 50; i++) {
        a = RuleProcessor.conway.step(a, Grid(83, 59), LifeRule.conway);
        b = RuleProcessor.anyRule.step(b, Grid(83, 59), LifeRule.conway);
      }
      expect(b.stateHash, a.stateHash);
    });

    test("gives exactly Conway's loop for Conway's rule", () {
      final g = soup(97, 61, 1);
      var a = g.copy();
      for (var i = 0; i < 60; i++) {
        a = a.step(); // Conway's own fast loop
      }
      // The same rule by a different road: the table, forced.
      var c = g.copy();
      final out = Grid(97, 61);
      for (var i = 0; i < 60; i++) {
        final table = LifeRule.conway.table;
        for (var y = 0; y < 61; y++) {
          for (var x = 0; x < 97; x++) {
            var n = 0;
            for (var dy = -1; dy <= 1; dy++) {
              for (var dx = -1; dx <= 1; dx++) {
                if (dx != 0 || dy != 0) n += c.get(x + dx, y + dy) ? 1 : 0;
              }
            }
            out.set(x, y, table[(c.get(x, y) ? 9 : 0) + n] == 1);
          }
        }
        c = out.copy();
      }
      expect(c.stateHash, a.stateHash, reason: 'a cell-by-cell reading of the table agrees with the fast loop');
    });

    test('Seeds: every live cell dies each generation', () {
      final g = soup(64, 48, 2, 0.2);
      final next = g.step(seeds);
      for (var i = 0; i < g.cells.length; i++) {
        if (g.cells[i] == 1) expect(next.cells[i], 0);
      }
    });

    test('Life without Death: no cell ever dies', () {
      var g = soup(64, 48, 3, 0.1);
      for (var i = 0; i < 20; i++) {
        final next = g.step(lifeWithoutDeath);
        for (var c = 0; c < g.cells.length; c++) {
          if (g.cells[c] == 1) expect(next.cells[c], 1);
        }
        g = next;
      }
    });

    test('Day & Night: flipping every cell commutes with a step', () {
      Grid flip(Grid g) => Grid.fromCells(g.width, g.height, Uint8List.fromList([for (final c in g.cells) 1 - c]));
      var g = soup(64, 48, 4);
      for (var i = 0; i < 10; i++) {
        expect(flip(g).step(dayAndNight).stateHash, flip(g.step(dayAndNight)).stateHash, reason: 'generation $i');
        g = g.step(dayAndNight);
      }
    });

    test('the rewind timeline replays by its rule', () {
      final g = soup(48, 40, 5);
      final t = Timeline(g, rule: highLife, baseInterval: 16);
      var direct = g.copy();
      for (var i = 0; i < 37; i++) {
        direct = direct.step(highLife);
      }
      expect(t.stateAt(37).stateHash, direct.stateHash);
    });
  });

  group('HashLife under other rules', () {
    for (final rule in [highLife, seeds, dayAndNight, lifeWithoutDeath, LifeRule.parse('B0/S8')!]) {
      test('${rule.notation} on a wrap-around board matches the plain step', () {
        final life = HashLife(rule: rule);
        var a = soup(61, 47, rule.hashCode % 97), b = a.copy();
        for (var i = 1; i <= 30; i++) {
          a = a.step(rule);
          b = life.stepTorus(b);
          expect(b.stateHash, a.stateHash, reason: 'generation $i');
        }
      });
    }

    test('HighLife on the endless plane, in jumps, matches the plain step on a board it never reaches the edge of', () {
      final start = soup(20, 20, 6, 0.4);
      final cells = [
        for (var y = 0; y < 20; y++)
          for (var x = 0; x < 20; x++)
            if (start.get(x, y)) (x, y),
      ];
      final plane = HashPlane.fromCells(HashLife(rule: highLife), cells);
      var g = Grid(300, 300);
      for (final (x, y) in cells) {
        g.set(x + 140, y + 140, true);
      }
      for (final j in [0, 3, 5, 2]) {
        plane.advance(j);
        for (var i = 0; i < 1 << j; i++) {
          g = g.step(highLife);
        }
        final expected = {
          for (var y = 0; y < 300; y++)
            for (var x = 0; x < 300; x++)
              if (g.get(x, y)) (x - 140, y - 140),
        };
        final actual = plane.liveCells().toSet();
        expect(actual.length == expected.length && actual.containsAll(expected), isTrue, reason: 'after 2^$j more');
      }
    });

    test('B0 on the endless plane is refused: empty space would fill', () {
      expect(() => HashPlane.fromCells(HashLife(rule: LifeRule.parse('B0/S8')!), [(0, 0)]), throwsArgumentError);
    });
  });
}
