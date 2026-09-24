import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/grid.dart';
import '../core/timeline.dart';
import '../engine/cpu_engine.dart';
import '../engine/gpu_engine.dart';
import '../engine/life_engine.dart';
import '../render/glow_pipeline.dart';
import '../render/shaders.dart';
import 'telemetry.dart';

/// A board's size in cells: one of the presets, a board shaped like the
/// screen ([BoardSize.fitScreen]), or whatever size a shared seed came with.
@immutable
class BoardSize {
  const BoardSize._(this.width, this.height, {this.fitsScreen = false});

  static const small = BoardSize._(256, 192);
  static const medium = BoardSize._(512, 384);
  static const large = BoardSize._(1024, 768); // the original Java app's board
  static const portrait = BoardSize._(192, 256); // phones: fills a tall screen instead of letterboxing a 4:3 board

  /// The presets. (Community seeds must use one of these.)
  static const values = [small, medium, large, portrait];

  /// The presets each layout offers, alongside Fit screen. Desktop keeps its original three.
  static const desktop = [small, medium, large];
  static const mobile = [portrait, small, medium];

  /// Logical pixels per cell for [fitScreen]: about the default board's density in a desktop window.
  static const screenCellSize = 2.0;

  /// A board shaped like a screen of [width] x [height] logical pixels, at
  /// [screenCellSize] per cell, so Board only fills it edge to edge.
  factory BoardSize.fitScreen(double width, double height) => BoardSize._(
    (width / screenCellSize).round().clamp(64, 2048),
    (height / screenCellSize).round().clamp(64, 2048),
    fitsScreen: true,
  );

  /// The size a shared seed or favorite came with: a preset if it is one.
  factory BoardSize.of(int width, int height) =>
      values.firstWhere((s) => s.width == width && s.height == height, orElse: () => BoardSize._(width, height));

  final int width;
  final int height;
  final bool fitsScreen;

  String get label => fitsScreen ? 'Fit screen · $width×$height' : '$width×$height';

  /// For tight spaces (the phone's size picker).
  String get shortLabel => fitsScreen ? 'Fit screen' : label;

  @override
  bool operator ==(Object other) => other is BoardSize && other.width == width && other.height == height && other.fitsScreen == fitsScreen;

  @override
  int get hashCode => Object.hash(width, height, fitsScreen);

  @override
  String toString() => 'BoardSize($label)';
}

/// One of the AI's `simulate` calls, replayed on the live board so the user
/// can watch what Claude is testing.
class Experiment {
  Experiment({required this.number, required this.seed, required this.generations});

  /// Playback aims to fit in about this long, whatever the length of the run.
  static const targetSeconds = 8.0;

  final int number;
  final Grid seed;
  final int generations;

  /// Fast-forwards long runs; never slower than 15/s so short ones stay lively.
  double get rate => (generations / targetSeconds).clamp(15, 480).toDouble();
}

/// Owns the running simulation: which engine, play/pause, speed, editing.
/// The UI's ticker calls [tick] every frame; everything else is commands.
class LifeController extends ChangeNotifier {
  LifeController(this._shaders) : pipeline = GlowPipeline(_shaders);

  final Shaders _shaders;
  final GlowPipeline pipeline;
  late LifeEngine engine;

  /// Where the current run began, with checkpoints for stepping backwards.
  /// Restarted by anything that puts a new board down (a seed, clear, an
  /// experiment, or drawing: an edit is a new beginning); kept across an
  /// engine switch, which changes nothing about the board.
  Timeline? timeline;

  /// The generation "back to the start" returns to.
  int get originGeneration => timeline?.originGeneration ?? 0;
  bool get atBeginning => generation <= originGeneration;

  /// Like stepping forward, stepping back works while paused.
  bool get canStepBack => !running && timeline != null && !atBeginning;

  BoardSize boardSize = BoardSize.medium;

  /// What's on the board, for naming a saved moment: a seed's prompt or
  /// share-link title, or null for random and hand-drawn boards.
  String? boardTitle;
  String? _pendingHandOffTitle;

  /// Title for saving the board right now, e.g. "A lonely pulsar · gen 340".
  String get momentTitle => '${boardTitle ?? 'My board'} · gen $generation';

  /// The board exactly as it is now, running or not, with its title. Taken
  /// together between steps, so a moment titled "gen 340" is generation 340.
  Future<({Grid seed, String title})> captureMoment() => _whileIdle(() async => (seed: await engine.snapshot(), title: momentTitle));
  bool running = false;

  /// Target rates, in generations per second. A rate (not "generations per
  /// frame") keeps the speed the same on 60 Hz and 120 Hz displays.
  static const speedLevels = [1, 2, 4, 8, 15, 30, 60, 120, 240, 480, 960];
  int speedIndex = 4;
  int get targetRate => speedLevels[speedIndex];

  /// Measured rate, which falls short of [targetRate] when the engine can't keep up.
  double gensPerSecond = 0;

  double? _lastTick;
  double _due = 0; // generations owed since the last step

  /// The AI experiment being replayed, if any. Stays set (paused on its last
  /// frame) after it ends, so the overlay can show the result.
  Experiment? experiment;
  final _experimentQueue = <Experiment>[];
  Grid? _pendingHandOff;
  double? _holdUntil;

  /// Pause between queued experiments, so the end state of one is visible.
  static const _holdSeconds = 0.8;

  bool get experimentFinished => experiment != null && generation >= experiment!.generations;
  double get _rate => experiment != null && !experimentFinished ? experiment!.rate : targetRate.toDouble();

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

  LifeEngine _create(EngineKind kind) => kind == EngineKind.cpu ? CpuEngine() : GpuEngine(_shaders.lifeStep);

  /// Called every display frame with the ticker's clock in seconds. Steps
  /// however many generations are due at [targetRate]: zero on most frames at
  /// slow speeds, several per frame at fast ones.
  Future<void> tick(double now) async {
    if (_disposed) return;
    final dt = _lastTick == null ? 0.0 : (now - _lastTick!).clamp(0.0, 0.1);
    _lastTick = now;
    if (_busy) return;
    if (experimentFinished) {
      await _afterExperiment(now);
      return;
    }
    if (!running) return;
    final rate = _rate;
    _due += dt * rate;
    // Epsilon: summing many frame-sized fractions lands a hair under whole numbers.
    if (_due < 1 - 1e-9) return;
    var n = (_due + 1e-9).floor().clamp(1, 32);
    _due -= n;
    // If the engine can't keep up, drop the backlog rather than spiral; the HUD's
    // measured rate shows the real throughput.
    if (_due > rate * 0.25) _due = 0;
    // An experiment stops on exactly the generation Claude simulated.
    if (experiment != null) n = min(n, experiment!.generations - generation);
    // Stop each batch on the timeline's next checkpoint, so snapshots land on exact generations.
    if (timeline != null) n = min(n, timeline!.nextSnapshotAfter(generation) - generation);
    _busy = true;
    try {
      await engine.step(n);
      await _recordCheckpoint();
      _publish();
      _gensSinceSample += n;
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

  /// An experiment reached its last generation: pause on it, then play the next
  /// queued one or hand over Claude's final seed.
  Future<void> _afterExperiment(double now) async {
    if (running && _experimentQueue.isEmpty && _pendingHandOff == null) {
      running = false;
      gensPerSecond = 0;
      notifyListeners();
      return;
    }
    if (_experimentQueue.isEmpty && _pendingHandOff == null) return;
    _holdUntil ??= now + _holdSeconds;
    if (now < _holdUntil!) return;
    _holdUntil = null;
    if (_experimentQueue.isNotEmpty) {
      await _startExperiment(_experimentQueue.removeAt(0));
    } else {
      final seed = _pendingHandOff!;
      _pendingHandOff = null;
      await _loadAndRun(seed, title: _pendingHandOffTitle);
    }
  }

  // ---- AI experiments ---------------------------------------------------------

  /// Replays an experiment, or queues it behind the one already playing.
  Future<void> playExperiment(Experiment e) async {
    if (experiment != null && !experimentFinished) {
      _experimentQueue.add(e);
      return;
    }
    await _startExperiment(e);
  }

  Future<void> _startExperiment(Experiment e) => _whileIdle(() async {
    await engine.load(e.seed);
    timeline = Timeline(e.seed);
    experiment = e;
    boardTitle = "Claude's experiment ${e.number}";
    running = true;
    _due = 0;
    _publish();
  });

  /// Claude finished: play its seed for real once the experiments have been shown.
  Future<void> handOff(Grid seed, {String? title}) async {
    onSeedOpened?.call(seed, SeedSource.assistant);
    if ((experiment != null && !experimentFinished) || _experimentQueue.isNotEmpty) {
      _pendingHandOff = seed;
      _pendingHandOffTitle = title;
      return;
    }
    await _loadAndRun(seed, title: title);
  }

  /// Starts [e] again from generation 0, replacing whatever is on the board.
  Future<void> replayExperiment(Experiment e) async {
    _cancelExperiments();
    await _startExperiment(e);
  }

  /// Told whenever a seed is opened, with where from ([SeedSource]) and, for
  /// a community seed, its name. main.dart points it at [Telemetry.seedOpened].
  void Function(Grid seed, SeedSource source, {String? communityName})? onSeedOpened;

  /// Loads [seed] at generation 0 and plays it at the user's speed. Seeds from
  /// favorites and share links carry their own board size; adopt it. Opening
  /// it from somewhere worth counting passes [source] (replays don't).
  Future<void> playSeed(Grid seed, {String? title, SeedSource? source, String? communityName}) {
    if (source != null) onSeedOpened?.call(seed, source, communityName: communityName);
    // Keep a screen-shaped board if the seed is that size; otherwise take the seed's.
    if (seed.width != boardSize.width || seed.height != boardSize.height) boardSize = BoardSize.of(seed.width, seed.height);
    return _loadAndRun(seed, title: title);
  }

  Future<void> _loadAndRun(Grid seed, {String? title}) async {
    await load(seed);
    boardTitle = title;
    running = true;
    _due = 0;
    notifyListeners();
  }

  void _cancelExperiments() {
    experiment = null;
    _experimentQueue.clear();
    _pendingHandOff = null;
    _holdUntil = null;
  }

  void _publish() {
    if (_disposed) return;
    pipeline.update(engine.frame!);
    notifyListeners();
  }

  /// Advances exactly one generation while paused.
  Future<void> stepOnce() => _whileIdle(() async {
    await engine.step(1);
    await _recordCheckpoint();
    _publish();
  });

  /// Goes back one generation while paused. The rules can't run backwards,
  /// so this rebuilds it from the nearest checkpoint (at most 63 steps),
  /// off the UI thread where the platform allows.
  Future<void> stepBack() => _whileIdle(() async {
    final t = timeline;
    if (running || t == null || atBeginning) return;
    final target = generation - 1;
    final nearest = t.nearestAtOrBefore(target);
    final steps = target - nearest.generation;
    final board = steps == 0
        ? nearest.board
        : Grid.fromCells(
            t.width,
            t.height,
            await compute(_advance, (cells: nearest.board.cells, width: t.width, height: t.height, steps: steps)),
          );
    await engine.load(board, generation: target);
    _publish();
  });

  /// Returns to where the current run began, keeping its name and play state.
  Future<void> rewindToStart() => _whileIdle(() async {
    final t = timeline;
    if (t == null || atBeginning) return;
    await engine.load(t.origin, generation: t.originGeneration);
    _due = 0;
    _publish();
  });

  Future<void> _recordCheckpoint() async {
    if (_disposed) return;
    final t = timeline;
    if (t != null && t.wantsSnapshot(generation)) t.record(generation, await engine.snapshot());
  }

  void toggleRunning() {
    // Playing on from the end of an experiment is ordinary play at the user's speed.
    if (experimentFinished) _cancelExperiments();
    running = !running;
    _due = 0;
    _gensSinceSample = 0;
    _rateClock.reset();
    if (!running) gensPerSecond = 0;
    notifyListeners();
  }

  void setGlow(double value) {
    pipeline.glow = value;
    notifyListeners();
  }

  void setSpeedIndex(int index) {
    speedIndex = index.clamp(0, speedLevels.length - 1);
    _due = 0;
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

  /// Replaces the board (used by reset, drawing, and the AI assistant). Any
  /// experiment replay stops: the board now shows something else.
  Future<void> load(Grid grid) => _whileIdle(() async {
    _cancelExperiments();
    boardTitle = null; // callers that know the seed's name set it after loading
    await engine.load(grid);
    timeline = Timeline(grid);
    pipeline.clearTrail();
    _publish();
  });

  // ---- Drawing --------------------------------------------------------------

  Future<void> beginEdit() async {
    _cancelExperiments();
    boardTitle = null; // drawn on: it's the user's board now
    _edit = await engine.snapshot();
  }

  void paintCell(int x, int y, bool alive) {
    final g = _edit;
    if (g == null || x < 0 || y < 0 || x >= g.width || y >= g.height) return;
    // A 2x2 brush on big boards so strokes are visible.
    final r = boardSize.width >= 1024 ? 1 : 0;
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
        timeline = Timeline(g, generation: engine.generation); // an edit is a new beginning
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
    _disposed = true;
    engine.dispose();
    pipeline.dispose();
    super.dispose();
  }

  /// Work already in flight (a step waiting on the isolate, a checkpoint
  /// readback) can finish after dispose; it must then touch nothing.
  bool _disposed = false;
}

/// Steps a board forward in a background isolate (inline on the web).
Uint8List _advance(({Uint8List cells, int width, int height, int steps}) r) {
  var a = Grid.fromCells(r.width, r.height, Uint8List.fromList(r.cells)), b = Grid(r.width, r.height);
  for (var i = 0; i < r.steps; i++) {
    a.stepInto(b);
    final t = a;
    a = b;
    b = t;
  }
  return a.cells;
}
