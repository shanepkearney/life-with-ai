import 'dart:typed_data';

import 'life_rule.dart';

/// A toroidal Game of Life board: one byte per cell (0 = dead, 1 = alive),
/// row-major, edges wrapping — the same topology as the original Java version.
///
/// This is deliberately free of Flutter imports so it can run in an isolate,
/// inside the AI agent's sandbox, and in plain `dart test`.
class Grid {
  Grid(this.width, this.height) : cells = Uint8List(width * height);

  Grid.fromCells(this.width, this.height, this.cells) : assert(cells.length == width * height);

  final int width;
  final int height;
  final Uint8List cells;

  int _index(int x, int y) => (y % height + height) % height * width + (x % width + width) % width;

  bool get(int x, int y) => cells[_index(x, y)] == 1;

  /// Coordinates wrap, so callers (and the AI) may place patterns across an edge.
  void set(int x, int y, bool alive) => cells[_index(x, y)] = alive ? 1 : 0;

  void clear() => cells.fillRange(0, cells.length, 0);

  Grid copy() => Grid.fromCells(width, height, Uint8List.fromList(cells));

  int get population {
    var n = 0;
    for (final c in cells) {
      n += c;
    }
    return n;
  }

  /// Advances one generation into [out] (which must be a different grid of
  /// the same size) and returns it, by [rule]. Double-buffering avoids
  /// allocating per step.
  Grid stepInto(Grid out, [LifeRule rule = LifeRule.conway]) {
    assert(out.width == width && out.height == height && !identical(out, this));
    if (!rule.isConway) return _stepByTable(out, rule.table);
    final src = cells;
    final dst = out.cells;
    final w = width;
    for (var y = 0; y < height; y++) {
      final up = ((y - 1 + height) % height) * w;
      final mid = y * w;
      final down = ((y + 1) % height) * w;
      for (var x = 0; x < w; x++) {
        // Only the first and last column need the modulo; keep the hot path branch-light.
        final l = x == 0 ? w - 1 : x - 1;
        final r = x == w - 1 ? 0 : x + 1;
        final n = src[up + l] + src[up + x] + src[up + r] + src[mid + l] + src[mid + r] + src[down + l] + src[down + x] + src[down + r];
        final alive = src[mid + x];
        dst[mid + x] = (n == 3 || (n == 2 && alive == 1)) ? 1 : 0;
      }
    }
    return out;
  }

  /// Any rule: the next state is looked up by `alive * 9 + neighbors`.
  /// Conway keeps its own loop above, unchanged, as the fast path.
  Grid _stepByTable(Grid out, Uint8List table) {
    final src = cells;
    final dst = out.cells;
    final w = width;
    for (var y = 0; y < height; y++) {
      final up = ((y - 1 + height) % height) * w;
      final mid = y * w;
      final down = ((y + 1) % height) * w;
      for (var x = 0; x < w; x++) {
        final l = x == 0 ? w - 1 : x - 1;
        final r = x == w - 1 ? 0 : x + 1;
        final n = src[up + l] + src[up + x] + src[up + r] + src[mid + l] + src[mid + r] + src[down + l] + src[down + x] + src[down + r];
        dst[mid + x] = table[src[mid + x] * 9 + n];
      }
    }
    return out;
  }

  /// Convenience for callers that don't care about allocation.
  Grid step([LifeRule rule = LifeRule.conway]) => stepInto(Grid(width, height), rule);

  /// Smallest rectangle containing every live cell, or null when empty.
  /// Not wrap-aware: a pattern straddling an edge reports the full span.
  ({int x, int y, int width, int height})? get boundingBox {
    var minX = width, minY = height, maxX = -1, maxY = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (cells[row + x] == 1) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return null;
    return (x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  }

  /// FNV-1a over the cell bytes; used to detect still lifes and oscillators.
  int get stateHash {
    var h = 0x811c9dc5;
    for (final c in cells) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// Writes one RGBA pixel per cell (white = alive, transparent = dead) so the
  /// GPU can sample the board as a texture.
  Uint8List toRgba([Uint8List? into]) {
    final out = into ?? Uint8List(cells.length * 4);
    final px = out.buffer.asUint32List(out.offsetInBytes, cells.length);
    for (var i = 0; i < cells.length; i++) {
      px[i] = cells[i] == 1 ? 0xFFFFFFFF : 0x00000000;
    }
    return out;
  }

  /// Reads back a board from RGBA pixels (red channel > 127 means alive).
  static Grid fromRgba(int width, int height, Uint8List rgba) {
    final g = Grid(width, height);
    for (var i = 0; i < g.cells.length; i++) {
      g.cells[i] = rgba[i * 4] > 127 ? 1 : 0;
    }
    return g;
  }

  /// Down-samples the board to an ASCII picture no wider than [maxCols].
  /// Each character covers a block of cells: ' ' empty, '.' sparse, 'o' busy,
  /// '#' dense. This is how the AI "sees" the board.
  String toAscii({int maxCols = 96, int maxRows = 48, int? x0, int? y0, int? w, int? h}) {
    final ox = x0 ?? 0, oy = y0 ?? 0;
    final rw = w ?? width, rh = h ?? height;
    final block = [(rw / maxCols).ceil(), (rh / maxRows).ceil(), 1].reduce((a, b) => a > b ? a : b);
    final cols = (rw / block).ceil(), rows = (rh / block).ceil();
    final buf = StringBuffer();
    for (var by = 0; by < rows; by++) {
      for (var bx = 0; bx < cols; bx++) {
        var live = 0, total = 0;
        for (var dy = 0; dy < block; dy++) {
          final y = by * block + dy;
          if (y >= rh) break;
          for (var dx = 0; dx < block; dx++) {
            final x = bx * block + dx;
            if (x >= rw) break;
            total++;
            if (get(ox + x, oy + y)) live++;
          }
        }
        final f = total == 0 ? 0.0 : live / total;
        buf.write(
          live == 0
              ? ' '
              : f < 0.15
              ? '.'
              : f < 0.4
              ? 'o'
              : '#',
        );
      }
      buf.writeln();
    }
    return buf.toString();
  }
}
