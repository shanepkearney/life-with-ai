import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/assistant_controller.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/main.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [const Size(1440, 900), const Size(1024, 700)]) {
    testWidgets('app lays out without overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late LifeController life;
      late AssistantController assistant;
      await tester.runAsync(() async {
        life = LifeController(await Shaders.load());
        await life.init();
        assistant = AssistantController(life, FavoritesStore());
        await assistant.loadSettings();
      });
      await tester.pumpWidget(LifeApp(controller: life, assistant: assistant));
      await tester.pump();

      expect(find.text('Assistant'), findsOneWidget);
      expect(find.text('Add your Anthropic API key'), findsOneWidget);
      // The engine and rule, in the HUD, whose menus change them.
      expect(find.text('ENGINE: GPU · shader', findRichText: true), findsOneWidget, reason: 'the engine menu');
      expect(find.text('RULE: Conway', findRichText: true), findsOneWidget, reason: 'the rule menu');

      // Without a key, sending opens the settings dialog instead of calling the API.
      await tester.tap(find.textContaining('Two glider fleets'));
      // The board's ticker runs forever, so pumpAndSettle would never return.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Assistant settings'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      life.dispose();
    });
  }
}
