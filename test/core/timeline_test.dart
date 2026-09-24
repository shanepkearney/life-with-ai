import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/timeline.dart';

Grid soup(int w, int h, {int seed = 1, double density = 0.3}) {
  final g = Grid(w, h);
  final rnd = Random(seed);
  for (var i = 0; i < g.cells.length; i++) {
    if (rnd.nextDouble() < density) g.cells[i] = 1;
  }
  return g;
}

/// Runs [start] forward, recording into [t] the way the controller does, and
/// returns every generation's true state for comparison.
List<Grid> runRecording(Grid start, Timeline t, int generations, {int from = 0}) {
  final truth = [start.copy()];
  var g = start.copy();
  for (var gen = from + 1; gen <= from + generations; gen++) {
    g = g.step();
    truth.add(g.copy());
    if (t.wantsSnapshot(gen)) t.record(gen, g);
  }
  return truth;
}

void main() {
  test('every earlier generation is reconstructed exactly', () {
    final start = soup(96, 64);
    final t = Timeline(start, baseInterval: 16);
    final truth = runRecording(start, t, 150);
    for (var gen = 0; gen <= 150; gen++) {
      expect(t.stateAt(gen).stateHash, truth[gen].stateHash, reason: 'generation $gen');
    }
    expect(t.snapshotCount, 1 + 150 ~/ 16);
  });

  test('the origin is the beginning, even when a run starts mid-count', () {
    final start = soup(40, 30, seed: 2);
    final t = Timeline(start, generation: 500, baseInterval: 16);
    final truth = runRecording(start, t, 40, from: 500);
    expect(t.origin.stateHash, start.stateHash);
    expect(t.stateAt(500).stateHash, start.stateHash);
    expect(t.stateAt(537).stateHash, truth[37].stateHash);
    expect(() => t.stateAt(499), throwsRangeError, reason: 'nothing before the beginning');
  });

  test('snapshots land on exact interval boundaries', () {
    final t = Timeline(Grid(8, 8), generation: 10, baseInterval: 64);
    expect(t.nextSnapshotAfter(10), 74);
    expect(t.nextSnapshotAfter(73), 74);
    expect(t.nextSnapshotAfter(74), 138);
    expect(t.wantsSnapshot(74), isTrue);
    expect(t.wantsSnapshot(75), isFalse);
  });

  test('over budget, snapshots thin out but every generation stays reachable', () {
    final start = soup(128, 96, seed: 3);
    final perSnapshot = (128 * 96) ~/ 8;
    final t = Timeline(start, baseInterval: 8, budgetBytes: perSnapshot * 10);
    final truth = runRecording(start, t, 400);
    expect(t.bytes, lessThanOrEqualTo(perSnapshot * 10));
    expect(t.interval, greaterThan(8), reason: 'it doubled at least once');
    for (final gen in [0, 1, 7, 8, 63, 64, 199, 256, 333, 399, 400]) {
      expect(t.stateAt(gen).stateHash, truth[gen].stateHash, reason: 'generation $gen');
    }
  });

  test('bit-packing round-trips odd-sized boards exactly', () {
    final start = soup(97, 61, seed: 4, density: 0.5);
    expect(Timeline(start).origin.stateHash, start.stateHash);
  });
}
