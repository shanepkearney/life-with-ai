import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/main.dart';
import 'package:life_with_ai/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Example prompts light up clearly under the mouse, and settle back after.
void main() {
  testWidgets('hovering an example prompt highlights it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 920);
    addTearDown(tester.view.reset);
    late LifeApp app;
    await tester.runAsync(() async => app = await bootstrap());
    await tester.pumpWidget(app);
    await tester.pump();

    final prompt = find.textContaining('Two glider fleets');
    Color border() {
      final box = tester.widget<AnimatedContainer>(find.ancestor(of: prompt, matching: find.byType(AnimatedContainer)).first);
      return ((box.decoration! as BoxDecoration).border! as Border).top.color;
    }

    expect(border(), Neon.border);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(prompt));
    await tester.pump(const Duration(milliseconds: 200));
    expect(border(), Neon.cyan.withValues(alpha: 0.7), reason: 'lit up under the mouse');

    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    expect(border(), Neon.border, reason: 'back to normal');

    await tester.pumpWidget(const SizedBox());
    app.controller.dispose();
  });
}
