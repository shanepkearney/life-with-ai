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

/// The chat follows new rows down, but never pulls a reader who scrolled up
/// back to the bottom. It used to jump on every build, and the page rebuilds
/// it constantly while the board plays, so after a run the history couldn't be
/// read: every scroll up snapped straight back.
void main() {
  Map<String, dynamic> reply(List<Map<String, dynamic>> content) => {
    'content': content,
    'stop_reason': 'tool_use',
    'usage': {'input_tokens': 10, 'output_tokens': 10},
  };

  /// A run long enough to overflow the panel: 20 tool rows, then the finish card.
  http.Client longRun() {
    final responses = [
      reply([
        for (var i = 0; i < 20; i++)
          {
            'type': 'tool_use',
            'id': 'p$i',
            'name': 'place_pattern',
            'input': {'name': 'block', 'x': 4 + (i % 10) * 5, 'y': 4 + (i ~/ 10) * 5},
          },
        {
          'type': 'tool_use',
          'id': 's',
          'name': 'simulate',
          'input': {'generations': 4},
        },
      ]),
      reply([
        {
          'type': 'tool_use',
          'id': 'f',
          'name': 'finish',
          'input': {'summary': 'Twenty blocks sit still.'},
        },
      ]),
      {
        'content': [
          {'type': 'text', 'text': 'A follow-up answer.'},
        ],
        'stop_reason': 'end_turn',
        'usage': {'input_tokens': 10, 'output_tokens': 10},
      },
    ];
    return MockClient((_) async => http.Response(jsonEncode(responses.removeAt(0)), 200));
  }

  testWidgets('a reader who scrolled up stays put while the page rebuilds, and sending brings the chat back down', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late LifeController life;
    late AssistantController assistant;
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load());
      await life.init();
      assistant = AssistantController(life, FavoritesStore(), httpClient: longRun())..apiKey = 'sk-test';
      await assistant.send('twenty blocks');
    });

    // A parent that rebuilds on demand, as the page does while the board plays.
    late StateSetter rebuildPage;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuildPage = setState;
              return SizedBox(height: 500, child: AssistantPanel(assistant: assistant));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final list = tester
        .state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first)
        .position;
    expect(list.pixels, list.maxScrollExtent, reason: 'opens on the newest row');

    // Scroll up to read the history, then let the page rebuild many times.
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump();
    final reading = list.pixels;
    expect(reading, lessThan(list.maxScrollExtent - 200));
    for (var i = 0; i < 20; i++) {
      rebuildPage(() {});
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(list.pixels, reading, reason: 'rebuilds must not pull the reader back down');

    // Sending brings their own message, and the reply, into view.
    await tester.enterText(find.byType(TextField), 'and now?');
    await tester.tap(find.byTooltip('Send'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('A follow-up answer.'), findsOneWidget);
    expect(list.pixels, list.maxScrollExtent);

    await tester.pumpWidget(const SizedBox());
    life.dispose();
  });
}
