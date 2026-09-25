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
}
