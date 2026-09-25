import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/hashlife.dart';
import 'package:life_with_ai/core/patterns.dart';

/// HashLife must run the app's wrap-around boards exactly as [Grid.step] does:
/// same cells, every generation, edges included.
void main() {
  Grid soup(int w, int h, int seed, double density) {
    final g = Grid(w, h);
    final rnd = Random(seed);
    for (var i = 0; i < g.cells.length; i++) {
      if (rnd.nextDouble() < density) g.cells[i] = 1;
    }
    return g;
  }

  void matches(Grid start, int generations, String what) {
    final life = HashLife();
    var a = start.copy(), b = start.copy();
    for (var i = 1; i <= generations; i++) {
      a = a.step();
      b = life.stepTorus(b);
      expect(b.stateHash, a.stateHash, reason: '$what, generation $i');
    }
  }

  test('a glider crosses every edge and corner exactly as the plain rules say', () {
    final g = Grid(16, 12);
    patternLibrary['glider']!.stampOnto(g, 13, 9); // heads down-right, into the corner
    matches(g, 80, 'glider');
  });

  for (final (w, h) in [(8, 8), (16, 12), (97, 61), (64, 48), (192, 256), (256, 192)]) {
    test('random soups on a ${w}x$h board', () {
      for (final density in [0.1, 0.35, 0.6]) {
        matches(soup(w, h, w * h + (density * 100).round(), density), w > 100 ? 25 : 60, '${w}x$h at $density');
      }
    });
  }

  test('a gun across the corner, for a hundred generations', () {
    final g = Grid(64, 48);
    patternLibrary['gosper_glider_gun']!.stampOnto(g, 50, 44);
    matches(g, 100, 'gun');
  });

  test('empty boards stay empty, and repetition is shared', () {
    final life = HashLife();
    expect(life.stepTorus(Grid(40, 30)).population, 0);
    final blocks = Grid(128, 128);
    for (var y = 0; y < 128; y += 8) {
      for (var x = 0; x < 128; x += 8) {
        blocks
          ..set(x, y, true)
          ..set(x + 1, y, true)
          ..set(x, y + 1, true)
          ..set(x + 1, y + 1, true);
      }
    }
    final before = life.nodeCount;
    final next = life.stepTorus(blocks);
    expect(next.stateHash, blocks.stateHash, reason: 'blocks are still lifes');
    expect(life.nodeCount - before, lessThan(200), reason: '256 identical blocks are one set of nodes, not 256');
  });

  test('forgetting the node table keeps results correct', () {
    final life = HashLife(maxNodes: 500);
    var a = soup(48, 40, 3, 0.3), b = a.copy();
    for (var i = 0; i < 30; i++) {
      a = a.step();
      b = life.stepTorus(b);
      expect(b.stateHash, a.stateHash, reason: 'generation ${i + 1}');
    }
  });
}
