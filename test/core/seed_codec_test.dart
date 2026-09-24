import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/core/seed_codec.dart';

void main() {
  Grid roundTrip(Grid g) => SeedCodec.decode(SeedCodec.encode(g));

  test('a glider encodes to a short, URL-safe code and back', () {
    final g = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(g, 210, 150);
    final code = SeedCodec.encode(g);
    expect(code, '1_512x384_210_150_bo-2bo-3o');
    expect(Uri.encodeQueryComponent(code), code, reason: 'no characters need escaping');
    expect(roundTrip(g).stateHash, g.stateHash);
  });

  test('every library pattern round-trips at every rotation', () {
    for (final p in patternLibrary.values) {
      for (var turns = 0; turns < 4; turns++) {
        final g = Grid(128, 96);
        p.transformed(quarterTurns: turns, flipX: turns.isOdd).stampOnto(g, 40, 30);
        expect(roundTrip(g).stateHash, g.stateHash, reason: '${p.name} x$turns');
      }
    }
  });

  test('random soups with blank rows and edge cells round-trip', () {
    final rnd = Random(7);
    for (var trial = 0; trial < 50; trial++) {
      final g = Grid(64 + rnd.nextInt(64), 48 + rnd.nextInt(48));
      final density = [0.02, 0.2, 0.6][trial % 3];
      for (var i = 0; i < g.cells.length; i++) {
        if (rnd.nextDouble() < density) g.cells[i] = 1;
      }
      // Force cells on all four edges, where off-by-one bugs live.
      g.set(0, 0, true);
      g.set(g.width - 1, g.height - 1, true);
      expect(roundTrip(g).stateHash, g.stateHash, reason: 'trial $trial');
    }
  });

  test('an empty board round-trips', () {
    final g = Grid(10, 8);
    expect(SeedCodec.encode(g), '1_10x8_0_0_');
    expect(roundTrip(g).population, 0);
  });

  test('two cells far apart use counted row breaks', () {
    final g = Grid(100, 100)
      ..set(10, 10, true)
      ..set(10, 90, true);
    expect(SeedCodec.encode(g), '1_100x100_10_10_o80-o');
    expect(roundTrip(g).stateHash, g.stateHash);
  });

  test('malformed or hostile codes are rejected, never crash', () {
    for (final bad in [
      '',
      'garbage',
      '2_512x384_0_0_o', // unknown version
      '1_512_0_0_o', // no height
      '1_0x10_0_0_o', // zero size
      '1_99999x99999_0_0_o', // absurd size
      '1_10x10_-1_0_o', // negative offset
      '1_10x10_10_0_o', // offset outside board
      '1_10x10_0_0_11o', // runs off the row
      '1_10x10_0_0_20-o', // runs off the bottom
      '1_10x10_0_0_o\$o', // RLE "\$" is not our row break
      '1_10x10_0_0_999999999999o', // enormous run length
    ]) {
      expect(SeedCodec.tryDecode(bad), isNull, reason: bad);
    }
  });
}
