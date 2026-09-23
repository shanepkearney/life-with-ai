import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/grid.dart';
import '../core/patterns.dart';
import 'simulation.dart';

/// Result of one tool call, ready to become a `tool_result` block.
class ToolOutcome {
  const ToolOutcome(this.text, {this.png, this.isError = false, this.seedChanged = false, this.finished = false});

  final String text;
  final Uint8List? png;
  final bool isError;
  final bool seedChanged;
  final bool finished;
}

class ToolInputError implements Exception {
  ToolInputError(this.message);
  final String message;
}

typedef Simulator = Future<SimulationReport> Function(SimulationRequest request);

/// Runs simulations off the UI thread on native (`compute` spawns an isolate)
/// and inline on web, where `compute` has no isolate to use.
Future<SimulationReport> defaultSimulator(SimulationRequest r) => compute(runSimulation, r);

/// The tools the model can call. Schemas are plain JSON so they can be sent
/// verbatim; order and content are stable so the tools block stays cacheable.
final List<Map<String, Object>> seedToolDefinitions = [
  {
    'name': 'clear_board',
    'description': 'Kill every cell on the seed board.',
    'input_schema': {'type': 'object', 'properties': <String, Object>{}},
  },
  {
    'name': 'place_pattern',
    'description': 'Stamp a named pattern from the library with its top-left corner at (x, y). '
        'Rotation is clockwise and applied after the optional horizontal flip, and changes the direction '
        'moving patterns travel. Coordinates wrap around the edges.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'enum': patternLibrary.keys.toList()},
        'x': {'type': 'integer'},
        'y': {'type': 'integer'},
        'rotation': {'type': 'integer', 'enum': [0, 90, 180, 270], 'description': 'Degrees clockwise. Default 0.'},
        'flip': {'type': 'boolean', 'description': 'Mirror left-right before rotating. Default false.'},
      },
      'required': ['name', 'x', 'y'],
    },
  },
  {
    'name': 'draw_shape',
    'description': 'Draw live cells in a shape. "line" runs from (x, y) to (x+width, y+height). '
        '"random_soup" fills the rectangle randomly at the given density — the classic way to get a chaotic, '
        'long-lived, colourful region.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'shape': {
          'type': 'string',
          'enum': ['line', 'rect_outline', 'filled_rect', 'ellipse_outline', 'filled_ellipse', 'random_soup'],
        },
        'x': {'type': 'integer'},
        'y': {'type': 'integer'},
        'width': {'type': 'integer'},
        'height': {'type': 'integer'},
        'density': {'type': 'number', 'description': 'random_soup only, 0-1. Default 0.35.'},
        'seed': {'type': 'integer', 'description': 'random_soup only. Same seed gives the same soup.'},
      },
      'required': ['shape', 'x', 'y', 'width', 'height'],
    },
  },
  {
    'name': 'set_cells',
    'description': 'Set individual cells alive (or dead). Use for small custom shapes the library lacks.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'cells': {
          'type': 'array',
          'maxItems': 4000,
          'items': {'type': 'array', 'items': {'type': 'integer'}, 'minItems': 2, 'maxItems': 2},
          'description': '[[x, y], ...]',
        },
        'alive': {'type': 'boolean', 'description': 'Default true.'},
      },
      'required': ['cells'],
    },
  },
  {
    'name': 'view_board',
    'description': 'ASCII view of the current seed (generation 0). Omit the region for the whole board '
        '(down-sampled: " " empty, "." sparse, "o" busy, "#" dense); a region of at most 96x48 is shown 1:1 '
        'with "#" = live cell.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'x': {'type': 'integer'},
        'y': {'type': 'integer'},
        'width': {'type': 'integer'},
        'height': {'type': 'integer'},
      },
    },
  },
  {
    'name': 'simulate',
    'description': 'Run the current seed forward WITHOUT changing it, and report what happens: fate (dies, '
        'still life, oscillator, growing, chaotic), population over time, and at each checkpoint the population, '
        'bounding box, hotspot count (dense regions — these glow brightest on screen) and an ASCII thumbnail. '
        'Set include_image to also get a PNG of the final generation (white = alive) when shape matters.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'generations': {'type': 'integer', 'minimum': 1, 'maximum': maxSimulatedGenerations},
        'checkpoints': {
          'type': 'array',
          'items': {'type': 'integer'},
          'maxItems': 6,
          'description': 'Generations to show thumbnails for. The final generation is always included.',
        },
        'include_image': {'type': 'boolean'},
      },
      'required': ['generations'],
    },
  },
  {
    'name': 'finish',
    'description': 'Hand the seed to the user: it is loaded onto the live board and starts playing. '
        'Call this once you are satisfied (or out of ideas), with a one- or two-sentence summary of '
        'what the user will see.',
    'input_schema': {
      'type': 'object',
      'properties': {'summary': {'type': 'string'}},
      'required': ['summary'],
    },
  },
];

/// The agent's sandbox: a seed board plus the tool implementations.
class SeedWorkbench {
  SeedWorkbench(int width, int height, {Simulator? simulator, Random? random})
      : seed = Grid(width, height),
        _simulate = simulator ?? defaultSimulator,
        _random = random ?? Random();

  Grid seed;
  final Simulator _simulate;
  final Random _random;

  Future<ToolOutcome> run(String name, Map<String, dynamic> input) async {
    try {
      return switch (name) {
        'clear_board' => _clear(),
        'place_pattern' => _place(input),
        'draw_shape' => _draw(input),
        'set_cells' => _setCells(input),
        'view_board' => _view(input),
        'simulate' => await _simulateTool(input),
        'finish' => ToolOutcome('Seed handed to the user.', finished: true),
        _ => ToolOutcome('Unknown tool "$name".', isError: true),
      };
    } on ToolInputError catch (e) {
      return ToolOutcome(e.message, isError: true);
    }
  }

  String get _status {
    final b = seed.boundingBox;
    return 'Seed population ${seed.population}'
        '${b == null ? '' : ', bounding box x=${b.x} y=${b.y} w=${b.width} h=${b.height}'} '
        '(board ${seed.width}x${seed.height}).';
  }

  ToolOutcome _clear() {
    seed.clear();
    return ToolOutcome('Cleared. $_status', seedChanged: true);
  }

  ToolOutcome _place(Map<String, dynamic> input) {
    final name = _string(input, 'name');
    final pattern = patternLibrary[name];
    if (pattern == null) throw ToolInputError('No pattern "$name". Available: ${patternLibrary.keys.join(', ')}.');
    final rotation = _int(input, 'rotation', fallback: 0);
    if (rotation % 90 != 0) throw ToolInputError('rotation must be 0, 90, 180 or 270.');
    final p = pattern.transformed(quarterTurns: rotation ~/ 90, flipX: input['flip'] == true);
    final x = _int(input, 'x'), y = _int(input, 'y');
    p.stampOnto(seed, x, y);
    return ToolOutcome('Placed $name (${p.width}x${p.height}) at ($x, $y), rotation $rotation. $_status', seedChanged: true);
  }

  ToolOutcome _draw(Map<String, dynamic> input) {
    final shape = _string(input, 'shape');
    final x = _int(input, 'x'), y = _int(input, 'y');
    final w = _int(input, 'width'), h = _int(input, 'height');
    if (shape != 'line' && (w < 1 || h < 1)) throw ToolInputError('width and height must be at least 1.');
    if (w.abs() > seed.width * 2 || h.abs() > seed.height * 2) throw ToolInputError('Shape is larger than the board.');

    switch (shape) {
      case 'line':
        final steps = max(w.abs(), h.abs());
        for (var i = 0; i <= steps; i++) {
          final t = steps == 0 ? 0.0 : i / steps;
          seed.set(x + (w * t).round(), y + (h * t).round(), true);
        }
      case 'rect_outline' || 'filled_rect':
        final filled = shape == 'filled_rect';
        for (var j = 0; j < h; j++) {
          for (var i = 0; i < w; i++) {
            if (filled || i == 0 || j == 0 || i == w - 1 || j == h - 1) seed.set(x + i, y + j, true);
          }
        }
      case 'ellipse_outline' || 'filled_ellipse':
        final cx = (w - 1) / 2, cy = (h - 1) / 2;
        final rx = max(w / 2, 0.5), ry = max(h / 2, 0.5);
        for (var j = 0; j < h; j++) {
          for (var i = 0; i < w; i++) {
            final d = pow((i - cx) / rx, 2) + pow((j - cy) / ry, 2);
            // Outline: a band roughly one cell thick around d == 1.
            final band = 1.6 / min(rx, ry);
            if (shape == 'filled_ellipse' ? d <= 1 : (d <= 1 && d >= 1 - band)) seed.set(x + i, y + j, true);
          }
        }
      case 'random_soup':
        final density = (input['density'] as num?)?.toDouble() ?? 0.35;
        if (density <= 0 || density > 1) throw ToolInputError('density must be in (0, 1].');
        final rnd = input['seed'] is int ? Random(input['seed'] as int) : _random;
        for (var j = 0; j < h; j++) {
          for (var i = 0; i < w; i++) {
            if (rnd.nextDouble() < density) seed.set(x + i, y + j, true);
          }
        }
      default:
        throw ToolInputError('Unknown shape "$shape".');
    }
    return ToolOutcome('Drew $shape at ($x, $y) size ${w}x$h. $_status', seedChanged: true);
  }

  ToolOutcome _setCells(Map<String, dynamic> input) {
    final raw = input['cells'];
    if (raw is! List) throw ToolInputError('cells must be an array of [x, y] pairs.');
    if (raw.length > 4000) throw ToolInputError('At most 4000 cells per call.');
    final alive = input['alive'] != false;
    for (final c in raw) {
      if (c is! List || c.length != 2 || c[0] is! int || c[1] is! int) {
        throw ToolInputError('Each cell must be [x, y] with integer coordinates; got $c.');
      }
      seed.set(c[0] as int, c[1] as int, alive);
    }
    return ToolOutcome('Set ${raw.length} cells ${alive ? 'alive' : 'dead'}. $_status', seedChanged: true);
  }

  ToolOutcome _view(Map<String, dynamic> input) {
    if (input.containsKey('x')) {
      final x = _int(input, 'x'), y = _int(input, 'y');
      final w = _int(input, 'width', fallback: 96).clamp(1, 96), h = _int(input, 'height', fallback: 48).clamp(1, 48);
      return ToolOutcome('$_status\nRegion ($x, $y) ${w}x$h:\n${seed.toAscii(x0: x, y0: y, w: w, h: h, maxCols: 96, maxRows: 48)}');
    }
    return ToolOutcome('$_status\n${seed.toAscii()}');
  }

  Future<ToolOutcome> _simulateTool(Map<String, dynamic> input) async {
    final gens = _int(input, 'generations');
    if (gens < 1 || gens > maxSimulatedGenerations) {
      throw ToolInputError('generations must be between 1 and $maxSimulatedGenerations.');
    }
    final cps = (input['checkpoints'] as List?)?.whereType<int>().take(6).toList() ?? const <int>[];
    final report = await _simulate((
      width: seed.width,
      height: seed.height,
      cells: seed.cells,
      generations: gens,
      checkpoints: cps,
      png: input['include_image'] == true,
    ));
    return ToolOutcome(report.toText(), png: report.png);
  }

  static int _int(Map<String, dynamic> input, String key, {int? fallback}) {
    final v = input[key];
    if (v is int) return v;
    if (v is num && v == v.roundToDouble()) return v.toInt();
    if (v == null && fallback != null) return fallback;
    throw ToolInputError('"$key" must be an integer.');
  }

  static String _string(Map<String, dynamic> input, String key) {
    final v = input[key];
    if (v is String && v.isNotEmpty) return v;
    throw ToolInputError('"$key" is required.');
  }
}
