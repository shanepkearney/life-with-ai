import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/hashlife.dart';
import 'package:life_with_ai/core/patterns.dart';

/// HashLife on an endless plane against the plain rules on a board big
/// enough that nothing reaches its edges.
void main() {
  const size = 400, at = 180;

  Set<(int, int)> live(Grid g) => {
    for (var y = 0; y < g.height; y++)
      for (var x = 0; x < g.width; x++)
        if (g.get(x, y)) (x - at, y - at),
  };

  List<(int, int)> soup(int seed) {
    final rnd = Random(seed);
    return [
      for (var y = 0; y < 24; y++)
        for (var x = 0; x < 24; x++)
          if (rnd.nextDouble() < 0.4) (x, y),
    ];
  }

  Grid gridOf(List<(int, int)> cells) {
    final g = Grid(size, size);
    for (final (x, y) in cells) {
      g.set(x + at, y + at, true);
    }
    return g;
  }

  void expectSame(HashPlane plane, Grid g, String what) {
    final a = plane.liveCells().toSet(), b = live(g);
    expect(a.length == b.length && a.containsAll(b), isTrue, reason: '$what: ${a.length} vs ${b.length} cells');
    expect(plane.population, b.length, reason: what);
  }

  test('single generations match the plain rules', () {
    final cells = soup(1);
    final plane = HashPlane.fromCells(HashLife(), cells);
    var g = gridOf(cells);
    for (var i = 1; i <= 60; i++) {
      plane.advance(0);
      g = g.step();
      expectSame(plane, g, 'generation $i');
    }
    expect(plane.generation, 60);
  });

  test('jumps of 2^j generations land exactly where stepping one at a time does', () {
    for (final seed in [2, 3, 4]) {
      final cells = soup(seed);
      final plane = HashPlane.fromCells(HashLife(), cells);
      var g = gridOf(cells);
      var gen = 0;
      for (final j in [0, 1, 3, 5, 2, 6]) {
        plane.advance(j);
        for (var i = 0; i < 1 << j; i++) {
          g = g.step();
        }
        gen += 1 << j;
        expectSame(plane, g, 'seed $seed after a 2^$j jump (generation $gen)');
      }
      expect(plane.generation, gen);
    }
  });

  test('a glider gun keeps firing across a 1,024-generation jump, cell for cell', () {
    final gun = patternLibrary['gosper_glider_gun']!;
    final plane = HashPlane.fromCells(HashLife(), [for (final c in gun.cells) c]);
    // A board wide enough that the stream never reaches an edge in 1,152 generations.
    const big = 800, off = 380;
    var g = Grid(big, big);
    for (final (x, y) in gun.cells) {
      g.set(x + off, y + off, true);
    }
    plane.advance(7); // 128
    plane.advance(10); // then 1,024 more in one jump
    for (var i = 0; i < 1152; i++) {
      g = g.step();
    }
    final expected = {
      for (var y = 0; y < big; y++)
        for (var x = 0; x < big; x++)
          if (g.get(x, y)) (x - off, y - off),
    };
    final actual = plane.liveCells().toSet();
    expect(actual.length == expected.length && actual.containsAll(expected), isTrue);
    expect(plane.generation, 1152);
    expect(plane.bounds!.width, greaterThan(250), reason: 'the stream has travelled');
  });

  test('bounds and rendering', () {
    final plane = HashPlane.fromCells(HashLife(), [(-5, 3), (-4, 3), (-3, 3)]); // a blinker, off the origin
    expect(plane.bounds, (x: -5, y: 3, width: 3, height: 1));
    final px = plane.render(-6, 2, 0, 5, 3); // one pixel per cell
    expect(
      [
        for (var i = 0; i < px.length; i++)
          if (px[i] > 0) (i % 5, i ~/ 5),
      ],
      [(1, 1), (2, 1), (3, 1)],
    );
    final zoomedOut = plane.render(-8, 0, 2, 2, 2); // 4x4 cells per pixel
    expect(zoomedOut.where((v) => v > 0), hasLength(1), reason: 'the blinker is one pixel');
    expect(zoomedOut.firstWhere((v) => v > 0), greaterThanOrEqualTo(110), reason: 'sparse but visible');
  });

  test('a long run is kept small: the table is pruned to what the pattern uses', () {
    final life = HashLife(maxNodes: 20000);
    final plane = HashPlane.fromCells(life, soup(9));
    var g = gridOf(soup(9));
    for (var i = 0; i < 6; i++) {
      plane.advance(4);
      for (var s = 0; s < 16; s++) {
        g = g.step();
      }
    }
    expectSame(plane, g, 'after pruning');
    expect(life.nodeCount, lessThan(40000));
  });
}
