import 'dart:typed_data';

import 'grid.dart';
import 'life_rule.dart';

/// Lets the board step backwards, although Game of Life can't run in reverse:
/// many boards lead to the same next generation, so the previous one can't be
/// computed from the current one.
///
/// Instead the timeline remembers where the run began (its origin) and a
/// snapshot every [interval] generations. To reach any earlier generation it
/// restores the nearest snapshot at or before it and replays forward: at most
/// `interval - 1` steps, so a step back is instant.
///
/// Snapshots are bit-packed (1 bit per cell, ~24 KB for 512x384). When they
/// outgrow [budgetBytes], every other one is dropped and the interval doubles,
/// so a long run gets gradually slower to rewind rather than using ever more
/// memory. The origin is always kept.
class Timeline {
  Timeline(Grid origin, {int generation = 0, this.budgetBytes = 16 * 1024 * 1024, this.baseInterval = 64, this.rule = LifeRule.conway})
    : width = origin.width,
      height = origin.height,
      originGeneration = generation,
      interval = baseInterval {
    _snapshots[generation] = _pack(origin);
  }

  /// The rule the run follows, for rebuilding the boards between snapshots.
  final LifeRule rule;

  final int width;
  final int height;

  /// The generation the run began at: 0 for a fresh seed, or the generation
  /// at which the user last drew on the board.
  final int originGeneration;
  final int budgetBytes;
  final int baseInterval;

  /// Current spacing between snapshots; doubles when memory runs short.
  int interval;

  final _snapshots = <int, Uint8List>{};

  int get snapshotCount => _snapshots.length;
  int get bytes => _snapshots.values.fold(0, (n, s) => n + s.length);

  /// The next generation at which the caller should hand over a snapshot.
  /// Callers stop stepping there, so snapshots land on exact generations.
  int nextSnapshotAfter(int generation) {
    final since = generation - originGeneration;
    return originGeneration + (since ~/ interval + 1) * interval;
  }

  bool wantsSnapshot(int generation) =>
      generation > originGeneration && (generation - originGeneration) % interval == 0 && !_snapshots.containsKey(generation);

  void record(int generation, Grid g) {
    assert(g.width == width && g.height == height);
    if (!wantsSnapshot(generation)) return;
    _snapshots[generation] = _pack(g);
    while (bytes > budgetBytes && _snapshots.length > 2) {
      _thinOut();
    }
  }

  /// Drops snapshots at odd multiples of the current interval, then doubles it.
  void _thinOut() {
    final keep = interval * 2;
    _snapshots.removeWhere((gen, _) => gen != originGeneration && (gen - originGeneration) % keep != 0);
    interval = keep;
  }

  Grid get origin => _unpack(_snapshots[originGeneration]!);

  /// The latest snapshot at or before [generation]: replay forward from here.
  ({int generation, Grid board}) nearestAtOrBefore(int generation) {
    if (generation < originGeneration) throw RangeError.range(generation, originGeneration, null, 'generation');
    var from = originGeneration;
    for (final g in _snapshots.keys) {
      if (g <= generation && g > from) from = g;
    }
    return (generation: from, board: _unpack(_snapshots[from]!));
  }

  /// The board at [generation], which must not be before the origin. Rebuilt
  /// from the nearest snapshot at or before it; callers run this off the UI
  /// thread for big boards.
  Grid stateAt(int generation) {
    final nearest = nearestAtOrBefore(generation);
    final from = nearest.generation;
    var a = nearest.board, b = Grid(width, height);
    final step = rule.processor.step;
    for (var i = from; i < generation; i++) {
      step(a, b, rule);
      final t = a;
      a = b;
      b = t;
    }
    return a;
  }

  Uint8List _pack(Grid g) {
    final out = Uint8List((g.cells.length + 7) >> 3);
    for (var i = 0; i < g.cells.length; i++) {
      if (g.cells[i] == 1) out[i >> 3] |= 1 << (i & 7);
    }
    return out;
  }

  Grid _unpack(Uint8List packed) {
    final g = Grid(width, height);
    for (var i = 0; i < g.cells.length; i++) {
      g.cells[i] = (packed[i >> 3] >> (i & 7)) & 1;
    }
    return g;
  }
}
