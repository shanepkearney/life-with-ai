import 'dart:typed_data';

import '../core/grid.dart';
import '../core/hashlife.dart';
import 'cpu_stepper_inline.dart' if (dart.library.io) 'cpu_stepper_isolate.dart' as impl;

typedef StepResult = ({Uint8List rgba, int population});

/// Owns the CPU-side board and advances it. On native platforms the work runs
/// on a background isolate so the UI thread only ever uploads a texture; on
/// the web (no shared-memory isolates) it runs inline.
abstract class CpuStepper {
  /// [hashLife] steps with [HashLife] instead of the plain rules.
  factory CpuStepper({bool hashLife = false}) => impl.create(hashLife: hashLife);

  Future<void> load(Grid grid);
  Future<StepResult> step(int generations);
  Future<Grid> snapshot();
  void dispose();
}

/// Shared by both implementations: a board and how it advances.
abstract class Stepping {
  factory Stepping(Grid g, {bool hashLife = false}) => hashLife ? HashLifeState(g) : StepperState(g);

  Grid get board;
  StepResult advance(int generations);
}

/// Double-buffered stepping by the plain rules.
class StepperState implements Stepping {
  StepperState(Grid g) : a = g.copy(), b = Grid(g.width, g.height), rgba = Uint8List(g.width * g.height * 4);

  Grid a, b;
  final Uint8List rgba;

  @override
  Grid get board => a;

  @override
  StepResult advance(int generations) {
    for (var i = 0; i < generations; i++) {
      a.stepInto(b);
      final t = a;
      a = b;
      b = t;
    }
    return (rgba: a.toRgba(Uint8List(rgba.length)), population: a.population);
  }
}

/// Stepping by [HashLife], cell-for-cell the same as [StepperState].
class HashLifeState implements Stepping {
  HashLifeState(Grid g) : board = g.copy(), _rgba = Uint8List(g.width * g.height * 4);

  final _life = HashLife();
  final Uint8List _rgba;

  @override
  Grid board;

  @override
  StepResult advance(int generations) {
    for (var i = 0; i < generations; i++) {
      board = _life.stepTorus(board);
    }
    return (rgba: board.toRgba(Uint8List(_rgba.length)), population: board.population);
  }
}
