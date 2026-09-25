import 'dart:typed_data';

import 'grid.dart';

/// A square of the board in HashLife's quadtree: a single cell at level 0,
/// otherwise four half-size quadrants. Nodes are canonical ("hash-consed"):
/// two identical squares anywhere, at any time, are the same object, so a
/// result worked out for one is reused for every copy.
final class HashNode {
  HashNode._(this.id, this.level, this.nw, this.ne, this.sw, this.se, this.population);

  /// Unique per node, for hashing its parents.
  final int id;
  final int level;
  final HashNode? nw, ne, sw, se;
  final int population;

  /// The centre half of this square one generation later (see [HashLife.step1]).
  HashNode? _next;

  int get size => 1 << level;
}

/// Bill Gosper's HashLife (1984), the algorithm Golly uses for giant
/// patterns. This is the foundation: canonical nodes and a memoized
/// one-generation step, used here to run the app's wrap-around boards
/// cell-for-cell like the other engines.
///
/// On a wrap-around board every generation rebuilds the tree from the board
/// (its edges must meet), so it is correct but not faster than the plain
/// engines. HashLife's speed comes from repetition and from jumping many
/// generations at once, which needs an unbounded plane: the next stage.
///
/// Free of Flutter imports, like [Grid], so it runs in an isolate and in
/// plain `dart test`.
class HashLife {
  HashLife({this.maxNodes = 1 << 21}) {
    _empty.add(off);
    _registerLeaves();
  }

  /// The sixteen 2x2 squares, by bits (nw = 1, ne = 2, sw = 4, se = 8), so the
  /// smallest squares never need a table lookup.
  final _leaves = List<HashNode?>.filled(16, null);

  void _registerLeaves() {
    for (var b = 0; b < 16; b++) {
      HashNode c(int bit) => b & bit != 0 ? on : off;
      _leaves[b] = join(c(1), c(2), c(4), c(8));
    }
  }

  /// A 2x2 square's bits (see [_leaves]).
  static int _bits(HashNode leaf) => leaf.nw!.population | leaf.ne!.population << 1 | leaf.sw!.population << 2 | leaf.se!.population << 3;

  /// For every 4x4 square (16 bits, row by row from the top-left), the bits
  /// of its centre 2x2 one generation later. Built once, shared.
  static final Uint8List _next4x4 = () {
    final table = Uint8List(1 << 16);
    for (var s = 0; s < 1 << 16; s++) {
      int cell(int x, int y) => s >> (y * 4 + x) & 1;
      int next(int x, int y) {
        var count = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx != 0 || dy != 0) count += cell(x + dx, y + dy);
          }
        }
        return count == 3 || (count == 2 && cell(x, y) == 1) ? 1 : 0;
      }

      table[s] = next(1, 1) | next(2, 1) << 1 | next(1, 2) << 2 | next(2, 2) << 3;
    }
    return table;
  }();

  /// Canonical nodes are forgotten (and rebuilt as needed) past this many.
  final int maxNodes;

  static final off = HashNode._(0, 0, null, null, null, null, 0);
  static final on = HashNode._(1, 0, null, null, null, null, 1);

  // The canonical table: open addressing on the children's ids, which is
  // several times faster than a general map keyed on four objects.
  var _table = List<HashNode?>.filled(1 << 16, null);
  var _count = 0;
  var _nextId = 2;
  final _empty = <HashNode>[];

  int get nodeCount => _count;

  // Kept under 2^30 at every step, so it's the same on the web (53-bit ints).
  static int _hash(int a, int b, int c, int d) {
    var h = (a * 1000003 ^ b) & 0x3fffffff;
    h = (h * 1000003 ^ c) & 0x3fffffff;
    return (h * 1000003 ^ d) & 0x3fffffff;
  }

  /// The canonical node with these quadrants.
  HashNode join(HashNode nw, HashNode ne, HashNode sw, HashNode se) {
    final mask = _table.length - 1;
    var i = _hash(nw.id, ne.id, sw.id, se.id) & mask;
    while (true) {
      final n = _table[i];
      if (n == null) break;
      if (identical(n.nw, nw) && identical(n.ne, ne) && identical(n.sw, sw) && identical(n.se, se)) return n;
      i = (i + 1) & mask;
    }
    final node = HashNode._(_nextId++, nw.level + 1, nw, ne, sw, se, nw.population + ne.population + sw.population + se.population);
    _table[i] = node;
    if (++_count * 2 > _table.length) _grow();
    return node;
  }

  void _grow() {
    final old = _table;
    _table = List<HashNode?>.filled(old.length * 2, null);
    _count = 0;
    for (final n in old) {
      if (n != null) _insert(n);
    }
  }

  void _insert(HashNode n) {
    final mask = _table.length - 1;
    var i = _hash(n.nw!.id, n.ne!.id, n.sw!.id, n.se!.id) & mask;
    while (_table[i] != null) {
      i = (i + 1) & mask;
    }
    _table[i] = n;
    _count++;
  }

  /// The all-dead node of [level].
  HashNode empty(int level) {
    while (_empty.length <= level) {
      final e = _empty.last;
      _empty.add(join(e, e, e, e));
    }
    return _empty[level];
  }

  /// The centre half of [n], one generation later: a node one level down.
  /// Only the centre can be known, since its edges depend on cells outside.
  HashNode step1(HashNode n) {
    assert(n.level >= 2);
    final memo = n._next;
    if (memo != null) return memo;
    final HashNode result;
    if (n.level == 2) {
      result = _step4x4(n);
    } else {
      // Nine overlapping squares, a level down, tile the node with overlap.
      final n00 = n.nw!, n02 = n.ne!, n20 = n.sw!, n22 = n.se!;
      final n01 = join(n.nw!.ne!, n.ne!.nw!, n.nw!.se!, n.ne!.sw!);
      final n10 = join(n.nw!.sw!, n.nw!.se!, n.sw!.nw!, n.sw!.ne!);
      final n11 = join(n.nw!.se!, n.ne!.sw!, n.sw!.ne!, n.se!.nw!);
      final n12 = join(n.ne!.sw!, n.ne!.se!, n.se!.nw!, n.se!.ne!);
      final n21 = join(n.sw!.ne!, n.se!.nw!, n.sw!.se!, n.se!.sw!);
      // Each quadrant of the answer is the next generation of the square
      // made of the centres of the four overlapping squares around it.
      result = join(
        step1(join(_centre(n00), _centre(n01), _centre(n10), _centre(n11))),
        step1(join(_centre(n01), _centre(n02), _centre(n11), _centre(n12))),
        step1(join(_centre(n10), _centre(n11), _centre(n20), _centre(n21))),
        step1(join(_centre(n11), _centre(n12), _centre(n21), _centre(n22))),
      );
    }
    n._next = result;
    return result;
  }

  HashNode _centre(HashNode n) => join(n.nw!.se!, n.ne!.sw!, n.sw!.ne!, n.se!.nw!);

  /// A 4x4 square's centre 2x2, one generation later, by Conway's rules
  /// (looked up in [_next4x4]).
  HashNode _step4x4(HashNode n) {
    final a = _bits(n.nw!), b = _bits(n.ne!), c = _bits(n.sw!), d = _bits(n.se!);
    // Rows of four, top to bottom: each quadrant's top pair, then its bottom pair.
    final s = (a & 3) | (b & 3) << 2 | (a >> 2) << 4 | (b >> 2) << 6 | (c & 3) << 8 | (d & 3) << 10 | (c >> 2) << 12 | (d >> 2) << 14;
    return _leaves[_next4x4[s]]!;
  }

  /// One generation of a wrap-around [board], by way of the tree: the board
  /// sits in the middle of a square twice its size, ringed by the cells its
  /// edges wrap to, and [step1] of that square is exactly the board's next
  /// generation.
  Grid stepTorus(Grid board) {
    if (_count > maxNodes) _forget();
    final w = board.width, h = board.height;
    var level = 2;
    while ((1 << level) < 2 * (w > h ? w : h)) {
      level++;
    }
    final offset = (1 << level) >> 2; // the board's corner inside the square
    final cells = board.cells;

    // Board cells, plus a one-cell ring copied from the opposite edges.
    int cellAt(int x, int y) {
      final bx = x - offset, by = y - offset;
      if (bx < -1 || by < -1 || bx > w || by > h) return 0;
      return cells[((by + h) % h) * w + (bx + w) % w];
    }

    HashNode build(int level, int x0, int y0) {
      final size = 1 << level;
      if (x0 + size <= offset - 1 || y0 + size <= offset - 1 || x0 > offset + w || y0 > offset + h) return empty(level);
      if (level == 1) {
        return _leaves[cellAt(x0, y0) | cellAt(x0 + 1, y0) << 1 | cellAt(x0, y0 + 1) << 2 | cellAt(x0 + 1, y0 + 1) << 3]!;
      }
      final half = size >> 1;
      return join(build(level - 1, x0, y0), build(level - 1, x0 + half, y0), build(level - 1, x0, y0 + half), build(level - 1, x0 + half, y0 + half));
    }

    final next = step1(build(level, 0, 0)); // covers [offset, 3 * offset): the board at its corner
    final out = Grid(w, h);
    _write(next, 0, 0, out);
    return out;
  }

  /// Copies [n]'s live cells, with its corner at ([x0], [y0]), into [out],
  /// ignoring any beyond the board (the wrap-around ring's own next state).
  void _write(HashNode n, int x0, int y0, Grid out) {
    if (n.population == 0 || x0 >= out.width || y0 >= out.height) return;
    if (n.level == 0) {
      out.cells[y0 * out.width + x0] = 1;
      return;
    }
    final half = n.size >> 1;
    _write(n.nw!, x0, y0, out);
    _write(n.ne!, x0 + half, y0, out);
    _write(n.sw!, x0, y0 + half, out);
    _write(n.se!, x0 + half, y0 + half, out);
  }

  /// Drops the canonical table when it grows past [maxNodes]. Results already
  /// worked out stay correct; later copies just don't share them.
  void _forget() {
    _table = List<HashNode?>.filled(1 << 16, null);
    _count = 0;
    for (final n in [..._empty.skip(1), ..._leaves.cast<HashNode>()]) {
      if (_count * 2 >= _table.length) _grow();
      _insert(n);
    }
  }
}
