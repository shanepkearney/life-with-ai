import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/ai/census.dart';
import 'package:life_with_ai/ai/simulation.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';

Grid board(List<(String, int, int, int)> placed, [int w = 96, int h = 72]) {
  final g = Grid(w, h);
  for (final (name, x, y, turns) in placed) {
    patternLibrary[name]!.transformed(quarterTurns: turns).stampOnto(g, x, y);
  }
  return g;
}

SimulationReport simulate(Grid g, int generations) =>
    runSimulation((width: g.width, height: g.height, cells: g.cells, generations: generations, checkpoints: const [], png: false));

void main() {
  group('census', () {
    test('names still lifes, oscillators and spaceships in any orientation, and counts the rest', () {
      final g = board([
        ('block', 5, 5, 0),
        ('block', 20, 5, 0),
        ('beehive', 35, 5, 1),
        ('blinker', 5, 25, 0),
        ('blinker', 20, 25, 1),
        ('glider', 40, 25, 0),
        ('glider', 60, 25, 2),
        ('lwss', 5, 45, 3),
        ('r_pentomino', 60, 50, 0), // not a known leftover
      ]);
      final c = takeCensus(g);
      expect(c.resting, {'block': 2, 'beehive': 1, 'blinker': 2});
      expect(c.moving, {'glider': 2, 'LWSS': 1});
      expect(c.other, 1);
      expect(c.largestOther, 5);
      expect(
        c.toText(),
        'moving: glider ×2, LWSS ×1; still or oscillating: block ×2, blinker ×2, beehive ×1; unidentified clusters: 1 (largest 5 cells)',
      );
    });

    test('knows every phase: a glider is a glider at any generation', () {
      for (var gen = 0; gen < 4; gen++) {
        final g = board([('glider', 10, 10, 1)]);
        final r = simulate(g, gen == 0 ? 1 : gen);
        expect(r.census!.moving, {'glider': 1}, reason: 'generation $gen');
      }
    });

    test('an object across the wrap-around edge counts once', () {
      final g = Grid(40, 30);
      // A block split across the left and right edges.
      for (final (x, y) in [(39, 10), (0, 10), (39, 11), (0, 11)]) {
        g.set(x, y, true);
      }
      expect(takeCensus(g).resting, {'block': 1});
    });
  });

  group('activity', () {
    test("oscillators don't count as activity, so a field of them has settled from the start", () {
      final r = simulate(board([('blinker', 10, 10, 0), ('toad', 30, 10, 0), ('beacon', 50, 10, 0), ('block', 10, 40, 0)]), 60);
      expect(r.activity.every((s) => s.$2 == 0), isTrue);
      expect(r.settledAt, r.activity.first.$1);
      expect(r.toText(), contains('Settled: activity held steady from about generation'));
      expect(r.toText(), contains('Final board: still or oscillating:'));
    });

    test('a methuselah is active, then settles; the report says when, and what is left', () {
      // The R-pentomino settles at about generation 1103 on an open plane; this board is big enough
      // that nothing it throws off wraps around and hits the rest within 1500 generations.
      final r = simulate(board([('r_pentomino', 250, 180, 0)], 500, 360), 1500);
      expect(r.activity.first.$2, greaterThan(0));
      expect(r.settledAt, isNotNull);
      expect(r.settledAt, greaterThan(500), reason: 'it churns for a long time first');
      expect(r.settledAt, lessThan(1200), reason: 'it settles at about generation 1103');
      // The R-pentomino's well-known final census.
      expect(r.census!.moving, {'glider': 6});
      expect(r.census!.resting, {'block': 8, 'blinker': 4, 'beehive': 4, 'loaf': 1, 'boat': 1, 'ship': 1});
      expect(r.census!.other, 0);
    });

    test('something still churning at the end is reported as not settled', () {
      final r = simulate(board([('r_pentomino', 250, 180, 0)], 500, 360), 300);
      expect(r.settledAt, isNull);
      expect(r.toText(), contains('Not settled: still changing at generation 300.'));
    });
  });
}
