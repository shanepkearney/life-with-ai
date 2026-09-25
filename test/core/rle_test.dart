import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/core/rle.dart';

/// Straight from the LifeWiki, comments and all.
const gosperGun = '''#N Gosper glider gun
#O Bill Gosper
#C A true period 30 glider gun.
#C The first known gun and the first known finite pattern with unbounded growth.
#C www.conwaylife.com/wiki/index.php?title=Gosper_glider_gun
x = 36, y = 9, rule = B3/S23
24bo11b\$22bobo11b\$12b2o6b2o12b2o\$11bo3bo4b2o12b2o\$2o8bo5bo3b2o14b\$2o8b
o3bob2o4bobo11b\$10bo5bo7bo11b\$11bo3bo20b\$12b2o22b!''';

/// Real posts from the ConwayLife forums, as their authors pasted them, with
/// counts from an independent parser. Each is a quirk RLE out there has.
final forumSamples = <({String what, String source, String rle, int cells, int width, int height})>[
  (
    what: 'Golly XRLE position comment',
    source: 'MikeP, https://conwaylife.com/forums/viewtopic.php?p=107208#p107208',
    rle: '''#CXRLE Pos=0,0 Gen=0
x = 19, y = 16, rule = B3/S23
2b2o\$b4o\$2ob2o9bo\$b2o11bo\$7bobo4b2o2bo\$6b2o2bo7bo\$7bobo4b2o2bo\$b2o10b
2obo\$2ob2o10bo\$b4o7b2obo\$2b2o8b2obo\$3bo9b2o\$bo3bo\$o5bob2o\$o5b2o\$6o!''',
    cells: 68,
    width: 19,
    height: 16,
  ),
  (
    what: 'LifeViewer script and custom #C tags',
    source: '8than888, https://conwaylife.com/forums/viewtopic.php?p=234957#p234957',
    rle: '''#C [[ GRID MAXGRIDSIZE 14 THEME Catagolue ]]
#CSYNTH xs8_33zy5cc costs 3 gliders (pseudo).
#CLL state-numbering golly
x = 13, y = 11, rule = B3/S23
o\$b2o\$2o3\$2b2o\$3b2o\$2bo\$10b3o\$10bo\$11bo!''',
    cells: 15,
    width: 13,
    height: 11,
  ),
  (
    what: 'LifeHistory: marked-up Life, odd states alive',
    source: 'I6_I6, https://conwaylife.com/forums/viewtopic.php?p=232318#p232318',
    rle: '''#C [[ THEME Golly ]]
x = 27, y = 15, rule = LifeHistory
8.A\$A6.A.A\$3A4.BA2B.B2D\$3.A4.2B.2B2DB\$2.2A2.3B.6B2.3B\$2.20B\$4.19B\$4.2B
C10BD4B\$4.2B2C10BD4B\$4.B2C11B2D3B\$4.13B2D4B\$5.12BD3B.B2A\$6.13B3.BA.A\$
6.3B.B3.B10.A\$25.2A!''',
    cells: 23,
    width: 27,
    height: 15,
  ),
  (
    what: 'LifeSuper: more marker states, still odd alive',
    source: 'toroidalet, https://conwaylife.com/forums/viewtopic.php?p=163875#p163875',
    rle: '''x = 89, y = 41, rule = LifeSuper
58.M\$58.M.M\$58.2M5\$58.M\$56.2M\$57.2M11\$8.M29.M39.M\$8.M.M27.M.M37.M.M\$
8.2M28.2M38.2M5\$8.M29.M39.M\$6.2M28.2M38.2M\$7.2M28.2M38.2M\$2M28.2M38.
2M\$2M28.2M38.2M2\$10.3U28.2U38.2U\$11.3U26.U2.U36.U2.U\$41.U2.U36.U2.U\$
42.2U38.2U\$46.2U39.2U\$45.U2.U37.U.U\$44.U2.U37.U.U\$45.2U38.2U!''',
    cells: 90,
    width: 89,
    height: 41,
  ),
  (
    what: 'a torus the pattern depends on',
    source: 'Wngks Life, https://conwaylife.com/forums/viewtopic.php?p=235308#p235308',
    rle: '''x = 42, y = 4, rule = B3/S23:T48,12
15b3o21b3o\$3o12bobo6b3o12bobo\$obo12b3o6bobo12b3o\$3o21b3o!''',
    cells: 32,
    width: 42,
    height: 4,
  ),
];

/// Another rule, with a LifeViewer script after the "!". Refused, politely.
const otherRuleSample = '''x=0,y=0,rule=B34q/S23-k
14b3o\$13bo3bo\$13b2ob2o9\$15bo\$15bo\$b2o12bo12b2o\$obo25bobo\$o10b3o3b3o10b
o\$obo25bobo\$b2o12bo12b2o\$15bo\$15bo9\$13b2ob2o\$13bo3bo\$14b3o!
[[ LOOP 200 THEME POISON AUTOSTART T 0 PAUSE 0.3 ]]''';

Set<(int, int)> liveCells(Grid g) {
  final box = g.boundingBox!;
  return {
    for (var y = 0; y < g.height; y++)
      for (var x = 0; x < g.width; x++)
        if (g.get(x, y)) (x - box.x, y - box.y),
  };
}

/// Plain set equality: the matcher's deep compare is quadratic on big sets.
void expectSameCells(Iterable<(int, int)> actual, Set<(int, int)> expected, {String? reason}) {
  final a = actual.toSet();
  expect(a.length == expected.length && a.containsAll(expected), isTrue, reason: reason);
}

void main() {
  test('a glider exports as standard RLE, with its name and comments', () {
    final g = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(g, 210, 150);
    expect(
      Rle.encode(g, name: 'Glider', comments: ['Generation 0.']),
      '#N Glider\n#C Generation 0.\nx = 3, y = 3, rule = B3/S23\nbo\$2bo\$3o!',
      reason: 'trailing dead cells are dropped, as Golly does',
    );
  });

  test("an empty board exports a header and an end, and nothing to load", () {
    final text = Rle.encode(Grid(64, 48));
    expect(text, 'x = 0, y = 0, rule = B3/S23\n!');
    expect(() => Rle.decode(text), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('no live cells'))));
  });

  test('reads the LifeWiki Gosper glider gun, name and comments included', () {
    final p = Rle.decode(gosperGun);
    expect((p.width, p.height), (36, 9));
    expect(p.cells, hasLength(36));
    expect(p.name, 'Gosper glider gun');
    expect(p.comments, hasLength(3));
    expect(p.comments.first, 'A true period 30 glider gun.');
  });

  test('random soups survive a round trip through RLE', () {
    final rnd = Random(11);
    for (var trial = 0; trial < 40; trial++) {
      final g = Grid(40 + rnd.nextInt(90), 30 + rnd.nextInt(60));
      for (var i = 0; i < g.cells.length; i++) {
        if (rnd.nextDouble() < [0.03, 0.3, 0.7][trial % 3]) g.cells[i] = 1;
      }
      g.set(0, 0, true);
      final p = Rle.decode(Rle.encode(g, name: 'soup $trial'));
      expectSameCells(p.cells, liveCells(g), reason: 'trial $trial');
      expect(p.name, 'soup $trial');
    }
  });

  test('lines are wrapped at 70 characters without splitting a count', () {
    final g = Grid(300, 4);
    for (var x = 0; x < 300; x += 2) {
      g.set(x, 0, true);
    }
    for (var x = 0; x < 300; x += 7) {
      g.set(x, 3, true);
    }
    final lines = Rle.encode(g).split('\n').skip(1).toList();
    expect(lines.length, greaterThan(1));
    for (final line in lines) {
      expect(line.length, lessThanOrEqualTo(Rle.lineLength));
    }
    expectSameCells(Rle.decode(Rle.encode(g)).cells, liveCells(g));
  });

  test("Conway's rule is accepted however it's written", () {
    for (final header in [
      'x = 3, y = 3, rule = B3/S23',
      'x = 3, y = 3, rule = b3/s23',
      'x = 3, y = 3, rule = 23/3',
      'x = 3, y = 3, rule = Life',
      'x = 3, y = 3, rule = B3/S23:T100,100',
      'x = 3, y = 3',
      'x=3,y=3,rule=B3/S23',
    ]) {
      expect(Rle.decode('$header\nbob\$2bo\$3o!').cells, hasLength(5), reason: header);
    }
    expect(Rle.decode('bob\$2bo\$3o!').cells, hasLength(5), reason: 'a bare body is fine');
  });

  test('other rules and multi-state patterns are refused with a reason', () {
    expect(
      () => Rle.decode('x = 3, y = 3, rule = B34twz/S23\nbob\$2bo\$3o!'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', allOf(contains('B34twz/S23'), contains('B3/S23')))),
    );
    expect(() => Rle.decode('x = 3, y = 1, rule = Generations\n3A!'), throwsA(isA<FormatException>()));
    expect(() => Rle.decode('x = 3, y = 1\n2oA!'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('"A"'))));
    expect(() => Rle.decode('bo?o!'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('"?"'))));
  });

  test('forgiving about layout: no "!", spaces, Windows line endings, blank lines, leading blanks', () {
    expect(Rle.decode('#N Blinker\r\nx = 3, y = 1\r\n\r\n3o').name, 'Blinker');
    expect(Rle.decode('b o b \$ 2b o\n\$3o').cells, hasLength(5));
    final p = Rle.decode('2\$3b3o!');
    expect((p.width, p.height), (3, 1), reason: 'cropped to its live cells, so it centers properly');
    expect(p.cells.toSet(), {(0, 0), (1, 0), (2, 0)});
  });

  test('absurd patterns are refused before they eat memory', () {
    for (final huge in ['3000o!', '5000\$o!', '99999999999999o!', '${'2048o\$' * 400}!']) {
      expect(() => Rle.decode(huge), throwsFormatException, reason: huge.length > 12 ? huge.substring(0, 12) : huge);
    }
  });

  test("a giant is refused by its header's size, before its rows are read", () {
    // Paul Rendell's Universal Turing Machine (rendell-attic.org), header and first row.
    expect(
      () => Rle.decode('x = 12699, y = 12652, rule = b3/s23\n144b2o\$145bo\$145bobo\$146b2o3\$151b2o!'),
      throwsA(isA<RleTooBig>().having((e) => (e.width, e.height), 'size', (12699, 12652))),
    );
    expect(
      () => Rle.decode('3000o!'),
      throwsA(isA<RleTooBig>().having((e) => e.width, 'width', greaterThan(Rle.maxSide))),
      reason: 'no header: as far as it got',
    );
  });

  test('a pattern is centered on the board', () {
    final g = Rle.decode('3o!').centeredOn(11, 5);
    expect(liveCells(g), {(0, 0), (1, 0), (2, 0)});
    expect(g.boundingBox, (x: 4, y: 2, width: 3, height: 1));
  });

  group('real patterns from the ConwayLife forums', () {
    for (final f in forumSamples) {
      test(f.what, () {
        final p = Rle.decode(f.rle);
        expect((p.cells.length, p.width, p.height), (f.cells, f.width, f.height), reason: f.source);
      });
    }

    test('the torus size is kept, so the pattern can play on the board it was made for', () {
      expect(Rle.decode(forumSamples.last.rle).torus, (width: 48, height: 12));
      expect(Rle.decode(gosperGun).torus, isNull);
    });

    test('another rule is refused by name, script lines and all', () {
      expect(() => Rle.decode(otherRuleSample), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('B34q/S23-k'))));
    });

    test('other birth/survival rules are read, and written back', () {
    final p = Rle.decode('#N Replicator\nx = 5, y = 5, rule = B36/S23\n2b3o\$bo2bo\$o3bo\$o2bo\$3o!');
    expect(p.rule.notation, 'B36/S23');
    expect(p.rule.name, 'HighLife');
    expect(Rle.decode('x = 3, y = 1, rule = S23/B36\n3o!').rule.name, 'HighLife', reason: 'survival first, too');
    final g = p.centeredOn(20, 20);
    expect(Rle.encode(g, rule: p.rule), contains('rule = B36/S23'));
    expect(Rle.decode(Rle.encode(g, rule: p.rule)).rule, p.rule);
    expect(Rle.decode('x = 3, y = 1, rule = LifeHistory\n3A!').rule.isConway, isTrue);
  });

  test('marker states are only letters in LifeHistory or LifeSuper, never in plain Life', () {
      expect(() => Rle.decode('x = 3, y = 1, rule = B3/S23\n3A!'), throwsFormatException);
      expect(Rle.decode('x = 3, y = 1, rule = LifeHistory\n3A!').cells, hasLength(3));
      expect(Rle.decode('x = 2, y = 1, rule = LifeSuper\npApB!').cells, hasLength(1), reason: 'state 25 is alive, 26 is not');
    });
  });

  group('BoardSize.holding', () {
    test('keeps the current board when the pattern fits', () {
      expect(BoardSize.holding(36, 9, current: BoardSize.small), BoardSize.small);
      final fit = BoardSize.fitScreen(1512, 982);
      expect(BoardSize.holding(700, 400, current: fit), fit);
    });

    test('otherwise takes the smallest preset that holds it', () {
      expect(BoardSize.holding(300, 100, current: BoardSize.small), BoardSize.medium);
      expect(BoardSize.holding(200, 100, current: BoardSize.portrait), BoardSize.small);
      expect(BoardSize.holding(600, 500, current: BoardSize.small), BoardSize.large);
    });

    test('and says so when nothing does', () {
      expect(BoardSize.holding(1100, 10, current: BoardSize.medium), isNull);
    });
  });
}
