import '../core/grid.dart';
import '../core/patterns.dart';

/// What is left on a board: its separate objects, the common ones by name.
///
/// Objects are clusters of live cells within [_reach] of each other (clusters
/// that wrap across a board edge count once). A cluster is named when it matches a known object in
/// any phase and orientation; the rest are counted as unidentified. Objects
/// that come within [_reach] of each other merge into one unidentified cluster.
class Census {
  Census(this.moving, this.resting, this.other, this.largestOther);

  /// Spaceships by name, e.g. {'glider': 3}.
  final Map<String, int> moving;

  /// Still lifes and oscillators by name.
  final Map<String, int> resting;

  /// Clusters that matched nothing known, and the size of the biggest.
  final int other, largestOther;

  int get objects => moving.values.fold<int>(0, (a, b) => a + b) + resting.values.fold<int>(0, (a, b) => a + b) + other;

  String toText() {
    if (objects == 0) return 'empty';
    String list(Map<String, int> m) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key} ×${e.value}').join(', ');
    return [
      if (moving.isNotEmpty) 'moving: ${list(moving)}',
      if (resting.isNotEmpty) 'still or oscillating: ${list(resting)}',
      if (other > 0) 'unidentified clusters: $other (largest $largestOther cells)',
    ].join('; ');
  }
}

/// Cells this close (in both directions) belong to the same object: a
/// spaceship's cells aren't always touching (one of the LWSS's sits two away
/// from the rest in some phases), so plain 8-connection would break it apart.
const _reach = 2;

/// Clusters bigger than this are never a known object; they are counted as unidentified unexamined.
const _maxKnownCells = 40;

Census takeCensus(Grid g) {
  final w = g.width, h = g.height;
  final seen = List<bool>.filled(w * h, false);
  final moving = <String, int>{}, resting = <String, int>{};
  var other = 0, largest = 0;
  for (var start = 0; start < w * h; start++) {
    if (g.cells[start] == 0 || seen[start]) continue;
    // Flood fill in unwrapped coordinates, so a cluster across an edge stays in one piece.
    final cells = <(int, int)>[];
    final queue = <(int, int)>[(start % w, start ~/ w)];
    seen[start] = true;
    while (queue.isNotEmpty) {
      final (x, y) = queue.removeLast();
      cells.add((x, y));
      for (var dy = -_reach; dy <= _reach; dy++) {
        for (var dx = -_reach; dx <= _reach; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          final i = (ny % h) * w + (nx % w);
          if (g.cells[i] == 0 || seen[i]) continue;
          seen[i] = true;
          queue.add((nx, ny));
        }
      }
    }
    final name = cells.length <= _maxKnownCells ? _known[_key(cells)] : null;
    if (name == null) {
      other++;
      if (cells.length > largest) largest = cells.length;
    } else if (_spaceships.contains(name)) {
      moving[name] = (moving[name] ?? 0) + 1;
    } else {
      resting[name] = (resting[name] ?? 0) + 1;
    }
  }
  return Census(moving, resting, other, largest);
}

const _spaceships = {'glider', 'LWSS', 'MWSS', 'HWSS'};

/// A cluster's shape, the same whatever its position.
String _key(List<(int, int)> cells) {
  var minX = cells.first.$1, minY = cells.first.$2;
  for (final (x, y) in cells) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
  }
  final shifted = [for (final (x, y) in cells) (x - minX, y - minY)]
    ..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
  return shifted.map((c) => '${c.$1},${c.$2}').join(' ');
}

/// Every phase of every known object, in all eight orientations, keyed by shape.
final Map<String, String> _known = () {
  final objects = {
    'glider': patternLibrary['glider']!,
    'LWSS': patternLibrary['lwss']!,
    'MWSS': patternLibrary['mwss']!,
    'HWSS': patternLibrary['hwss']!,
    'blinker': patternLibrary['blinker']!,
    'toad': patternLibrary['toad']!,
    'beacon': patternLibrary['beacon']!,
    'pentadecathlon': patternLibrary['pentadecathlon']!,
    'block': patternLibrary['block']!,
    'beehive': patternLibrary['beehive']!,
    'loaf': patternLibrary['loaf']!,
    'boat': patternLibrary['boat']!,
    // Common leftovers the library doesn't offer for placing.
    'tub': Pattern.fromRle('tub', '', 'bo\$obo\$bo!'),
    'ship': Pattern.fromRle('ship', '', '2o\$obo\$b2o!'),
    'pond': Pattern.fromRle('pond', '', 'b2o\$o2bo\$o2bo\$b2o!'),
  };
  final known = <String, String>{};
  for (final MapEntry(key: name, value: pattern) in objects.entries) {
    // Run it in open space for 30 generations: every period here divides that or is shorter.
    const margin = 20;
    var grid = Grid(pattern.width + 2 * margin, pattern.height + 2 * margin);
    pattern.stampOnto(grid, margin, margin);
    var next = Grid(grid.width, grid.height);
    for (var gen = 0; gen < 30; gen++) {
      final live = [
        for (var i = 0; i < grid.cells.length; i++)
          if (grid.cells[i] != 0) (i % grid.width, i ~/ grid.width),
      ];
      // A phase in pieces can't be matched as one cluster; skip it.
      if (_connected(live)) {
        for (var turns = 0; turns < 4; turns++) {
          for (final flip in [false, true]) {
            final t = [
              for (final (x, y) in live)
                switch (turns) {
                  0 => (flip ? -x : x, y),
                  1 => (-y, flip ? -x : x),
                  2 => (flip ? x : -x, -y),
                  _ => (y, flip ? x : -x),
                },
            ];
            known.putIfAbsent(_key(t), () => name);
          }
        }
      }
      grid.stepInto(next);
      (grid, next) = (next, grid);
    }
  }
  return known;
}();

bool _connected(List<(int, int)> cells) {
  if (cells.isEmpty) return false;
  final set = cells.toSet();
  final reached = {cells.first};
  final queue = [cells.first];
  while (queue.isNotEmpty) {
    final (x, y) = queue.removeLast();
    for (var dy = -_reach; dy <= _reach; dy++) {
      for (var dx = -_reach; dx <= _reach; dx++) {
        final n = (x + dx, y + dy);
        if (set.contains(n) && reached.add(n)) queue.add(n);
      }
    }
  }
  return reached.length == cells.length;
}
