import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/grid.dart';
import '../engine/cpu_engine.dart';
import '../engine/gpu_engine.dart';
import '../engine/life_engine.dart';
import '../render/glow_pipeline.dart';
import '../render/shaders.dart';

enum BoardSize {
  small(256, 192),
  medium(512, 384),
  large(1024, 768); // the original Java app's board

  const BoardSize(this.width, this.height);
  final int width;
  final int height;
  String get label => '$width×$height';
}

/// Owns the running simulation: which engine, play/pause, speed, editing.
/// The UI's ticker calls [tick] every frame; everything else is commands.
class LifeController extends ChangeNotifier {
  LifeController(this._shaders) : pipeline = GlowPipeline(_shaders);

  final Shaders _shaders;
  final GlowPipeline pipeline;
  late LifeEngine engine;

  BoardSize boardSize = BoardSize.medium;
  bool running = false;
  int speed = 1; // generations per frame
  double gensPerSecond = 0;

  bool _busy = false;
  int _gensSinceSample = 0;
  final _rateClock = Stopwatch()..start();

  // Editing (drawing on the board, or the AI previewing a seed).
  Grid? _edit;
  bool _flushQueued = false;

  EngineKind get engineKind => engine.kind;
  int get generation => engine.generation;
  int get population => engine.population;
  int get width => engine.width;
  int get height => engine.height;

  Future<void> init({EngineKind engine = EngineKind.gpu}) async {
    this.engine = _create(engine);
    await randomize();
  }

  LifeEngine _create(EngineKind kind) =>
      kind == EngineKind.cpu ? CpuEngine() : GpuEngine(_shaders.lifeStep);

  Future<void> tick() async {
    if (!running || _busy) return;
    _busy = true;
    try {
      await engine.step(speed);
      _publish();
      _gensSinceSample += speed;
      final ms = _rateClock.elapsedMilliseconds;
      if (ms >= 500) {
        gensPerSecond = _gensSinceSample * 1000 / ms;
        _gensSinceSample = 0;
        _rateClock.reset();
      }
    } finally {
      _busy = false;
    }
  }

  void _publish() {
    pipeline.update(engine.frame!);
    notifyListeners();
  }

  /// Advances exactly one generation while paused.
  Future<void> stepOnce() => _whileIdle(() async {
        await engine.step(1);
        _publish();
      });

  void toggleRunning() {
    running = !running;
    _gensSinceSample = 0;
    _rateClock.reset();
    if (!running) gensPerSecond = 0;
    notifyListeners();
  }

  void setGlow(double value) {
    pipeline.glow = value;
    notifyListeners();
  }

  void setSpeed(int value) {
    speed = value;
    notifyListeners();
  }

  /// Hot-swaps the engine mid-run: the board is carried across, so the two
  /// can be compared on the same pattern.
  Future<void> switchEngine(EngineKind kind) async {
    if (kind == engine.kind) return;
    await _whileIdle(() async {
      final grid = await engine.snapshot();
      final next = _create(kind);
      await next.load(grid, generation: engine.generation);
      engine.dispose();
      engine = next;
      _publish();
    });
  }

  Future<void> setBoardSize(BoardSize size) async {
    boardSize = size;
    await randomize();
  }

  Future<void> randomize([double density = 0.25]) {
    final g = Grid(boardSize.width, boardSize.height);
    final rnd = Random();
    for (var i = 0; i < g.cells.length; i++) {
      g.cells[i] = rnd.nextDouble() < density ? 1 : 0;
    }
    return load(g);
  }

  Future<void> clear() => load(Grid(boardSize.width, boardSize.height));

  /// Replaces the board (used by reset, drawing, and the AI assistant).
  Future<void> load(Grid grid) => _whileIdle(() async {
        await engine.load(grid);
        _publish();
      });

  // ---- Drawing --------------------------------------------------------------

  Future<void> beginEdit() async {
    _edit = await engine.snapshot();
  }

  void paintCell(int x, int y, bool alive) {
    final g = _edit;
    if (g == null || x < 0 || y < 0 || x >= g.width || y >= g.height) return;
    // A 2x2 brush on big boards so strokes are visible.
    final r = boardSize == BoardSize.large ? 1 : 0;
    for (var dy = 0; dy <= r; dy++) {
      for (var dx = 0; dx <= r; dx++) {
        g.set(x + dx, y + dy, alive);
      }
    }
    if (!_flushQueued) {
      _flushQueued = true;
      // Coalesce a whole drag's worth of points into one upload per frame.
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        _flushQueued = false;
        await engine.load(g, generation: engine.generation);
        _publish();
      });
      SchedulerBinding.instance.ensureVisualUpdate();
    }
  }

  void endEdit() => _edit = null;

  Future<T> _whileIdle<T>(Future<T> Function() body) async {
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
    _busy = true;
    try {
      return await body();
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    engine.dispose();
    pipeline.dispose();
    super.dispose();
  }
}
