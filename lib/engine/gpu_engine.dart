import 'dart:ui' as ui;

import '../core/grid.dart';
import '../render/shaders.dart';
import 'life_engine.dart';

/// Steps entirely on the GPU: each generation is a fragment-shader pass that
/// samples the previous generation's image and renders the next one
/// ("ping-pong"). The board never touches the CPU except for [snapshot] and
/// the throttled population readback.
class GpuEngine implements LifeEngine {
  GpuEngine(this._program);

  final ui.FragmentProgram _program;
  DateTime _lastCount = DateTime.fromMillisecondsSinceEpoch(0);
  bool _counting = false;

  @override
  EngineKind get kind => EngineKind.gpu;
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
    final next = await imageFromRgba(grid.toRgba(), width, height);
    frame?.dispose();
    frame = next;
  }

  @override
  Future<void> step([int generations = 1]) async {
    for (var i = 0; i < generations; i++) {
      // A fresh shader per pass: the recorded picture is rasterised later, so
      // mutating a shared instance could change a pass that hasn't run yet.
      final shader = _program.fragmentShader()
        ..setFloat(0, width.toDouble())
        ..setFloat(1, height.toDouble())
        ..setImageSampler(0, frame!, filterQuality: ui.FilterQuality.none);
      final next = renderPass(shader, width, height);
      frame!.dispose(); // safe: the pending picture holds its own reference
      frame = next;
    }
    generation += generations;
    _maybeCountPopulation();
  }

  /// Reading pixels back stalls the GPU pipeline, so do it at most twice a second.
  void _maybeCountPopulation() {
    final now = DateTime.now();
    if (_counting || now.difference(_lastCount).inMilliseconds < 500) return;
    _counting = true;
    _lastCount = now;
    final image = frame!.clone();
    image.toByteData().then((data) {
      image.dispose();
      _counting = false;
      if (data == null) return;
      final bytes = data.buffer.asUint8List();
      var n = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i] > 127) n++;
      }
      population = n;
    });
  }

  @override
  Future<Grid> snapshot() async {
    final data = await frame!.toByteData();
    return Grid.fromRgba(width, height, data!.buffer.asUint8List());
  }

  @override
  void dispose() => frame?.dispose();
}
