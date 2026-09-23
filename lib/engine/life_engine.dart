import 'dart:ui' as ui;

import '../core/grid.dart';

enum EngineKind {
  cpu('CPU · isolate'),
  gpu('GPU · shader');

  const EngineKind(this.label);
  final String label;
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

  /// Replaces the board. [generation] lets an edit or engine swap keep counting.
  Future<void> load(Grid grid, {int generation = 0});

  /// Advances [generations] steps.
  Future<void> step([int generations = 1]);

  /// Copies the current board back to the CPU.
  Future<Grid> snapshot();

  void dispose();
}
