import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/main.dart';
import 'package:life_with_ai/ui/control_bar.dart';
import 'package:life_with_ai/ui/mobile_controls.dart';
import 'package:life_with_ai/ui/mobile_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The layout follows the window, live: narrowing it switches to the phone
/// layout and widening switches back. (Not runnable with `--platform chrome`:
/// that harness can't load the app's shader assets.)
void main() {
  testWidgets('resizing the window switches layouts both ways', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 920);
    addTearDown(tester.view.reset);

    late LifeApp app;
    await tester.runAsync(() async => app = await bootstrap());
    await tester.pumpWidget(app);
    await tester.pump();
    expect(find.byType(ControlBar), findsOneWidget);

    for (final (size, phone) in [
      (const Size(690, 900), true), // just under the width breakpoint
      (const Size(1200, 480), true), // wide but short: landscape phone
      (const Size(1200, 800), false),
      (const Size(400, 850), true),
      (const Size(1440, 920), false),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(find.byType(MobileControls), phone ? findsOneWidget : findsNothing, reason: '$size');
      expect(find.byType(MobileSheet), phone ? findsOneWidget : findsNothing, reason: '$size');
      expect(find.byType(ControlBar), phone ? findsNothing : findsOneWidget, reason: '$size');
    }
    await tester.pumpWidget(const SizedBox());
    app.controller.dispose();
  });
}
