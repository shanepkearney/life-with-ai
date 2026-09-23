import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/render/shaders.dart';

/// Speed is a rate in generations/second, independent of the display's refresh rate.
void main() {
  Future<int> generationsAfterOneSecond(WidgetTester tester, {required int hz, required int speedIndex}) async {
    late LifeController c;
    await tester.runAsync(() async {
      c = LifeController(await Shaders.load());
      await c.init();
      c.setSpeedIndex(speedIndex);
      c.toggleRunning();
      for (var f = 0; f <= hz; f++) {
        await c.tick(f / hz);
      }
    });
    final g = c.generation;
    c.dispose();
    return g;
  }

  for (final hz in [60, 120]) {
    testWidgets('slowest speed is 1 generation/s at $hz Hz', (tester) async {
      expect(await generationsAfterOneSecond(tester, hz: hz, speedIndex: 0), 1);
    });
    testWidgets('60 generations/s is the same at $hz Hz', (tester) async {
      expect(await generationsAfterOneSecond(tester, hz: hz, speedIndex: LifeController.speedLevels.indexOf(60)), 60);
    });
  }
}
