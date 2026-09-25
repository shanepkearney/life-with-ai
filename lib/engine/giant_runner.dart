import 'dart:typed_data';

import '../core/hashlife.dart';
import 'giant_runner_inline.dart' if (dart.library.io) 'giant_runner_isolate.dart' as impl;

/// Which part of the plane to draw: [width] x [height] pixels whose top-left
/// is the cell at ([left], [top]), each pixel covering 2^[k] x 2^[k] cells.
typedef GiantView = ({int left, int top, int k, int width, int height});

/// A drawn view, as RGBA ready for the glow pipeline, with the pattern's state.
typedef GiantFrame = ({Uint8List rgba, int width, int height, int generation, int population, ({int x, int y, int width, int height})? bounds});

/// Runs a giant pattern on [HashPlane], off the UI thread where the platform
/// allows (like the CPU engine's stepper): natively in an isolate, inline on
/// the web.
abstract class GiantRunner {
  factory GiantRunner() => impl.create();

  /// On the UI thread, on any platform: the web's runner, and the one widget
  /// tests use (their clock doesn't deliver an isolate's replies).
  factory GiantRunner.inline() = InlineGiantRunner;

  /// True when it shares the UI thread (the web), so big jumps are rationed.
  bool get inline;

  /// Loads [cells], (x, y) pairs flattened, and draws [view].
  Future<GiantFrame> load(Int32List cells, GiantView view);

  /// Moves on 2^[j] generations, then draws [view].
  Future<GiantFrame> advance(int j, GiantView view);

  /// Draws [view] without moving on (panning, zooming).
  Future<GiantFrame> render(GiantView view);

  /// Back to generation 0, then draws [view].
  Future<GiantFrame> restart(GiantView view);

  void dispose();
}

/// The work itself, shared by both runners.
class GiantWorld {
  GiantWorld(Int32List cells, {int maxNodes = 1 << 22})
    : plane = HashPlane.fromCells(HashLife(maxNodes: maxNodes), [for (var i = 0; i + 1 < cells.length; i += 2) (cells[i], cells[i + 1])]);

  final HashPlane plane;

  GiantFrame draw(GiantView v) {
    final px = plane.render(v.left, v.top, v.k, v.width, v.height);
    final rgba = Uint8List(px.length * 4);
    for (var i = 0; i < px.length; i++) {
      final b = px[i];
      if (b == 0) continue;
      rgba[i * 4] = b;
      rgba[i * 4 + 1] = b;
      rgba[i * 4 + 2] = b;
    }
    for (var i = 3; i < rgba.length; i += 4) {
      rgba[i] = 255;
    }
    return (rgba: rgba, width: v.width, height: v.height, generation: plane.generation, population: plane.population, bounds: plane.bounds);
  }
}

/// Runs on the UI thread: the web has no shared-memory isolates. Its table
/// is smaller, to suit a browser tab.
class InlineGiantRunner implements GiantRunner {
  GiantWorld? _world;

  @override
  bool get inline => true;

  @override
  Future<GiantFrame> load(Int32List cells, GiantView view) async {
    _world = GiantWorld(cells, maxNodes: 1 << 20);
    return _world!.draw(view);
  }

  @override
  Future<GiantFrame> advance(int j, GiantView view) async {
    _world!.plane.advance(j);
    return _world!.draw(view);
  }

  @override
  Future<GiantFrame> render(GiantView view) async => _world!.draw(view);

  @override
  Future<GiantFrame> restart(GiantView view) async {
    _world!.plane.restart();
    return _world!.draw(view);
  }

  @override
  void dispose() => _world = null;
}
