import 'grid.dart';

/// A named arrangement of live cells, parsed from standard RLE.
class Pattern {
  Pattern._(this.name, this.description, this.cells, this.width, this.height);

  factory Pattern.fromRle(String name, String description, String rle) {
    final cells = parseRle(rle);
    var w = 0, h = 0;
    for (final (x, y) in cells) {
      if (x + 1 > w) w = x + 1;
      if (y + 1 > h) h = y + 1;
    }
    return Pattern._(name, description, List.unmodifiable(cells), w, h);
  }

  final String name;
  final String description;
  final List<(int, int)> cells;
  final int width;
  final int height;

  /// Rotates clockwise by [quarterTurns] (after an optional horizontal flip),
  /// renormalized so the result's top-left is (0,0).
  Pattern transformed({int quarterTurns = 0, bool flipX = false}) {
    var pts = cells.map((c) => flipX ? (width - 1 - c.$1, c.$2) : c).toList();
    var w = width, h = height;
    for (var i = 0; i < quarterTurns % 4; i++) {
      // (x, y) -> (h-1-y, x) is a 90° clockwise turn in screen coordinates.
      pts = pts.map((c) => (h - 1 - c.$2, c.$1)).toList();
      final t = w;
      w = h;
      h = t;
    }
    return Pattern._(name, description, pts, w, h);
  }

  /// Stamps the pattern with its top-left at ([x], [y]); coordinates wrap.
  void stampOnto(Grid grid, int x, int y) {
    for (final (dx, dy) in cells) {
      grid.set(x + dx, y + dy, true);
    }
  }
}

/// Parses the body of an RLE file (header lines optional) into live-cell
/// coordinates. `b`/`.` is dead, any other letter is alive, `$` ends a row,
/// `!` ends the pattern, and a leading number repeats the next token.
List<(int, int)> parseRle(String rle) {
  final out = <(int, int)>[];
  var x = 0, y = 0, run = 0;
  for (final line in rle.split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || t.startsWith('x')) continue;
    for (final ch in t.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        run = run * 10 + (code - 48);
        continue;
      }
      final n = run == 0 ? 1 : run;
      run = 0;
      if (ch == '!') return out;
      if (ch == '\$') {
        y += n;
        x = 0;
      } else if (ch == 'b' || ch == '.') {
        x += n;
      } else if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
        for (var i = 0; i < n; i++) {
          out.add((x + i, y));
        }
        x += n;
      } else {
        throw FormatException('Unexpected "$ch" in RLE');
      }
    }
  }
  return out;
}

/// The library the AI composes from. Descriptions are written for the model:
/// they say what the pattern *does* over time, which is what it needs to plan.
final Map<String, Pattern> patternLibrary = {
  for (final p in [
    // Spaceships. The standard RLE ships face left; they are mirrored so every
    // spaceship in the library travels right (or down-right) at rotation 0.
    Pattern.fromRle(
      'glider',
      'Smallest spaceship. 3x3, moves 1 cell diagonally (down-right at rotation 0) every 4 generations.',
      'bob\$2bo\$3o!',
    ),
    Pattern.fromRle(
      'lwss',
      'Lightweight spaceship. Moves 2 cells right every 4 generations.',
      'bo2bo\$o4b\$o3bo\$4o!',
    ).transformed(flipX: true),
    Pattern.fromRle(
      'mwss',
      'Middleweight spaceship. Moves 2 cells right every 4 generations.',
      '3bo2b\$bo3bo\$o5b\$o4bo\$5o!',
    ).transformed(flipX: true),
    Pattern.fromRle(
      'hwss',
      'Heavyweight spaceship. Moves 2 cells right every 4 generations.',
      '3b2o2b\$bo4bo\$o6b\$o5bo\$6o!',
    ).transformed(flipX: true),
    // Oscillators (stay put, repeat).
    Pattern.fromRle('blinker', 'Period-2 oscillator, 3 cells.', '3o!'),
    Pattern.fromRle('toad', 'Period-2 oscillator.', 'b3o\$3o!'),
    Pattern.fromRle('beacon', 'Period-2 oscillator.', '2o2b\$2o2b\$2b2o\$2b2o!'),
    Pattern.fromRle(
      'pulsar',
      'Large, symmetric period-3 oscillator (13x13). Visually striking.',
      '2b3o3b3o2b2\$o4bobo4bo\$o4bobo4bo\$o4bobo4bo\$2b3o3b3o2b2\$2b3o3b3o2b\$o4bobo4bo\$o4bobo4bo\$o4bobo4bo2\$2b3o3b3o!',
    ),
    Pattern.fromRle('pentadecathlon', 'Period-15 oscillator (10x3).', '2bo4bo2b\$2ob4ob2o\$2bo4bo!'),
    // Still lifes (never change).
    Pattern.fromRle('block', 'Still life, 2x2. Stable; also eats gliders that hit it at the right phase.', '2o\$2o!'),
    Pattern.fromRle('beehive', 'Still life.', 'b2o\$o2bo\$b2o!'),
    Pattern.fromRle('loaf', 'Still life.', 'b2o\$o2bo\$bobo\$2bo!'),
    Pattern.fromRle('boat', 'Still life.', '2o\$obo\$bo!'),
    // Methuselahs (small seeds with long, chaotic lives — great for "explosions").
    Pattern.fromRle(
      'r_pentomino',
      'Methuselah: 5 cells that churn chaotically for ~1100 generations, throwing off gliders, before settling.',
      'b2o\$2o\$bo!',
    ),
    Pattern.fromRle(
      'acorn',
      'Methuselah: 7 cells that grow for ~5200 generations into a large debris field (~630 cells).',
      'bo5b\$3bo3b\$2o2b3o!',
    ),
    Pattern.fromRle('diehard', 'Methuselah that vanishes completely after exactly 130 generations.', '6bob\$2o6b\$bo3b3o!'),
    Pattern.fromRle('pi_heptomino', 'Methuselah: symmetric, evolves for ~170 generations into a symmetric debris field.', '3o\$obo\$obo!'),
    Pattern.fromRle('thunderbird', 'Methuselah: stabilizes after 243 generations, symmetric.', '3o2\$bo\$bo\$bo!'),
    // Guns and infinite growth.
    Pattern.fromRle(
      'gosper_glider_gun',
      'Emits a new glider every 30 generations, traveling down-right at rotation 0. 36x9.',
      '24bo11b\$22bobo11b\$12b2o6b2o12b2o\$11bo3bo4b2o12b2o\$2o8bo5bo3b2o14b\$2o8bo3bob2o4bobo11b\$10bo5bo7bo11b\$11bo3bo20b\$12b2o!',
    ),
    Pattern.fromRle(
      'infinite_growth',
      '5x5 seed whose population grows without bound (leaves a switch-engine trail).',
      '3obo\$o\$3b2o\$b2obo\$obobo!',
    ),
  ])
    p.name: p,
};
