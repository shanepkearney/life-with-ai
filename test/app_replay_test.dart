import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_with_ai/app/assistant_controller.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/assistant_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Claude's final seed, and each experiment it ran, can be replayed from the chat.
void main() {
  Map<String, dynamic> reply(List<Map<String, dynamic>> content) => {
        'content': content,
        'stop_reason': 'tool_use',
        'usage': {'input_tokens': 10, 'output_tokens': 10},
      };
  Map<String, dynamic> tool(String id, String name, Map<String, dynamic> input) =>
      {'type': 'tool_use', 'id': id, 'name': name, 'input': input};

  /// One scripted run: place a glider, simulate 8 generations, finish.
  http.Client scriptedApi() {
    final responses = [
      reply([
        tool('t1', 'place_pattern', {'name': 'glider', 'x': 20, 'y': 20}),
        tool('t2', 'simulate', {'generations': 8}),
      ]),
      reply([tool('t3', 'finish', {'summary': 'A glider drifts away.'})]),
    ];
    return MockClient((_) async => http.Response(jsonEncode(responses.removeAt(0)), 200));
  }

  Future<(LifeController, AssistantController)> runOnce() async {
    SharedPreferences.setMockInitialValues({});
    final life = LifeController(await Shaders.load());
    await life.init();
    final assistant = AssistantController(life, FavoritesStore(), httpClient: scriptedApi())..apiKey = 'sk-test';
    await assistant.send('one glider');
    return (life, assistant);
  }

  testWidgets('the finish card replays Claude\'s seed from generation 0', (tester) async {
    await tester.runAsync(() async {
      final (life, assistant) = await runOnce();
      final done = assistant.entries.singleWhere((e) => e.kind == EntryKind.done);
      expect(done.canReplay, isTrue);

      // The user moves on: the board is cleared.
      await life.clear();
      expect(life.population, 0);

      await assistant.replay(done);
      expect(life.generation, 0);
      expect(life.population, 5);
      expect(life.running, isTrue);
      expect(life.experiment, isNull, reason: 'a seed replay is normal play, not an experiment');
      life.dispose();
    });
  });

  testWidgets('a simulate row replays that exact experiment', (tester) async {
    await tester.runAsync(() async {
      final (life, assistant) = await runOnce();
      final sim = assistant.entries.singleWhere((e) => e.experiment != null);
      expect(sim.text, startsWith('simulate'));
      await life.clear();

      await assistant.replay(sim);
      expect(life.experiment!.number, 1);
      expect(life.experiment!.generations, 8);
      expect(life.generation, 0);
      expect(life.population, 5);
      life.dispose();
    });
  });

  testWidgets('replay buttons appear in the chat and are disabled while Claude works', (tester) async {
    late LifeController life;
    late AssistantController assistant;
    await tester.runAsync(() async => (life, assistant) = await runOnce());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [AssistantPanel(assistant: assistant)]))));
    await tester.pump();

    expect(find.text('Replay seed'), findsOneWidget);
    Finder button(String label) => find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(tester.widget<ButtonStyleButton>(button('Replay seed')).onPressed, isNotNull);

    assistant.busy = true;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    assistant.notifyListeners();
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(button('Replay seed')).onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    life.dispose();
  });
}
