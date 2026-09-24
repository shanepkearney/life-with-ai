import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/grid.dart';
import '../core/patterns.dart';
import 'theme.dart';

/// The app's loading indicator: the logo's neon glider, flying. Its four
/// phases come from running the real B3/S23 rules, not from drawings, and the
/// camera follows it so it cycles in place, with a faint ghost where cells just died.
/// Cells cool from the tail (cyan) to the leading edge (amber), as in the icon.
class GliderLoader extends StatefulWidget {
  const GliderLoader({super.key, this.size = 56, this.label, this.showAfter = const Duration(milliseconds: 150)});

  final double size;
  final String? label;

  /// Loads that finish sooner never show it, so a fast load doesn't flicker.
  final Duration showAfter;

  /// Live cells for each of the glider's four phases, found by stepping it.
  /// After four generations it is the same shape, one cell down and right.
  static final List<List<(int, int)>> phases = () {
    var grid = Grid(12, 12);
    patternLibrary['glider']!.stampOnto(grid, 2, 2);
    final out = <List<(int, int)>>[];
    for (var gen = 0; gen < 4; gen++) {
      out.add([
        for (var y = 0; y < grid.height; y++)
          for (var x = 0; x < grid.width; x++)
            if (grid.get(x, y)) (x - 2 - gen ~/ 4, y - 2 - gen ~/ 4),
      ]);
      grid = grid.step();
    }
    return out;
  }();

  @override
  State<GliderLoader> createState() => _GliderLoaderState();
}

class _GliderLoaderState extends State<GliderLoader> with SingleTickerProviderStateMixin {
  /// One loop is four generations: the glider's full period.
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4 * 170),
  )..repeat();
  late bool _visible = widget.showAfter == Duration.zero;
  Timer? _reveal;

  @override
  void initState() {
    super.initState();
    if (!_visible) _reveal = Timer(widget.showAfter, () => setState(() => _visible = true));
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label ?? 'Loading',
    liveRegion: true,
    child: AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: widget.size,
              child: CustomPaint(painter: _GliderPainter(_clock)),
            ),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Text(widget.label!, style: Neon.mono.copyWith(fontSize: 11, color: Neon.muted)),
            ),
          ],
        ],
      ),
    ),
  );
}

class _GliderPainter extends CustomPainter {
  _GliderPainter(this.clock) : super(repaint: clock);

  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    // The view is 5 cells across; the 3x3 glider sits in the middle.
    final cell = size.shortestSide / 5;
    final loop = clock.value * 4; // generations into this loop, 0..4
    final now = loop.floor();
    // The camera glides a quarter cell per generation, so the glider stays centred.
    final camera = loop / 4;

    // Where generation [gen]'s cells are, in cells (one cell on every four generations).
    List<(int, int)> at(int gen) {
      final shift = (gen / 4).floor();
      return [for (final (x, y) in GliderLoader.phases[gen % 4]) (x + shift, y + shift)];
    }

    final live = at(now);
    // A ghost of the generation before, only where cells just died: a hint of motion, not a blur.
    for (final c in at(now - 1).where((c) => !live.contains(c))) {
      _cell(canvas, c, cell, camera, Neon.cyan.withValues(alpha: 0.18), glow: false);
    }
    // Tail to leading edge along the direction of travel: cyan → magenta → amber, as in the icon.
    final sums = live.map((c) => c.$1 + c.$2);
    final lo = sums.reduce(math.min), hi = sums.reduce(math.max);
    for (final c in live) {
      final t = (c.$1 + c.$2 - lo) / (hi - lo);
      final color = t < 0.5 ? Color.lerp(Neon.cyan, Neon.magenta, t * 2)! : Color.lerp(Neon.magenta, Neon.amber, (t - 0.5) * 2)!;
      _cell(canvas, c, cell, camera, color, glow: true);
    }
  }

  void _cell(Canvas canvas, (int, int) c, double cell, double camera, Color color, {required bool glow}) {
    final x = c.$1 - camera + 1, y = c.$2 - camera + 1;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x * cell + cell * 0.1, y * cell + cell * 0.1, cell * 0.8, cell * 0.8),
      Radius.circular(cell * 0.22),
    );
    if (glow) {
      canvas.drawRRect(
        rect.inflate(cell * 0.06),
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(2, cell * 0.3)),
      );
    }
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GliderPainter old) => false; // repaints with the clock
}
