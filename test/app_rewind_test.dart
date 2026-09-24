import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/engine/life_engine.dart';
import 'package:life_with_ai/render/shaders.dart';

/// Stepping back and rewinding reproduce the forward run exactly, on both
/// engines, across a checkpoint boundary.
void main() {
  Grid seed() {
    final g = Grid(BoardSize.medium.width, BoardSize.medium.height);
    patternLibrary['r_pentomino']!.stampOnto(g, 250, 180);
    patternLibrary['gosper_glider_gun']!.stampOnto(g, 20, 20);
    return g;
  }

  for (final kind in EngineKind.values) {
    testWidgets('${kind.name}: 70 steps forward, then back one at a time, matches the forward run', (tester) async {
      await tester.runAsync(() async {
        final c = LifeController(await Shaders.load());
        await c.init(engine: kind);
        await c.load(seed());
        expect(c.atBeginning, isTrue);
        expect(c.canStepBack, isFalse);

        final history = <int>[(await c.engine.snapshot()).stateHash];
        for (var i = 0; i < 70; i++) {
          await c.stepOnce();
          history.add((await c.engine.snapshot()).stateHash);
        }
        expect(c.generation, 70);
        expect(c.timeline!.snapshotCount, 2, reason: 'origin + generation 64');

        for (var gen = 69; gen >= 0; gen--) {
          await c.stepBack();
          expect(c.generation, gen);
          expect((await c.engine.snapshot()).stateHash, history[gen], reason: 'generation $gen');
        }
        expect(c.canStepBack, isFalse, reason: 'nothing before the beginning');
        await c.stepBack(); // a no-op, not an error
        expect(c.generation, 0);
        c.dispose();
      });
    });
  }

  testWidgets('back to the start keeps the name and play state; loading anew starts a new timeline', (tester) async {
    await tester.runAsync(() async {
      final c = LifeController(await Shaders.load());
      await c.init();
      await c.playSeed(seed(), title: 'Gun and pentomino');
      final start = (await c.engine.snapshot()).stateHash;
      for (var i = 0; i < 10; i++) {
        await c.stepOnce();
      }
      expect(c.canStepBack, isFalse, reason: 'stepping back waits for pause, like stepping forward');

      await c.rewindToStart();
      expect(c.generation, 0);
      expect((await c.engine.snapshot()).stateHash, start);
      expect(c.running, isTrue);
      expect(c.boardTitle, 'Gun and pentomino');

      await c.clear();
      expect(c.timeline!.origin.population, 0, reason: 'a new board is a new beginning');
      c.dispose();
    });
  });

  testWidgets('switching engines keeps the history', (tester) async {
    await tester.runAsync(() async {
      final c = LifeController(await Shaders.load());
      await c.init(engine: EngineKind.gpu);
      await c.load(seed());
      final start = (await c.engine.snapshot()).stateHash;
      for (var i = 0; i < 5; i++) {
        await c.stepOnce();
      }
      await c.switchEngine(EngineKind.cpu);
      await c.rewindToStart();
      expect((await c.engine.snapshot()).stateHash, start);
      c.dispose();
    });
  });
}
