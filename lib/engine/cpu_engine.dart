import 'dart:ui' as ui;

import '../core/grid.dart';
import '../render/shaders.dart';
import 'cpu_stepper.dart';
import 'life_engine.dart';

/// Steps on the CPU (see [CpuStepper]) and uploads each generation as a texture.
class CpuEngine implements LifeEngine {
  final _stepper = CpuStepper();

  @override
  EngineKind get kind => EngineKind.cpu;
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
    width = grid.width;
    height = grid.height;
    this.generation = generation;
    population = grid.population;
    await _stepper.load(grid);
    _setFrame(await imageFromRgba(grid.toRgba(), width, height));
  }

  @override
  Future<void> step([int generations = 1]) async {
    final r = await _stepper.step(generations);
    generation += generations;
    population = r.population;
    _setFrame(await imageFromRgba(r.rgba, width, height));
  }

  void _setFrame(ui.Image next) {
    frame?.dispose();
    frame = next;
  }

  @override
  Future<Grid> snapshot() => _stepper.snapshot();

  @override
  void dispose() {
    _stepper.dispose();
    frame?.dispose();
  }
}
