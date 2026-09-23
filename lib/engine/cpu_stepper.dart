import 'dart:typed_data';

import '../core/grid.dart';
import 'cpu_stepper_inline.dart' if (dart.library.io) 'cpu_stepper_isolate.dart' as impl;

typedef StepResult = ({Uint8List rgba, int population});

/// Owns the CPU-side board and advances it. On native platforms the work runs
/// on a background isolate so the UI thread only ever uploads a texture; on
/// the web (no shared-memory isolates) it runs inline.
abstract class CpuStepper {
  factory CpuStepper() => impl.create();

  Future<void> load(Grid grid);
  Future<StepResult> step(int generations);
  Future<Grid> snapshot();
  void dispose();
}

/// Shared by both implementations: double-buffered stepping.
class StepperState {
  StepperState(Grid g) : a = g.copy(), b = Grid(g.width, g.height), rgba = Uint8List(g.width * g.height * 4);

  Grid a, b;
  final Uint8List rgba;

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
