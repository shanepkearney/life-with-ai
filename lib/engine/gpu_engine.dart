import 'dart:ui' as ui;

import '../core/grid.dart';
import '../core/life_rule.dart';
import '../render/shaders.dart';
import 'life_engine.dart';

/// Steps entirely on the GPU: each generation is a fragment-shader pass that
/// samples the previous generation's image and renders the next one
/// ("ping-pong"). The board never touches the CPU except for [snapshot] and
/// the throttled population readback.
class GpuEngine implements LifeEngine {
  GpuEngine(this._shaders);

  final Shaders _shaders;

  /// The rule's processor's shader, chosen once at [load].
  late ui.FragmentProgram _program = _shaders.lifeStep;
  DateTime _lastCount = DateTime.fromMillisecondsSinceEpoch(0);

  /// Passes chained onto [frame] since it was last detached (see [detach]).
  int _chained = 0;
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
  LifeRule rule = LifeRule.conway;

  @override
  Future<void> load(Grid grid, {int generation = 0, LifeRule rule = LifeRule.conway}) async {
    if (_disposed) return;
    this.rule = rule;
    _program = rule.processor.program(_shaders);
    width = grid.width;
    height = grid.height;
    this.generation = generation;
    population = grid.population;
    final next = await imageFromRgba(grid.toRgba(), width, height);
    // The decode can finish after dispose(): free the image rather than keep it.
    if (_disposed) return next.dispose();
    frame?.dispose();
    frame = next;
    _chained = 0;
  }

  @override
  Future<void> step([int generations = 1]) async {
    if (_disposed) return;
    for (var i = 0; i < generations; i++) {
      // A fresh shader per pass: the recorded picture is rasterized later, so
      // mutating a shared instance could change a pass that hasn't run yet.
      final shader = _program.fragmentShader()
        ..setFloat(0, width.toDouble())
        ..setFloat(1, height.toDouble());
      rule.processor.setUniforms(shader, rule);
      shader.setImageSampler(0, frame!, filterQuality: ui.FilterQuality.none);
      final next = renderPass(shader, width, height);
      frame!.dispose(); // safe: the pending picture holds its own reference
      frame = next;
      _chained++;
    }
    generation += generations;
    if (_chained >= detachEvery) {
      final flat = await detach(frame!);
      if (_disposed) return flat.dispose();
      frame!.dispose();
      frame = flat;
      _chained = 0;
    }
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
      if (data == null || _disposed) return;
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

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    frame?.dispose();
    frame = null;
  }
}

/// The GPU side of each [RuleProcessor]: its shader, and the uniforms it
/// takes after the board size. (The core stays free of dart:ui.)
extension RuleProcessorGpu on RuleProcessor {
  ui.FragmentProgram program(Shaders shaders) => switch (this) {
    RuleProcessor.conway => shaders.lifeStep,
    RuleProcessor.anyRule => shaders.lifeStepRule,
  };

  void setUniforms(ui.FragmentShader shader, LifeRule rule) => switch (this) {
    RuleProcessor.conway => null,
    RuleProcessor.anyRule => shader
      ..setFloat(2, rule.birth.toDouble())
      ..setFloat(3, rule.survival.toDouble()),
  };
}
