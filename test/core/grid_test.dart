import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';

Grid _run(Grid g, int generations) {
  var a = g.copy(), b = Grid(g.width, g.height);
  for (var i = 0; i < generations; i++) {
    a.stepInto(b);
    final t = a;
    a = b;
    b = t;
  }
  return a;
}

Grid _with(String name, {int w = 64, int h = 64, int x = 10, int y = 10, int turns = 0}) {
  final g = Grid(w, h);
  patternLibrary[name]!.transformed(quarterTurns: turns).stampOnto(g, x, y);
  return g;
}

void main() {
  group('rules', () {
    test('blinker oscillates with period 2', () {
      final g = _with('blinker');
      expect(_run(g, 1).stateHash, isNot(g.stateHash));
      expect(_run(g, 2).stateHash, g.stateHash);
    });

    test('block is a still life', () {
      final g = _with('block');
      expect(_run(g, 1).stateHash, g.stateHash);
    });

    test('glider moves one cell down-right every 4 generations', () {
      final g = _with('glider');
      final start = g.boundingBox!;
      final end = _run(g, 4).boundingBox!;
      expect((end.x - start.x, end.y - start.y), (1, 1));
      expect(_run(g, 4).population, 5);
    });

    test('edges wrap: a glider crossing the corner survives intact', () {
      final g = _with('glider', w: 16, h: 16, x: 12, y: 12);
      final after = _run(g, 64); // 16 cells diagonally = one full lap
      expect(after.stateHash, g.stateHash);
    });

    test('empty board stays empty', () {
      expect(_run(Grid(8, 8), 3).population, 0);
    });
  });

  group('pattern library claims', () {
    test('every pattern parses to a non-empty shape within its bounds', () {
      for (final p in patternLibrary.values) {
        expect(p.cells, isNotEmpty, reason: p.name);
        for (final (x, y) in p.cells) {
          expect(x < p.width && y < p.height, isTrue, reason: p.name);
        }
      }
    });

    for (final name in ['lwss', 'mwss', 'hwss']) {
      test('$name moves 2 cells right every 4 generations at rotation 0', () {
        final g = _with(name, x: 20, y: 20);
        final s = g.boundingBox!, e = _run(g, 4).boundingBox!;
        expect((e.x - s.x, e.y - s.y), (2, 0));
      });
    }

    for (final (name, period) in [('toad', 2), ('beacon', 2), ('pulsar', 3), ('pentadecathlon', 15)]) {
      test('$name has period $period', () {
        final g = _with(name, x: 20, y: 20);
        expect(_run(g, period).stateHash, g.stateHash);
        expect(_run(g, 1).stateHash, isNot(g.stateHash));
      });
    }

    for (final name in ['beehive', 'loaf', 'boat']) {
      test('$name is a still life', () {
        final g = _with(name);
        expect(_run(g, 1).stateHash, g.stateHash);
      });
    }

    test('diehard dies at generation 130', () {
      final g = _with('diehard', w: 128, h: 128, x: 60, y: 60);
      expect(_run(g, 129).population, greaterThan(0));
      expect(_run(g, 130).population, 0);
    });

    test('gosper gun emits a glider every 30 generations', () {
      final g = _with('gosper_glider_gun', w: 200, h: 200, x: 10, y: 10);
      final p0 = g.population;
      expect(_run(g, 30).population, p0 + 5);
      expect(_run(g, 60).population, p0 + 10);
    });

    test('rotation turns a glider to travel down-left', () {
      final g = _with('glider', x: 30, y: 30, turns: 1);
      final s = g.boundingBox!, e = _run(g, 4).boundingBox!;
      expect((e.x - s.x, e.y - s.y), (-1, 1));
    });
  });

  test('RGBA round-trip preserves the board', () {
    final g = _with('gosper_glider_gun', w: 50, h: 20, x: 2, y: 2);
    expect(Grid.fromRgba(50, 20, g.toRgba()).stateHash, g.stateHash);
  });

  test('ascii view shows live cells', () {
    final g = _with('block', w: 4, h: 4, x: 1, y: 1);
    expect(g.toAscii(), '    \n ## \n ## \n    \n');
  });
}
