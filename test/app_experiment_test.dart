import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/render/shaders.dart';

/// AI experiments replay on the live board: at a fitted rate, stopping on the
/// simulated generation, one after another, then handing over the final seed.
void main() {
  Grid gliderSeed() {
    final g = Grid(BoardSize.medium.width, BoardSize.medium.height);
    patternLibrary['glider']!.stampOnto(g, 10, 10);
    return g;
  }

  Future<LifeController> controller() async {
    final c = LifeController(await Shaders.load());
    await c.init();
    return c;
  }

  // Drives the controller's clock at 60 Hz.
  var clock = 0.0;
  Future<void> run(LifeController c, double seconds) async {
    for (var i = 0; i < (seconds * 60).round(); i++) {
      clock += 1 / 60;
      await c.tick(clock);
    }
  }

  testWidgets('an experiment plays at its fitted rate and stops on its last generation', (tester) async {
    await tester.runAsync(() async {
      final c = await controller();
      await c.tick(clock);
      await c.playExperiment(Experiment(number: 1, seed: gliderSeed(), generations: 30));
      expect(c.running, isTrue);
      expect(c.generation, 0);

      await run(c, 1); // 30 generations fit in 8s -> clamped up to 15/s
      expect(c.generation, inInclusiveRange(14, 16));

      await run(c, 3);
      expect(c.generation, 30, reason: 'stops exactly where Claude simulated to');
      expect(c.running, isFalse);
      expect(c.experimentFinished, isTrue);
      c.dispose();
    });
  });

  testWidgets('a long experiment is fast-forwarded to fit about 8 seconds', (tester) async {
    await tester.runAsync(() async {
      final c = await controller();
      expect(Experiment(number: 1, seed: gliderSeed(), generations: 800).rate, 100);
      expect(Experiment(number: 1, seed: gliderSeed(), generations: 1500).rate, closeTo(187.5, 1e-9));
      c.dispose();
    });
  });

  testWidgets('queued experiments play in order, then the final seed is handed over', (tester) async {
    await tester.runAsync(() async {
      final c = await controller();
      await c.tick(clock);
      await c.playExperiment(Experiment(number: 1, seed: gliderSeed(), generations: 10));
      await c.playExperiment(Experiment(number: 2, seed: gliderSeed(), generations: 10));
      final finalSeed = Grid(c.width, c.height);
      patternLibrary['block']!.stampOnto(finalSeed, 50, 50);
      await c.handOff(finalSeed);

      expect(c.experiment!.number, 1);
      await run(c, 2); // 10 gens at 15/s, plus the hold
      expect(c.experiment?.number, 2);
      await run(c, 2);
      expect(c.experiment, isNull, reason: 'the final seed replaced the replays');
      expect(c.running, isTrue);
      expect((await c.engine.snapshot()).population, greaterThanOrEqualTo(4));
      c.dispose();
    });
  });

  testWidgets('editing the seed cancels the replay', (tester) async {
    await tester.runAsync(() async {
      final c = await controller();
      await c.playExperiment(Experiment(number: 1, seed: gliderSeed(), generations: 500));
      await c.playExperiment(Experiment(number: 2, seed: gliderSeed(), generations: 500));
      await c.load(gliderSeed());
      expect(c.experiment, isNull);
      c.dispose();
    });
  });
}
