import 'grid.dart';
import 'life_rule.dart';
import 'seed_codec.dart';

/// A pattern too big to read: [width] x [height] cells, from its header when
/// it has one, or as far as it got otherwise. The dialog says how that
/// compares with the boards here.
class RleTooBig extends FormatException {
  const RleTooBig(this.width, this.height) : super('This pattern is too big for any board here.');

  final int width;
  final int height;
}

/// A pattern read from RLE text: its live cells relative to its own top-left
/// corner, plus the name and comments from its `#N` and `#C` lines.
class RlePattern {
  RlePattern({
    required this.width,
    required this.height,
    required this.cells,
    this.name,
    this.comments = const [],
    this.torus,
    this.rule = LifeRule.conway,
  });

  final int width;
  final int height;
  final List<(int, int)> cells;
  final String? name;
  final List<String> comments;

  /// The board it was made for, from a rule like `B3/S23:T48,12`. Such a
  /// pattern relies on wrapping at exactly those edges.
  final ({int width, int height})? torus;

  /// The rule it runs by: Conway's unless its header names another
  /// birth/survival rule, such as HighLife's `B36/S23`.
  final LifeRule rule;

  /// A [boardWidth] x [boardHeight] board with this pattern in the middle.
  Grid centeredOn(int boardWidth, int boardHeight) {
    assert(width <= boardWidth && height <= boardHeight);
    final g = Grid(boardWidth, boardHeight);
    final left = (boardWidth - width) ~/ 2, top = (boardHeight - height) ~/ 2;
    for (final (x, y) in cells) {
      g.set(left + x, top + y, true);
    }
    return g;
  }
}

/// Standard Game of Life RLE, the format Golly, LifeViewer, the LifeWiki and
/// the ConwayLife forums use:
///
///     #N Glider
///     x = 3, y = 3, rule = B3/S23
///     bob$2bo$3o!
///
/// `b` is dead, `o` alive, `$` ends a row, `!` ends the pattern, and a count
/// repeats what follows. Share links use the same body with `-` for `$`
/// ([SeedCodec]), so this is a thin layer over it.
///
/// It also reads LifeHistory and LifeSuper, which the forums use a lot: they
/// are Conway's Life with extra states that mark cells up (`.` and `A`-`X`,
/// or `pA`-`yX` past 24). Odd states are alive and even ones dead, which is
/// how Golly turns them back into plain Life.
abstract final class Rle {
  /// Golly's line length for RLE bodies.
  static const lineLength = 70;

  /// Nothing larger fits any board, so nothing larger is worth reading.
  static const maxSide = 2048;
  static const maxLiveCells = 1024 * 768;

  /// Limits for [decode] with `unbounded`, for HashLife's endless plane: the
  /// Turing machine is 12,699 cells across with about 159,000 live ones.
  static const maxSideUnbounded = 1 << 24;
  static const maxLiveCellsUnbounded = 20000000;

  /// [grid]'s live cells as RLE, cropped to their bounding box, with an
  /// optional name (`#N`), origin (`#O`: who found it) and comments. [onBoard]
  /// also records the board, the way Golly does: its size as a torus in the
  /// rule (`B3/S23:T512,384`) and where the pattern sits (`#CXRLE Pos=x,y`),
  /// so the seed comes back exactly, wrap-around included.
  static String encode(
    Grid grid, {
    String? name,
    String? origin,
    List<String> comments = const [],
    bool onBoard = false,
    LifeRule rule = LifeRule.conway,
  }) {
    final box = grid.boundingBox;
    final out = StringBuffer();
    if (name != null && name.trim().isNotEmpty) out.writeln('#N ${_oneLine(name)}');
    if (origin != null && origin.trim().isNotEmpty) out.writeln('#O ${_oneLine(origin)}');
    for (final c in comments) {
      for (final line in c.split('\n')) {
        out.writeln('#C ${line.trim()}'.trimRight());
      }
    }
    if (onBoard) out.writeln('#CXRLE Pos=${box?.x ?? 0},${box?.y ?? 0}');
    out.writeln('x = ${box?.width ?? 0}, y = ${box?.height ?? 0}, rule = ${rule.notation}${onBoard ? ':T${grid.width},${grid.height}' : ''}');
    final body = '${SeedCodec.encode(grid).split('_').last.replaceAll('-', r'$')}!';
    out.write(_wrap(body));
    return out.toString();
  }

  /// Reads RLE text. Throws [FormatException] with a message fit to show
  /// people: this parses whatever was pasted.
  /// With [unbounded], only absurd sizes are refused (see
  /// [maxSideUnbounded]): the pattern is for HashLife's endless plane, not a board.
  static RlePattern decode(String text, {bool unbounded = false}) {
    final side = unbounded ? maxSideUnbounded : maxSide;
    final liveCap = unbounded ? maxLiveCellsUnbounded : maxLiveCells;
    String? name;
    final comments = <String>[];
    final body = StringBuffer();
    var sawHeader = false;
    ({bool multiState, ({int width, int height})? torus, LifeRule rule}) header = (multiState: false, torus: null, rule: LifeRule.conway);
    var declared = (width: 0, height: 0);
    // The header's size when it's bigger (it's the whole pattern), else what was read.
    RleTooBig tooBig(int w, int h) => RleTooBig(declared.width > w ? declared.width : w, declared.height > h ? declared.height : h);
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        final tag = line.length > 1 ? line[1] : '';
        final rest = line.length > 2 ? line.substring(2).trim() : '';
        if (tag == 'N' && rest.isNotEmpty) name ??= rest;
        if ((tag == 'C' || tag == 'c') && rest.isNotEmpty) comments.add(rest);
        continue;
      }
      if (!sawHeader && body.isEmpty && RegExp(r'^x\s*=').hasMatch(line)) {
        sawHeader = true;
        header = _readHeader(line);
        final size = RegExp(r'x\s*=\s*(\d+)\s*,\s*y\s*=\s*(\d+)').firstMatch(line);
        if (size != null) declared = (width: int.tryParse(size[1]!) ?? 0, height: int.tryParse(size[2]!) ?? 0);
        // Say so now, rather than after reading every row of a giant.
        if (declared.width > side || declared.height > side) throw RleTooBig(declared.width, declared.height);
        continue;
      }
      body.write(line);
    }
    final cells = <(int, int)>[];
    final chars = body.toString();
    var x = 0, y = 0, run = 0, width = 0, height = 0;
    RlePattern finish() => _finish(cells, width, height, name, comments, header.torus, header.rule);
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      final code = ch.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        run = run * 10 + (code - 0x30);
        if (run > side * side) throw tooBig(x + run, y + 1);
        continue;
      }
      if (ch == ' ' || ch == '\t') continue;
      final n = run == 0 ? 1 : run;
      run = 0;
      if (ch == r'$') {
        y += n;
        x = 0;
      } else if (ch == '!') {
        return finish();
      } else {
        final alive = switch (ch) {
          'b' || '.' => false,
          'o' => true,
          _ when header.multiState && _isState(code) => (code - 0x40).isOdd,
          // Past state 24: a prefix p-y, then A-X. State 24k + j is odd when j is (24k is even).
          _ when header.multiState && code >= 0x70 && code <= 0x79 && i + 1 < chars.length && _isState(chars.codeUnitAt(i + 1)) =>
            (chars.codeUnitAt(++i) - 0x40).isOdd,
          _ when RegExp(r'[A-Za-z]').hasMatch(ch) => throw FormatException(
            '"$ch" is a cell state Conway\'s Game of Life doesn\'t have. Only b (dead) and o (alive) work here.',
          ),
          _ => throw FormatException('"$ch" doesn\'t belong in RLE. A pattern is made of b, o, \$, ! and numbers.'),
        };
        if (alive) {
          if (cells.length + n > liveCap) throw tooBig(x + n, y + 1);
          for (var k = 0; k < n; k++) {
            cells.add((x + k, y));
          }
          if (x + n > width) width = x + n;
          if (y + 1 > height) height = y + 1;
        }
        x += n;
      }
      if (x > side || y > side) throw tooBig(x, y + 1);
    }
    return finish();
  }

  /// `A` to `X`: states 1 to 24 in multi-state RLE.
  static bool _isState(int code) => code >= 0x41 && code <= 0x58;

  /// Crops to the live cells, so leading blank rows or columns don't push
  /// the pattern off center.
  static RlePattern _finish(
    List<(int, int)> cells,
    int width,
    int height,
    String? name,
    List<String> comments,
    ({int width, int height})? torus,
    LifeRule rule,
  ) {
    if (cells.isEmpty) throw const FormatException('There are no live cells in this pattern.');
    var minX = width, minY = height;
    for (final (x, y) in cells) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
    }
    return RlePattern(
      width: width - minX,
      height: height - minY,
      cells: [for (final (x, y) in cells) (x - minX, y - minY)],
      name: name,
      comments: comments,
      torus: torus,
      rule: rule,
    );
  }

  /// Accepts Conway's rule however it's written (`B3/S23`, `b3/s23`, the old
  /// `23/3`, `Life`), its marked-up forms LifeHistory and LifeSuper, and a
  /// Golly topology after a colon: `:T48,12` is a 48x12 torus.
  static ({bool multiState, ({int width, int height})? torus, LifeRule rule}) _readHeader(String header) {
    // The rule comes last, and a topology's own comma belongs to it.
    final m = RegExp(r'rule\s*=\s*(.*)$', caseSensitive: false).firstMatch(header);
    if (m == null) return (multiState: false, torus: null, rule: LifeRule.conway); // no rule means Life
    final parts = m.group(1)!.replaceAll(' ', '').split(':');
    final rule = parts.first;
    const conway = {'life', 'conway'};
    const markedUp = {'lifehistory', 'lifesuper', 'b3/s23history', 'b3/s23super'};
    final lower = rule.toLowerCase();
    // Any birth/survival rule (Conway's included, however it's written); by name, Life and its marked-up forms.
    final parsed = conway.contains(lower) || markedUp.contains(lower) ? LifeRule.conway : LifeRule.parse(rule);
    if (parsed == null) {
      throw FormatException("This pattern uses the rule $rule. Life with AI runs birth/survival rules like B3/S23 (Conway's) or B36/S23 (HighLife).");
    }
    final t = parts.length > 1 ? RegExp(r'^T(\d+),(\d+)$', caseSensitive: false).firstMatch(parts[1]) : null;
    final w = t == null ? 0 : int.parse(t.group(1)!), h = t == null ? 0 : int.parse(t.group(2)!);
    final torus = w > 0 && h > 0 && w <= maxSide && h <= maxSide ? (width: w, height: h) : null;
    return (multiState: markedUp.contains(lower), torus: torus, rule: parsed);
  }

  /// Breaks [body] into lines of at most [lineLength], never inside a count.
  static String _wrap(String body) {
    final tokens = RegExp(r'\d*[^\d]').allMatches(body).map((m) => m[0]!);
    final out = StringBuffer();
    var line = 0;
    for (final t in tokens) {
      if (line + t.length > lineLength) {
        out.writeln();
        line = 0;
      }
      out.write(t);
      line += t.length;
    }
    return out.toString();
  }

  static String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
