import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/engine/cpu_engine.dart';
import 'package:life_with_ai/engine/gpu_engine.dart';
import 'package:life_with_ai/engine/life_engine.dart';
import 'package:life_with_ai/render/shaders.dart';

/// Work in flight when a board is disposed (a step waiting on the isolate, an
/// image still decoding) must finish quietly. CI caught this: a CPU step that
/// completed after dispose freed an already-freed image.
void main() {
  Grid board() => Grid(64, 48)..set(10, 10, true)..set(11, 10, true)..set(12, 10, true);

  for (final kind in EngineKind.values) {
    testWidgets('${kind.name}: a load or step that finishes after dispose is harmless', (tester) async {
      await tester.runAsync(() async {
        final shaders = await Shaders.load();
        LifeEngine make() => kind == EngineKind.cpu ? CpuEngine() : GpuEngine(shaders.lifeStep);

        // Work refused after dispose, and disposing twice, are both fine.
        final e = make();
        await e.load(board());
        e.dispose();
        await e.load(board());
        await e.step();
        e.dispose();
        expect(e.frame, isNull);

        // A load whose image decode is still running when dispose happens.
        final e1 = make();
        final loading = e1.load(board());
        e1.dispose();
        await Future.any([loading, Future<void>.delayed(const Duration(milliseconds: 300))]);
        expect(e1.frame, isNull);

        // The racy shape CI hit: dispose while a step is still in flight.
        for (var trial = 0; trial < 10; trial++) {
          final e2 = make();
          await e2.load(board());
          final pending = e2.step(1);
          await Future<void>.delayed(Duration(microseconds: trial * 300));
          e2.dispose();
          // A killed isolate never replies, so don't wait for ever.
          await Future.any([pending, Future<void>.delayed(const Duration(milliseconds: 300))]);
        }
      });
    });
  }

  testWidgets('a controller disposed mid-run stops cleanly', (tester) async {
    await tester.runAsync(() async {
      final c = LifeController(await Shaders.load());
      await c.init(engine: EngineKind.cpu);
      c.toggleRunning();
      final ticking = c.tick(0.0).then((_) => c.tick(0.5));
      c.dispose();
      await Future.any([ticking, Future<void>.delayed(const Duration(milliseconds: 300))]);
      await c.tick(1.0); // a tick after dispose does nothing
    });
  });
}
