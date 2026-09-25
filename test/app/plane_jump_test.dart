import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/giant_mode.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/rle.dart';
import 'package:life_with_ai/engine/giant_runner.dart';
import 'package:life_with_ai/render/shaders.dart';

void main() {
  testWidgets('on the endless plane, a pattern a board could hold starts at 1x; a true giant jumps', (tester) async {
    await tester.runAsync(() async {
      final life = LifeController(await Shaders.load())..newGiantRunner = GiantRunner.inline;
      await life.init();
      await life.openGiant(Rle.decode('#N Acorn\nx = 7, y = 3, rule = B3/S23\nbo\$3bo\$2o2b3o!'));
      expect(life.giant!.jump, 0, reason: 'Acorn plays at 1x, as on a board');
      await life.openGiant(Rle.decode('x = 5000, y = 1, rule = B3/S23\no4998bo!', unbounded: true));
      expect(life.giant!.jump, GiantMode.giantJump, reason: 'too big for any board: it starts at a thousand');
      life.dispose();
    });
  });

  testWidgets('below ×1 the plane steps at a paced rate: at 1/s, two seconds are two generations', (tester) async {
    await tester.runAsync(() async {
      final life = LifeController(await Shaders.load())..newGiantRunner = GiantRunner.inline;
      await life.init();
      await life.openGiant(Rle.decode('#N Acorn\nx = 7, y = 3, rule = B3/S23\nbo\$3bo\$2o2b3o!'));
      life.setGiantSpeed(GiantMode.minSpeed);
      expect(life.giant!.rate, 1);
      final start = life.giant!.generation;
      for (var t = 0.0; t <= 2.0 + 1e-9; t += 0.05) {
        await life.tick(t);
      }
      expect(life.giant!.generation - start, 2);
      life.setGiantSpeed(0);
      expect((life.giant!.rate, life.giant!.jump), (null, 0), reason: '×1 runs flat out again');
      life.dispose();
    });
  });
}
