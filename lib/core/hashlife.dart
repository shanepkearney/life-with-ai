import 'dart:typed_data';

import 'grid.dart';
import 'life_rule.dart';

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

  /// The centre half of this square [_nextStep] generations on (a power of
  /// two, see [HashLife.advance]): one remembered answer per square.
  HashNode? _next;
  int _nextStep = -1;

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
  HashLife({this.maxNodes = 1 << 21, this.rule = LifeRule.conway}) : _next4x4 = _tableFor(rule) {
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
  /// of its centre 2x2 one generation later, by [rule].
  final Uint8List _next4x4;

  /// One table per rule, built once and shared.
  static final _tables = <LifeRule, Uint8List>{};

  static Uint8List _tableFor(LifeRule rule) => _tables.putIfAbsent(rule, () {
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
        return rule.next(cell(x, y) == 1, count) ? 1 : 0;
      }

      table[s] = next(1, 1) | next(2, 1) << 1 | next(1, 2) << 2 | next(2, 2) << 3;
    }
    return table;
  });

  /// Canonical nodes are forgotten (and rebuilt as needed) past this many.
  final int maxNodes;

  /// The rule every step follows. A square's remembered futures are only
  /// true for one rule, so a HashLife instance keeps to one.
  final LifeRule rule;

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
  HashNode step1(HashNode n) => advance(n, 0);

  /// The centre half of [n], 2^[j] generations later, a node one level down.
  /// [j] can be up to `level - 2`: HashLife's jump, where a square's future
  /// is built from its quarters' futures, each remembered for every copy.
  HashNode advance(HashNode n, int j) {
    assert(n.level >= 2 && j >= 0 && j <= n.level - 2);
    // Empty space stays empty, unless the rule brings it to life (B0).
    if (n.population == 0 && !rule.birthFromNothing) return empty(n.level - 1);
    final memo = n._next;
    if (memo != null && n._nextStep == j) return memo;
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
      // At full speed each of the nine first moves half the way (2^(level-3)),
      // then the four squares they make move the rest. Slower, the nine only
      // give up their centres, and the four squares make the whole jump.
      final full = j == n.level - 2;
      HashNode part(HashNode x) => full ? advance(x, j - 1) : _centre(x);
      final c00 = part(n00), c01 = part(n01), c02 = part(n02);
      final c10 = part(n10), c11 = part(n11), c12 = part(n12);
      final c20 = part(n20), c21 = part(n21), c22 = part(n22);
      final k = full ? j - 1 : j;
      result = join(
        advance(join(c00, c01, c10, c11), k),
        advance(join(c01, c02, c11, c12), k),
        advance(join(c10, c11, c20, c21), k),
        advance(join(c11, c12, c21, c22), k),
      );
    }
    n
      .._next = result
      .._nextStep = j;
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

  /// Keeps only the squares [root] is made of, and forgets every remembered
  /// future: what a long run piles up, freed, with the table rebuilt small.
  void keepOnly(Iterable<HashNode> roots) {
    _table = List<HashNode?>.filled(1 << 16, null);
    _count = 0;
    final seen = <HashNode>{};
    void keep(HashNode n) {
      if (n.level == 0 || !seen.add(n)) return;
      n
        .._next = null
        .._nextStep = -1;
      keep(n.nw!);
      keep(n.ne!);
      keep(n.sw!);
      keep(n.se!);
      if (_count * 2 >= _table.length) _grow();
      _insert(n);
    }

    for (final n in [...roots, ..._empty.skip(1), ..._leaves.cast<HashNode>()]) {
      keep(n);
    }
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

/// A pattern on an endless plane, run by [HashLife]: no edges to wrap, so it
/// can jump ahead 2^j generations at a time, and giant patterns (Paul
/// Rendell's 12,699 x 12,652-cell Turing machine) cost only as much memory
/// as they have distinct squares.
class HashPlane {
  HashPlane._(this.life, this._root, this._x, this._y) : _start = (_root, _x, _y);

  /// [cells] as (x, y) pairs; they keep those coordinates on the plane.
  factory HashPlane.fromCells(HashLife life, List<(int, int)> cells) {
    // With B0 an empty plane would fill at once: it has no finite state to hold.
    if (life.rule.birthFromNothing) throw ArgumentError('${life.rule.notation} brings empty space to life, which an endless plane can\'t hold.');
    if (cells.isEmpty) return HashPlane._(life, life.empty(3), 0, 0);
    var minX = cells.first.$1, minY = cells.first.$2, maxX = minX, maxY = minY;
    for (final (x, y) in cells) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    var level = 3;
    while ((1 << level) <= (maxX - minX > maxY - minY ? maxX - minX : maxY - minY)) {
      level++;
    }
    HashNode build(int level, int x0, int y0, List<(int, int)> part) {
      if (part.isEmpty) return life.empty(level);
      if (level == 0) return HashLife.on;
      final half = 1 << (level - 1);
      final nw = <(int, int)>[], ne = <(int, int)>[], sw = <(int, int)>[], se = <(int, int)>[];
      for (final c in part) {
        final east = c.$1 >= x0 + half, south = c.$2 >= y0 + half;
        (south ? (east ? se : sw) : (east ? ne : nw)).add(c);
      }
      return life.join(
        build(level - 1, x0, y0, nw),
        build(level - 1, x0 + half, y0, ne),
        build(level - 1, x0, y0 + half, sw),
        build(level - 1, x0 + half, y0 + half, se),
      );
    }

    return HashPlane._(life, build(level, minX, minY, cells), minX, minY);
  }

  final HashLife life;
  HashNode _root;

  /// Where it began, for [restart].
  final (HashNode, int, int) _start;

  /// Back to generation 0.
  void restart() {
    _root = _start.$1;
    _x = _start.$2;
    _y = _start.$3;
    generation = 0;
  }

  /// The plane coordinates of the root square's top-left cell.
  int _x, _y;

  int generation = 0;

  int get population => _root.population;

  /// The largest jump [advance] allows: 2^40 generations, a trillion, so the
  /// generation count stays exact on the web (53-bit integers).
  static const maxStep = 40;

  /// Moves on 2^[j] generations.
  void advance(int j) {
    assert(j >= 0 && j <= maxStep);
    // Keep the root small: drop empty borders.
    while (_root.level > 3 && _inCentreHalf(_root)) {
      final quarter = _root.size >> 2;
      _root = life.join(_root.nw!.se!, _root.ne!.sw!, _root.sw!.ne!, _root.se!.nw!);
      _x += quarter;
      _y += quarter;
    }
    // Room to grow: in the centre quarter of a root big enough for the jump,
    // nothing can reach past the centre half that [HashLife.advance] returns.
    while (_root.level < j + 2 || !_inCentreHalf(_root)) {
      _expand();
    }
    _expand();
    final quarter = _root.size >> 2;
    _root = life.advance(_root, j);
    _x += quarter;
    _y += quarter;
    generation += 1 << j;
    if (life.nodeCount > life.maxNodes) life.keepOnly([_root, _start.$1]);
  }

  /// Everything live is inside the centre half (its outer twelve sixteenths are empty).
  static bool _inCentreHalf(HashNode n) =>
      n.nw!.nw!.population +
          n.nw!.ne!.population +
          n.nw!.sw!.population +
          n.ne!.nw!.population +
          n.ne!.ne!.population +
          n.ne!.se!.population +
          n.sw!.nw!.population +
          n.sw!.sw!.population +
          n.sw!.se!.population +
          n.se!.ne!.population +
          n.se!.sw!.population +
          n.se!.se!.population ==
      0;

  /// Doubles the root, keeping it in the middle.
  void _expand() {
    final e = life.empty(_root.level - 1);
    final r = _root;
    _root = life.join(life.join(e, e, e, r.nw!), life.join(e, e, r.ne!, e), life.join(e, r.sw!, e, e), life.join(r.se!, e, e, e));
    final quarter = _root.size >> 2;
    _x -= quarter;
    _y -= quarter;
  }

  /// The smallest rectangle holding every live cell, or null when there are none.
  ({int x, int y, int width, int height})? get bounds {
    if (_root.population == 0) return null;
    int edge(HashNode n, int x0, int y0, bool horizontal, bool low) {
      if (n.level == 0) return horizontal ? x0 : y0;
      final half = n.size >> 1;
      final parts = [(n.nw!, x0, y0), (n.ne!, x0 + half, y0), (n.sw!, x0, y0 + half), (n.se!, x0 + half, y0 + half)];
      // The quarters nearest the wanted edge first.
      int key((HashNode, int, int) p) => (horizontal ? p.$2 : p.$3) * (low ? 1 : -1);
      parts.sort((a, b) => key(a).compareTo(key(b)));
      int? best;
      for (final (q, qx, qy) in parts) {
        if (q.population == 0) continue;
        final e = edge(q, qx, qy, horizontal, low);
        if (best == null || (low ? e < best : e > best)) best = e;
      }
      return best!;
    }

    final left = edge(_root, _x, _y, true, true), right = edge(_root, _x, _y, true, false);
    final top = edge(_root, _x, _y, false, true), bottom = edge(_root, _x, _y, false, false);
    return (x: left, y: top, width: right - left + 1, height: bottom - top + 1);
  }

  /// Every live cell, in plane coordinates. For tests and small patterns.
  List<(int, int)> liveCells() {
    final out = <(int, int)>[];
    void walk(HashNode n, int x0, int y0) {
      if (n.population == 0) return;
      if (n.level == 0) return out.add((x0, y0));
      final half = n.size >> 1;
      walk(n.nw!, x0, y0);
      walk(n.ne!, x0 + half, y0);
      walk(n.sw!, x0, y0 + half);
      walk(n.se!, x0 + half, y0 + half);
    }

    walk(_root, _x, _y);
    return out;
  }

  /// A [width] x [height] picture of the plane, one byte per pixel, whose
  /// top-left pixel is the cell at ([left], [top]) and where each pixel
  /// covers 2^[k] x 2^[k] cells. A pixel is 0 where they're all dead, and
  /// brighter the more of them live, so sparse machinery still shows when
  /// zoomed far out. Only squares on screen are visited.
  Uint8List render(int left, int top, int k, int width, int height) {
    final counts = Uint32List(width * height);
    final right = left + (width << k), bottom = top + (height << k);
    void walk(HashNode n, int x0, int y0) {
      final size = n.size;
      if (n.population == 0 || x0 >= right || y0 >= bottom || x0 + size <= left || y0 + size <= top) return;
      if (n.level <= k) {
        final px = (x0 - left) >> k, py = (y0 - top) >> k; // arithmetic shift: floors negatives too
        if (px >= 0 && py >= 0 && px < width && py < height) counts[py * width + px] += n.population;
        return;
      }
      final half = size >> 1;
      walk(n.nw!, x0, y0);
      walk(n.ne!, x0 + half, y0);
      walk(n.sw!, x0, y0 + half);
      walk(n.se!, x0 + half, y0 + half);
    }

    walk(_root, _x, _y);
    final out = Uint8List(width * height);
    if (k == 0) {
      for (var i = 0; i < out.length; i++) {
        if (counts[i] > 0) out[i] = 255;
      }
      return out;
    }
    final cellsPerPixel = (1 << k) * (1 << k);
    for (var i = 0; i < out.length; i++) {
      final c = counts[i];
      if (c == 0) continue;
      final density = c / cellsPerPixel;
      // Any life at all is clearly visible; crowds are brighter.
      out[i] = (110 + 145 * (density * 3 > 1 ? 1 : density * 3)).round();
    }
    return out;
  }
}
