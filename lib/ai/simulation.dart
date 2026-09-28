import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/grid.dart';
import 'census.dart';

/// Upper bound per simulate call: 1500 generations of a 1024x768 board is a
/// couple of seconds of CPU, which is as long as a tool call should block.
const maxSimulatedGenerations = 1500;

/// Input for [runSimulation]. A record of primitives so it can cross an
/// isolate boundary via `compute`.
typedef SimulationRequest = ({int width, int height, Uint8List cells, int generations, List<int> checkpoints, bool png});

/// What the agent learns from running a candidate seed forward.
class SimulationReport {
  SimulationReport({
    required this.generations,
    required this.fate,
    required this.populationSamples,
    required this.checkpoints,
    this.activity = const [],
    this.settledAt,
    this.census,
    this.png,
  });

  final int generations;

  /// e.g. "died out at generation 130", "oscillates with period 2 from generation 48",
  /// "still growing", "still active (chaotic)".
  final String fate;
  final List<(int gen, int pop)> populationSamples;
  final List<Checkpoint> checkpoints;

  /// (generation, cells that differ from [activityLag] generations earlier).
  /// Still lifes and period-1/2/3/6 oscillators come out as 0; anything
  /// moving or evolving doesn't.
  final List<(int gen, int changed)> activity;

  /// The sampled generation from which activity held steady (see [settledFrom]),
  /// or null if it was still evolving at the end.
  final int? settledAt;

  /// The objects on the final board.
  final Census? census;

  /// Board at the final generation as a PNG, when requested.
  final Uint8List? png;

  /// Compact, model-readable text. Kept small on purpose: this goes into the
  /// conversation on every refine turn.
  String toText() {
    final b = StringBuffer()
      ..writeln('Simulated $generations generations.')
      ..writeln('Fate: $fate')
      ..writeln('Population over time (gen:pop): ${populationSamples.map((s) => '${s.$1}:${s.$2}').join(' ')}');
    if (activity.isNotEmpty) {
      b
        ..writeln(
          'Activity (cells that differ from $activityLag generations earlier; still lifes and period-2/3 oscillators '
          'count 0, anything moving or evolving counts): ${activity.map((s) => '${s.$1}:${s.$2}').join(' ')}',
        )
        ..writeln(
          settledAt != null
              ? 'Settled: activity held steady from about generation $settledAt; what still counts is objects in motion '
                    'or longer-period oscillators.'
              : 'Not settled: still changing at generation $generations.',
        );
    }
    if (census != null) b.writeln('Final board: ${census!.toText()}.');
    for (final c in checkpoints) {
      b
        ..writeln()
        ..writeln(
          '--- generation ${c.generation}: population ${c.population}, '
          '${c.bounds == null ? 'empty' : 'bounding box x=${c.bounds!.x} y=${c.bounds!.y} w=${c.bounds!.width} h=${c.bounds!.height}'}, '
          'hotspots ${c.hotspots} ---',
        )
        ..write(c.ascii);
    }
    return b.toString();
  }
}

class Checkpoint {
  Checkpoint(this.generation, this.population, this.bounds, this.hotspots, this.ascii);

  final int generation;
  final int population;
  final ({int x, int y, int width, int height})? bounds;

  /// Number of 16x16-cell blocks with >= 25% live cells — these are what glow
  /// hottest in the renderer.
  final int hotspots;
  final String ascii;
}

int countHotspots(Grid g, {int block = 16, double threshold = 0.25}) {
  var n = 0;
  for (var by = 0; by < g.height; by += block) {
    for (var bx = 0; bx < g.width; bx += block) {
      var live = 0, total = 0;
      for (var y = by; y < by + block && y < g.height; y++) {
        for (var x = bx; x < bx + block && x < g.width; x++) {
          total++;
          live += g.cells[y * g.width + x];
        }
      }
      if (live / total >= threshold) n++;
    }
  }
  return n;
}

/// Activity compares each board with the one this many generations earlier:
/// 6 is a multiple of the periods of blinkers, toads, beacons and pulsars.
const activityLag = 6;

/// The first sampled generation from which activity held steady: what is left
/// is still lifes, short oscillators (which count 0) and objects in steady
/// motion (escaping gliders change the same number of cells every sample).
/// Null when the last few samples still vary, i.e. it is still evolving.
int? settledFrom(List<(int gen, int changed)> activity) {
  if (activity.length < 3) return null;
  int? from;
  var lo = activity.last.$2, hi = lo;
  for (var i = activity.length - 1; i >= 0; i--) {
    final c = activity[i].$2;
    final newLo = min(lo, c), newHi = max(hi, c);
    if (newHi - newLo > max(6, newHi * 0.1)) break;
    lo = newLo;
    hi = newHi;
    from = activity[i].$1;
  }
  // A steady tail of one or two samples could be chance.
  final steadySamples = activity.where((s) => from != null && s.$1 >= from).length;
  return steadySamples >= 3 ? from : null;
}

/// Pure function: runs the seed forward and classifies what happens.
SimulationReport runSimulation(SimulationRequest r) {
  final gens = r.generations.clamp(1, maxSimulatedGenerations);
  final wanted = {...r.checkpoints.where((c) => c >= 0 && c <= gens), gens};
  var a = Grid.fromCells(r.width, r.height, Uint8List.fromList(r.cells));
  var b = Grid(r.width, r.height);

  final seen = <int, int>{a.stateHash: 0}; // state hash -> first generation seen
  final samples = <(int, int)>[];
  final checkpoints = <Checkpoint>[];
  final sampleEvery = (gens / 12).ceil();
  String? fate;

  // Activity: sampled about 24 times, each against a copy taken activityLag generations before.
  final activityEvery = max(activityLag, (gens / 24).ceil());
  final activityAt = {for (var g = activityEvery; g <= gens; g += activityEvery) g, if (gens >= activityLag) gens};
  final earlier = <int, Uint8List>{}; // sample generation -> the board activityLag generations before it
  final activity = <(int, int)>[];
  void snapshot(int gen) {
    if (activityAt.contains(gen + activityLag)) earlier[gen + activityLag] = Uint8List.fromList(a.cells);
  }

  snapshot(0);

  void checkpoint(int gen) =>
      checkpoints.add(Checkpoint(gen, a.population, a.boundingBox, countHotspots(a), a.toAscii(maxCols: 64, maxRows: 24)));

  if (wanted.contains(0)) checkpoint(0);
  samples.add((0, a.population));

  for (var gen = 1; gen <= gens; gen++) {
    a.stepInto(b);
    final t = a;
    a = b;
    b = t;
    if (gen % sampleEvery == 0 || gen == gens) samples.add((gen, a.population));
    final before = earlier.remove(gen);
    if (before != null) {
      var changed = 0;
      for (var i = 0; i < before.length; i++) {
        if (before[i] != a.cells[i]) changed++;
      }
      activity.add((gen, changed));
    }
    snapshot(gen);
    if (wanted.contains(gen)) checkpoint(gen);
    if (fate != null) continue;
    final pop = a.population;
    if (pop == 0) {
      fate = 'died out at generation $gen';
      continue;
    }
    final h = a.stateHash;
    final first = seen[h];
    if (first != null) {
      final period = gen - first;
      fate = period == 1
          ? 'became a still life at generation $first (population $pop)'
          : 'settled into a period-$period oscillation from generation $first (population $pop)';
    } else {
      seen[h] = gen;
    }
  }

  if (fate == null) {
    double mean(Iterable<(int, int)> xs) => xs.map((s) => s.$2).reduce((x, y) => x + y) / xs.length;
    final third = (samples.length ~/ 3).clamp(1, samples.length);
    final early = mean(samples.take(third));
    final late = mean(samples.skip(samples.length - third));
    fate = late > early * 1.3
        ? 'still active and growing'
        : late < early * 0.7
        ? 'still active but shrinking'
        : 'still active (roughly stable population, not yet periodic — spaceships or chaos)';
  }

  checkpoints.sort((x, y) => x.generation.compareTo(y.generation));
  return SimulationReport(
    generations: gens,
    fate: fate,
    populationSamples: samples,
    checkpoints: checkpoints,
    activity: activity,
    settledAt: settledFrom(activity),
    census: takeCensus(a),
    png: r.png ? encodeBoardPng(a) : null,
  );
}

/// White-on-black PNG, one pixel per cell (scaled up for small boards so the
/// model has something legible). Roughly width*height/750 input tokens.
Uint8List encodeBoardPng(Grid g) {
  final scale = g.width < 400 ? 2 : 1;
  final image = img.Image(width: g.width * scale, height: g.height * scale, numChannels: 1);
  for (var y = 0; y < g.height; y++) {
    for (var x = 0; x < g.width; x++) {
      if (g.cells[y * g.width + x] == 0) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          image.setPixelR(x * scale + dx, y * scale + dy, 255);
        }
      }
    }
  }
  return img.encodePng(image);
}
