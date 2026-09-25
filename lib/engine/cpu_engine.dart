import 'dart:ui' as ui;

import '../core/grid.dart';
import '../render/shaders.dart';
import 'cpu_stepper.dart';
import 'life_engine.dart';

/// Steps on the CPU (see [CpuStepper]) and uploads each generation as a
/// texture: by the plain rules, or with [EngineKind.hashlife], by HashLife.
class CpuEngine implements LifeEngine {
  CpuEngine({this.kind = EngineKind.cpu}) : assert(kind != EngineKind.gpu), _stepper = CpuStepper(hashLife: kind == EngineKind.hashlife);

  final CpuStepper _stepper;

  @override
  final EngineKind kind;
  @override
  int width = 0;
  @override
  int height = 0;
  @override
  int generation = 0;
  @override
  int population = 0;
  @override
  ui.Image? frame;

  @override
  Future<void> load(Grid grid, {int generation = 0}) async {
    if (_disposed) return; // its isolate is gone and would never reply
    width = grid.width;
    height = grid.height;
    this.generation = generation;
    population = grid.population;
    await _stepper.load(grid);
    _setFrame(await imageFromRgba(grid.toRgba(), width, height));
  }

  @override
  Future<void> step([int generations = 1]) async {
    if (_disposed) return;
    final r = await _stepper.step(generations);
    generation += generations;
    population = r.population;
    _setFrame(await imageFromRgba(r.rgba, width, height));
  }

  /// A step or load can finish after [dispose] (its isolate reply or image
  /// decode was already in flight); its image is then freed, not swapped in.
  void _setFrame(ui.Image next) {
    if (_disposed) {
      next.dispose();
      return;
    }
    frame?.dispose();
    frame = next;
  }

  bool _disposed = false;

  @override
  Future<Grid> snapshot() => _stepper.snapshot();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stepper.dispose();
    frame?.dispose();
    frame = null;
  }
}
