import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/ai/seed_agent.dart';
import 'package:life_with_ai/app/assistant_controller.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/api_key_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LifeController life;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    life = LifeController(await Shaders.load());
    await life.init();
  });
  tearDown(() => life.dispose());

  Future<AssistantController> open(WidgetTester tester) async {
    final assistant = AssistantController(life, FavoritesStore());
    await tester.runAsync(assistant.loadSettings);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(onPressed: () => showApiKeyDialog(context, assistant), child: const Text('open')),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return assistant;
  }

  testWidgets('the token limit is chosen in Assistant settings, priced per step, and remembered', (tester) async {
    final assistant = await open(tester);
    expect(assistant.maxTokens, SeedAgent.defaultMaxTokens);
    // Opus 5 writes at $25 per million tokens: 16,000 of them cost at most $0.40.
    expect(find.text(r'16,000  ·  up to $0.40 a step'), findsOneWidget);

    await tester.tap(find.byKey(const Key('max-tokens')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'32,000  ·  up to $0.80 a step').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(assistant.maxTokens, 32000);

    // A fresh start reads it back.
    final reloaded = AssistantController(life, FavoritesStore());
    await tester.runAsync(reloaded.loadSettings);
    expect(reloaded.maxTokens, 32000);
  });

  testWidgets('a stored limit that is no longer offered falls back to the default', (tester) async {
    SharedPreferences.setMockInitialValues({'anthropic_max_tokens': 12345});
    final assistant = AssistantController(life, FavoritesStore());
    await tester.runAsync(assistant.loadSettings);
    expect(assistant.maxTokens, SeedAgent.defaultMaxTokens);
  });
}
