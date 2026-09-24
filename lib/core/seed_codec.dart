import 'grid.dart';

/// Compact, URL-safe text form of a seed, used for favorites and share links.
///
///     1_512x384_210_150_2o-bo-3o
///     │ │       │   │   └ run-length rows of the live cells' bounding box
///     │ │       │   └──── top of that box
///     │ │       └──────── left of that box
///     │ └──────────────── board size (placement depends on it: edges wrap)
///     └────────────────── format version
///
/// The body is standard Game of Life RLE (`b` dead, `o` alive, a count repeats
/// the next token) with `-` instead of `$` for "end of row" and no trailing
/// `!`, so every character is safe in a URL without escaping.
class SeedCodec {
  static const version = '1';

  /// Refuses absurd sizes from untrusted links before allocating anything.
  static const maxCells = 4096 * 4096;

  static String encode(Grid g) {
    final box = g.boundingBox;
    if (box == null) return '${version}_${g.width}x${g.height}_0_0_';
    final rows = <String>[];
    for (var y = box.y; y < box.y + box.height; y++) {
      final row = StringBuffer();
      var x = box.x;
      final end = box.x + box.width;
      // Trailing dead cells in a row carry no information; stop at the last live one.
      var last = end - 1;
      while (last >= x && !g.get(last, y)) {
        last--;
      }
      while (x <= last) {
        final alive = g.get(x, y);
        var run = 1;
        while (x + run <= last && g.get(x + run, y) == alive) {
          run++;
        }
        if (run > 1) row.write(run);
        row.write(alive ? 'o' : 'b');
        x += run;
      }
      rows.add(row.toString());
    }
    // Collapse runs of empty rows into a counted row break, e.g. "3-".
    final body = StringBuffer();
    var pendingBreaks = 0;
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) pendingBreaks++;
      if (rows[i].isEmpty && i < rows.length - 1) continue;
      if (pendingBreaks > 0) body.write(pendingBreaks > 1 ? '$pendingBreaks-' : '-');
      pendingBreaks = 0;
      body.write(rows[i]);
    }
    return '${version}_${g.width}x${g.height}_${box.x}_${box.y}_$body';
  }

  /// Throws [FormatException] for anything malformed: codes arrive from links
  /// anyone can edit.
  static Grid decode(String code) {
    final parts = code.trim().split('_');
    if (parts.length != 5) throw const FormatException('A seed code has 5 parts separated by "_".');
    if (parts[0] != version) throw FormatException('Unsupported seed format version "${parts[0]}".');
    final size = parts[1].split('x');
    final w = size.length == 2 ? int.tryParse(size[0]) : null;
    final h = size.length == 2 ? int.tryParse(size[1]) : null;
    if (w == null || h == null || w < 1 || h < 1 || w * h > maxCells) {
      throw FormatException('Bad board size "${parts[1]}".');
    }
    final ox = int.tryParse(parts[2]), oy = int.tryParse(parts[3]);
    if (ox == null || oy == null || ox < 0 || oy < 0 || ox >= w || oy >= h) {
      throw const FormatException('Bad seed position.');
    }

    final g = Grid(w, h);
    var x = 0, y = 0, run = 0;
    for (final ch in parts[4].split('')) {
      final digit = int.tryParse(ch);
      if (digit != null) {
        run = run * 10 + digit;
        if (run > w * h) throw const FormatException('Run length is larger than the board.');
        continue;
      }
      final n = run == 0 ? 1 : run;
      run = 0;
      switch (ch) {
        case 'b':
          x += n;
        case 'o':
          for (var i = 0; i < n; i++) {
            if (x + i >= w || y >= h) throw const FormatException('Seed runs off the board.');
            g.set(ox + x + i, oy + y, true);
          }
          x += n;
        case '-':
          y += n;
          x = 0;
        default:
          throw FormatException('Unexpected "$ch" in seed code.');
      }
      if (x > w || y >= h) throw const FormatException('Seed runs off the board.');
    }
    return g;
  }

  /// Like [decode] but returns null instead of throwing.
  static Grid? tryDecode(String code) {
    try {
      return decode(code);
    } on FormatException {
      return null;
    }
  }
}
