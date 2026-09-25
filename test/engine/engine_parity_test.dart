import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/engine/cpu_engine.dart';
import 'package:life_with_ai/engine/gpu_engine.dart';
import 'package:life_with_ai/engine/life_engine.dart';
import 'package:life_with_ai/render/shaders.dart';

/// The GPU and HashLife engines are only trustworthy if they are bit-for-bit
/// identical to the CPU rules, including wrap-around at the edges.
void main() {
  Grid seeded(int w, int h, int seed) {
    final g = Grid(w, h);
    final rnd = Random(seed);
    for (var i = 0; i < g.cells.length; i++) {
      g.cells[i] = rnd.nextDouble() < 0.3 ? 1 : 0;
    }
    // Put a gun across the corner so wrapping is exercised every step.
    patternLibrary['gosper_glider_gun']!.stampOnto(g, w - 20, h - 4);
    return g;
  }

  for (final (w, h, gens) in [(64, 48, 1), (97, 61, 37), (256, 192, 150), (128, 96, 3 * detachEvery + 5)]) {
    testWidgets('GPU and HashLife match CPU on ${w}x$h after $gens generations', (tester) async {
      await tester.runAsync(() async {
        final shaders = await Shaders.load();
        final start = seeded(w, h, w * h);
        final cpu = CpuEngine(), gpu = GpuEngine(shaders.lifeStep), hash = CpuEngine(kind: EngineKind.hashlife);
        for (final e in [cpu, gpu, hash]) {
          await e.load(start);
        }
        for (var i = 0; i < gens; i++) {
          await cpu.step();
          await gpu.step();
          await hash.step();
        }
        final a = await cpu.snapshot(), b = await gpu.snapshot(), c = await hash.snapshot();
        expect(b.population, a.population);
        expect(b.stateHash, a.stateHash);
        expect((c.population, c.stateHash), (a.population, a.stateHash), reason: 'HashLife');
        expect(hash.population, a.population, reason: "the engine's own count");
        for (final e in [cpu, gpu, hash]) {
          e.dispose();
        }
      });
    });
  }
}
