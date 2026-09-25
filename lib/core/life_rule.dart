import 'dart:typed_data';

import 'grid.dart';

/// A Life-like rule: which neighbor counts bring a dead cell to life (birth)
/// and which keep a live one alive (survival). Conway's Game of Life is
/// B3/S23: born with exactly 3 live neighbors, surviving with 2 or 3.
///
/// Every engine takes the rule from here, so a rule behaves the same on the
/// CPU, the GPU and HashLife; the parity test proves it for a set of rules.
/// Free of Flutter imports, like [Grid].
final class LifeRule {
  const LifeRule._(this.birth, this.survival);

  /// From bit masks: bit n set means n neighbors (0-8).
  factory LifeRule(int birth, int survival) {
    if (birth < 0 || birth > 511 || survival < 0 || survival > 511) throw ArgumentError('Neighbor counts run from 0 to 8.');
    return LifeRule._(birth, survival);
  }

  /// B3/S23.
  static const conway = LifeRule._(1 << 3, 1 << 2 | 1 << 3);

  /// Neighbor counts that bring a dead cell to life, as bits 0-8.
  final int birth;

  /// Neighbor counts that keep a live cell alive, as bits 0-8.
  final int survival;

  bool get isConway => this == conway;

  /// How this rule is computed, decided here once. Engines take the
  /// processor's step (and, on the GPU, its shader) when a board is loaded,
  /// so no stepping loop or shader ever checks which rule it is running.
  RuleProcessor get processor => isConway ? RuleProcessor.conway : RuleProcessor.anyRule;

  /// The well-known rules, by name, for choosing one. Conway's first.
  static final named = <({String name, LifeRule rule, String about})>[
    (name: 'Conway', rule: conway, about: 'The Game of Life: born with 3, survives with 2 or 3'),
    (name: 'HighLife', rule: parse('B36/S23')!, about: 'Almost Life, with a pattern that copies itself'),
    (name: 'Day & Night', rule: parse('B3678/S34678')!, about: 'The same with every cell flipped: life inside solid regions too'),
    (name: 'Seeds', rule: parse('B2/S')!, about: 'Every cell dies each step; tiny patterns explode'),
    (name: 'Life without Death', rule: parse('B3/S012345678')!, about: 'Nothing ever dies: it grows ladders and vines'),
    (name: 'Maze', rule: parse('B3/S12345')!, about: 'Grows into maze-like corridors'),
    (name: 'Replicator', rule: parse('B1357/S1357')!, about: 'Every pattern copies itself, over and over'),
    (name: '2×2', rule: parse('B36/S125')!, about: 'Patterns built from 2×2 blocks'),
    (name: 'Morley', rule: parse('B368/S245')!, about: 'Rich in spaceships ("Move")'),
    (name: 'Anneal', rule: parse('B4678/S35678')!, about: 'Noise melts into smooth, shifting blobs'),
    (name: 'Diamoeba', rule: parse('B35678/S5678')!, about: 'Amoeba-like diamonds'),
  ];

  /// Its well-known name, or null.
  String? get name {
    for (final n in named) {
      if (n.rule == this) return n.name;
    }
    return null;
  }

  /// The name if it has one, else the notation: "HighLife", "B2/S3".
  String get label => name ?? notation;

  /// Born from nothing: with B0 a dead cell among dead neighbors comes alive,
  /// so an endless plane would fill at once. Boards cope; HashLife's plane can't.
  bool get birthFromNothing => birth & 1 != 0;

  /// Whether a cell is alive next generation, given whether it is now and
  /// how many of its 8 neighbors are.
  bool next(bool alive, int neighbors) => ((alive ? survival : birth) >> neighbors) & 1 == 1;

  /// [next] as a lookup table for hot loops: index `alive * 9 + neighbors`.
  Uint8List get table {
    final t = Uint8List(18);
    for (var n = 0; n <= 8; n++) {
      t[n] = (birth >> n) & 1;
      t[9 + n] = (survival >> n) & 1;
    }
    return t;
  }

  /// `B3/S23`, the notation RLE files and Golly use.
  String get notation {
    String digits(int mask) => [
      for (var n = 0; n <= 8; n++)
        if ((mask >> n) & 1 == 1) '$n',
    ].join();
    return 'B${digits(birth)}/S${digits(survival)}';
  }

  /// Reads `B3/S23` in any case, the older survival-first `23/3`, and
  /// `S23/B3`. Null for anything else (other families of rule, or names).
  static LifeRule? parse(String text) {
    final t = text.replaceAll(' ', '').toUpperCase();
    int? mask(String digits) {
      var m = 0;
      for (final c in digits.split('')) {
        if (c.isEmpty) continue;
        final n = int.tryParse(c);
        if (n == null || n > 8) return null;
        m |= 1 << n;
      }
      return m;
    }

    final bs = RegExp(r'^B([0-8]*)/S([0-8]*)$').firstMatch(t);
    final sb = RegExp(r'^S([0-8]*)/B([0-8]*)$').firstMatch(t);
    final old = RegExp(r'^([0-8]*)/([0-8]*)$').firstMatch(t);
    final (b, s) = bs != null
        ? (mask(bs[1]!), mask(bs[2]!))
        : sb != null
        ? (mask(sb[2]!), mask(sb[1]!))
        : old != null
        ? (mask(old[2]!), mask(old[1]!)) // survival first, then birth
        : (null, null);
    return b == null || s == null ? null : LifeRule._(b, s);
  }

  @override
  bool operator ==(Object other) => other is LifeRule && other.birth == birth && other.survival == survival;

  @override
  int get hashCode => Object.hash(birth, survival);

  @override
  String toString() => 'LifeRule($notation)';
}

/// One generation of [src] into [out] by [rule].
typedef StepFunction = Grid Function(Grid src, Grid out, LifeRule rule);

/// The ways a rule can be computed. Each carries its CPU step; the GPU engine
/// attaches its shader to the same values (see `gpu_engine.dart`).
enum RuleProcessor {
  /// Conway's B3/S23 by its own specialized code, the fastest there is.
  conway(Grid.stepConway),

  /// Any birth/survival rule, by looking up the next state in its table.
  anyRule(Grid.stepByTable);

  const RuleProcessor(this.step);

  final StepFunction step;
}
