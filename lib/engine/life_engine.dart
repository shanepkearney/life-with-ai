import 'dart:ui' as ui;

import '../core/grid.dart';
import '../core/life_rule.dart';

enum EngineKind {
  cpu('CPU · isolate', 'CPU', 'Plain Conway rules, a background isolate'),
  gpu('GPU · shader', 'GPU', 'A fragment shader: the fastest on these boards'),
  hashlife('HashLife · tree', 'HashLife', "Gosper's HashLife, the algorithm Golly uses for giant patterns");

  const EngineKind(this.label, this.short, this.about);

  /// For the stats line.
  final String label;

  /// For the engine switch, where room is tight.
  final String short;

  /// A tooltip line.
  final String about;
}

/// A Game of Life simulator that exposes each generation as a GPU texture
/// (one pixel per cell), so rendering is identical whichever engine runs it.
abstract class LifeEngine {
  EngineKind get kind;
  int get width;
  int get height;
  int get generation;

  /// Live-cell count. The GPU engine refreshes this lazily (a readback is
  /// expensive), so it may lag a few generations behind [generation].
  int get population;

  /// Current generation as an image, or null before the first [load].
  ui.Image? get frame;

  /// The rule [step] follows, set by [load].
  LifeRule get rule;

  /// Replaces the board, and the [rule] it runs by. [generation] lets an edit
  /// or engine swap keep counting.
  Future<void> load(Grid grid, {int generation = 0, LifeRule rule = LifeRule.conway});

  /// Advances [generations] steps.
  Future<void> step([int generations = 1]);

  /// Copies the current board back to the CPU.
  Future<Grid> snapshot();

  void dispose();
}
