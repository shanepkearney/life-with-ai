import 'dart:math';

import 'package:flutter/material.dart';

import '../core/grid.dart';
import 'theme.dart';

/// A small static picture of a seed, cropped to its live cells and scaled to
/// fit. Small seeds draw each cell; seeds too big for one pixel per cell (a
/// saved random board) draw a density preview instead. Always clipped to the
/// tile, whatever the seed's size.
class SeedThumbnail extends StatelessWidget {
  const SeedThumbnail(this.seed, {super.key, this.size = 56});

  final Grid seed;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Neon.background,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Neon.border),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: CustomPaint(size: Size.square(size), painter: SeedPainter(seed)),
    ),
  );
}

/// Visible for testing.
class SeedPainter extends CustomPainter {
  SeedPainter(this.seed) : box = seed.boundingBox;

  final Grid seed;
  final ({int x, int y, int width, int height})? box;

  static const _pad = 6.0;

  /// Below this many pixels per cell, individual cells stop being readable.
  static const _minCellPx = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final b = box;
    if (b == null) return;
    final avail = size.shortestSide - _pad * 2;
    // Fit the bounding box, keeping cells square; tiny seeds cap at 8px per cell.
    final scale = min(8.0, avail / max(b.width, b.height));
    final ox = (size.width - b.width * scale) / 2, oy = (size.height - b.height * scale) / 2;
    if (scale >= _minCellPx) {
      _paintCells(canvas, b, scale, ox, oy);
    } else {
      _paintDensity(canvas, b, scale, ox, oy);
    }
  }

  void _paintCells(Canvas canvas, ({int x, int y, int width, int height}) b, double scale, double ox, double oy) {
    final glow = Paint()
      ..color = Neon.cyan.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final body = Paint()..color = Neon.cyan;
    for (var y = 0; y < b.height; y++) {
      for (var x = 0; x < b.width; x++) {
        if (!seed.get(b.x + x, b.y + y)) continue;
        final r = Rect.fromLTWH(ox + x * scale, oy + y * scale, scale, scale);
        canvas.drawRect(r.inflate(scale * 0.4), glow);
        canvas.drawRect(r.deflate(scale > 2 ? scale * 0.1 : 0), body);
      }
    }
  }

  /// Seeds too big for one pixel per cell. A dense board (a saved random
  /// soup) samples one cell per pixel, so it keeps the board's speckled
  /// texture; averaging ~100 cells per pixel would smooth noise into a flat
  /// block. A sparse seed lights any pixel whose patch holds a live cell, so
  /// small clusters far apart stay visible.
  void _paintDensity(Canvas canvas, ({int x, int y, int width, int height}) b, double scale, double ox, double oy) {
    final w = max(1, (b.width * scale).ceil()), h = max(1, (b.height * scale).ceil());
    final dense = seed.population / (b.width * b.height) > 0.05;
    final paint = Paint();
    final lit = Neon.cyan.withValues(alpha: 0.95), dim = Neon.cyan.withValues(alpha: 0.12);
    final glow = Paint()
      ..color = Neon.cyan.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    for (var py = 0; py < h; py++) {
      final y0 = (py / scale).floor(), y1 = min(b.height, ((py + 1) / scale).ceil());
      for (var px = 0; px < w; px++) {
        final x0 = (px / scale).floor(), x1 = min(b.width, ((px + 1) / scale).ceil());
        final bool on;
        if (dense) {
          on = seed.get(b.x + (x0 + x1) ~/ 2, b.y + (y0 + y1) ~/ 2);
        } else {
          on = _anyAlive(b.x + x0, b.y + y0, b.x + x1, b.y + y1);
        }
        if (!on && !dense) continue;
        if (!dense) {
          // Sparse seeds: each lit patch is a lone cluster, so draw it as a small
          // glowing dot rather than a single, near-invisible pixel.
          final c = Offset(ox + px + 0.5, oy + py + 0.5);
          canvas.drawCircle(c, 3, glow);
          canvas.drawCircle(c, 1.4, paint..color = lit);
          continue;
        }
        paint.color = on ? lit : dim;
        canvas.drawRect(Rect.fromLTWH(ox + px, oy + py, 1, 1), paint);
      }
    }
  }

  bool _anyAlive(int x0, int y0, int x1, int y1) {
    for (var y = y0; y < y1; y++) {
      final row = y * seed.width;
      for (var x = x0; x < x1; x++) {
        if (seed.cells[row + x] == 1) return true;
      }
    }
    return false;
  }

  @override
  bool shouldRepaint(SeedPainter old) => !identical(old.seed, seed);
}
