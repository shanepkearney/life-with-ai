import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_with_ai/app/assistant_controller.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/assistant_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Heart a finished seed, find it in Favourites, play it, share it, delete it.
void main() {
  http.Client scriptedApi() {
    Map<String, dynamic> reply(List<Map<String, dynamic>> content) => {
      'content': content,
      'stop_reason': 'tool_use',
      'usage': {'input_tokens': 1, 'output_tokens': 1},
    };
    final responses = [
      reply([
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'place_pattern',
          'input': {'name': 'glider', 'x': 20, 'y': 20},
        },
      ]),
      reply([
        {
          'type': 'tool_use',
          'id': 't2',
          'name': 'finish',
          'input': {'summary': 'A glider drifts away.'},
        },
      ]),
    ];
    return MockClient((_) async => http.Response(jsonEncode(responses.removeAt(0)), 200));
  }

  testWidgets('heart, recall, play, share and delete a favourite', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });

    late LifeController life;
    late AssistantController assistant;
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load());
      await life.init();
      final favorites = FavoritesStore();
      await favorites.load();
      assistant = AssistantController(life, favorites, httpClient: scriptedApi())..apiKey = 'sk-test';
      await assistant.send('One glider please');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(children: [AssistantPanel(assistant: assistant)]),
        ),
      ),
    );
    await tester.pump();

    // Heart it on the finish card.
    await tester.tap(find.byTooltip('Add to favourites'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byTooltip('Remove from favourites'), findsOneWidget);
    expect(find.bySemanticsLabel('Favourites, 1 saved'), findsOneWidget, reason: 'the tab shows the count');

    // Recall it: the panel switches to Favourites.
    await tester.tap(find.bySemanticsLabel('Favourites, 1 saved'));
    await tester.pump();
    expect(find.byTooltip('New chat'), findsNothing, reason: 'the Assistant toolbar belongs to its own tab');
    expect(find.text('One glider please'), findsOneWidget);
    expect(find.text('A glider drifts away.'), findsOneWidget);

    // Wipe the board, then play the favourite back onto it.
    await tester.runAsync(() => life.clear());
    await tester.tap(find.text('One glider please'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(life.population, 5);
    expect(life.generation, 0);
    expect(life.running, isTrue);
    expect(find.text('▶ Playing on the board'), findsOneWidget);

    // Share it.
    await tester.tap(find.byTooltip('Copy share link'));
    await tester.pump();
    final copied = ShareLink.parse(Uri.parse(clipboard!))!;
    expect(copied.seed.population, 5);
    expect(copied.title, 'One glider please');
    expect(copied.note, 'A glider drifts away.', reason: "Claude's summary travels with the link");

    // Delete it, then undo.
    await tester.tap(find.byTooltip('Remove from favourites'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(assistant.favorites.items, isEmpty);
    expect(find.textContaining('No favourites yet'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600)); // the previous message animates out, Undo animates in
    await tester.tap(find.text('Undo'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(assistant.favorites.items.single.title, 'One glider please');

    // Back to the chat.
    await tester.tap(find.text('Assistant'));
    await tester.pump();
    expect(find.byTooltip('New chat'), findsOneWidget, reason: 'the Assistant tab and its toolbar are back');

    await tester.pumpWidget(const SizedBox());
    life.dispose();
  });
}
