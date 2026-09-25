import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/assistant_controller.dart';
import 'package:life_with_ai/app/community.dart';
import 'package:life_with_ai/app/community_submit.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/assistant_panel.dart';
import 'package:life_with_ai/ui/community_view.dart';
import 'package:life_with_ai/ui/favorites_view.dart';
import 'package:life_with_ai/ui/glider_loader.dart';
import 'package:life_with_ai/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LifeController life;
  late FavoritesStore favorites;
  late List<CommunitySeed> seeds;
  String? clipboard;

  Future<void> setUp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    clipboard = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load());
      await life.init();
      favorites = FavoritesStore();
      await favorites.load();
      seeds = await loadCommunitySeeds(rootBundle);
    });
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }

  Widget host(Widget child) => MaterialApp(
    theme: Neon.theme(),
    home: Scaffold(
      body: Row(children: [SizedBox(width: 380, child: child)]),
    ),
  );

  testWidgets('the Community tab lists the bundled seeds with credit, and plays and saves them', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setUp(tester);
    final opened = <Uri>[];
    await tester.pumpWidget(host(CommunityView(seeds: seeds, favorites: favorites, life: life, openUrl: (u) async => opened.add(u))));
    await tester.pump();

    for (final name in ['Neon Frame', 'Boxed Chaos', 'Tool Concert', 'Oscillator Garden']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('“A symmetrical bloom you would see at a tool concert.”'), findsOneWidget);

    // The credit links to the author's GitHub.
    await tester.tap(find.text('by @shanepkearney', findRichText: true).first);
    expect(opened.single.toString(), 'https://github.com/shanepkearney');

    // Tap a card to play it.
    await tester.tap(find.text('Oscillator Garden'));
    await settle(tester);
    expect(life.boardTitle, 'Oscillator Garden');
    expect(life.generation, 0);
    expect(life.running, isTrue);
    expect(find.text('▶ Playing on the board'), findsOneWidget);

    // Heart it: it's saved with its description.
    final garden = seeds.firstWhere((s) => s.name == 'Oscillator Garden');
    await tester.tap(find.byTooltip('Add to favorites').at(seeds.indexOf(garden)));
    await settle(tester);
    expect(favorites.items.single.title, 'Oscillator Garden');
    expect(favorites.items.single.summary, garden.description);

    await tester.pumpWidget(const SizedBox());
    life.dispose();
  });

  testWidgets('a classic credits its discoverer and source, and every card downloads its .rle file', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setUp(tester);
    final opened = <Uri>[];
    final saved = <(String, String, String)>[];
    await tester.pumpWidget(
      host(
        CommunityView(
          seeds: seeds,
          favorites: favorites,
          life: life,
          openUrl: (u) async => opened.add(u),
          saveFile: (bytes, name, mime) async {
            saved.add((name, mime, utf8.decode(bytes)));
            return (label: 'Downloads', file: null);
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Found by Bill Gosper, 1970'), findsOneWidget);
    expect(find.text('added by @shanepkearney', findRichText: true), findsWidgets);
    final gun = seeds.firstWhere((s) => s.name == 'Gosper glider gun');
    await tester.tap(find.byTooltip('Where it came from: conwaylife.com').at(seeds.where((s) => s.source != null).toList().indexOf(gun)));
    expect(opened.single, gun.source);

    await tester.tap(find.byTooltip('Download .rle').at(seeds.indexOf(gun)));
    await settle(tester);
    expect(saved.single.$1, 'gosper-glider-gun.rle');
    expect(saved.single.$2, 'application/x-life');
    expect(saved.single.$3, gun.rle, reason: 'the file exactly as committed');
    expect(find.text('Saved gosper-glider-gun.rle to Downloads'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    life.dispose();
  });

  testWidgets('the Community tab loads its seeds when first opened, with the glider loader meanwhile', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setUp(tester);
    var loads = 0;
    var pending = Completer<List<CommunitySeed>>();
    final assistant = AssistantController(
      life,
      favorites,
      communitySource: () {
        loads++;
        return pending.future;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: Neon.theme(),
        home: Scaffold(
          body: Row(children: [AssistantPanel(assistant: assistant)]),
        ),
      ),
    );
    await tester.pump();
    expect(loads, 0, reason: 'nothing loads until the tab is opened');

    await tester.tap(find.text('Community'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(loads, 1);
    expect(find.byType(GliderLoader), findsOneWidget);
    expect(find.text('Loading community seeds…'), findsOneWidget);

    // A failure offers a retry, which loads again.
    pending.completeError(Exception('offline'));
    await tester.pump();
    expect(find.text("Couldn't load the community seeds."), findsOneWidget);
    pending = Completer();
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(loads, 2);
    expect(find.byType(GliderLoader), findsOneWidget);

    pending.complete(seeds);
    await tester.pump();
    expect(find.byType(GliderLoader), findsNothing);
    expect(find.text(seeds.first.name), findsOneWidget);
    expect(find.byTooltip('New chat'), findsNothing);

    // Switching away and back doesn't load again.
    await tester.tap(find.text('Assistant'));
    await tester.pump();
    await tester.tap(find.text('Community'));
    await tester.pump();
    expect(loads, 2);
    expect(find.text(seeds.first.name), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    life.dispose();
  });

  test("the loader's frames are the glider's real phases, and it returns to its shape a cell on", () {
    Set<(int, int)> shape(Iterable<(int, int)> cells) {
      final minX = cells.map((c) => c.$1).reduce(math.min), minY = cells.map((c) => c.$2).reduce(math.min);
      return {for (final (x, y) in cells) (x - minX, y - minY)};
    }

    final phases = GliderLoader.phases;
    expect(phases, hasLength(4));
    expect(shape(phases[0]), shape(patternLibrary['glider']!.cells));
    for (final p in phases) {
      expect(p, hasLength(5), reason: 'every phase of a glider has five cells');
    }
    expect(shape(phases[1]), isNot(shape(phases[0])));
    // One more step from the last phase is the first, moved one cell down and right.
    final grid = Grid(12, 12);
    for (final (x, y) in phases[3]) {
      grid.set(x + 2, y + 2, true);
    }
    final next = grid.step();
    final cells = [
      for (var y = 0; y < 12; y++)
        for (var x = 0; x < 12; x++)
          if (next.get(x, y)) (x - 3, y - 3),
    ];
    expect(cells.toSet(), phases[0].toSet());
  });

  testWidgets('Submit opens GitHub with the entry filled in, or copies it when it is too long', (tester) async {
    await setUp(tester);
    final glider = Grid(512, 384)
      ..set(11, 10, true)
      ..set(12, 11, true)
      ..set(10, 12, true)
      ..set(11, 12, true)
      ..set(12, 12, true);
    await tester.runAsync(() => favorites.add(glider, title: 'One glider please', summary: 'A glider drifts away.'));
    final opened = <Uri>[];
    await tester.pumpWidget(host(FavoritesView(favorites: favorites, life: life, openUrl: (u) async => opened.add(u))));
    await tester.pump();

    await tester.tap(find.byTooltip('Submit to the community'));
    await settle(tester);
    final url = opened.single;
    expect(url.host, 'github.com');
    expect(url.path, '/${CommunitySubmit.repo}/new/main/community/seeds');
    expect(url.queryParameters['filename'], 'one-glider-please.rle');
    final entry = url.queryParameters['value']!;
    expect(entry, contains('#C Added: '));
    expect(entry, contains('by @${CommunitySubmit.authorPlaceholder}'));
    expect(entry, startsWith('#N One glider please\n#O ${CommunitySubmit.authorPlaceholder}\n'));
    expect(entry, contains('#C Prompt: One glider please'));
    expect(entry, contains('#C A glider drifts away.'));
    // With a real username it passes the same check a pull request runs.
    final ready = CommunitySeed.parse(entry.replaceAll(CommunitySubmit.authorPlaceholder, 'octocat'));
    expect(ready.seed!.population, 5);
    expect(clipboard, isNull);

    // A seed too long for GitHub's URL: the entry goes by clipboard.
    final soup = Grid(512, 384);
    for (var i = 0; i < 3000; i++) {
      soup.set((i * 37) % 512, (i * 91) % 384, true);
    }
    await tester.runAsync(() => favorites.add(soup, title: 'Soup', summary: Favorite.momentSummary));
    await tester.pump();
    opened.clear();
    await tester.tap(find.byTooltip('Submit to the community').first);
    await settle(tester);
    expect(opened.single.queryParameters.containsKey('value'), isFalse);
    expect(opened.single.queryParameters['filename'], 'soup.rle');
    final pasted = clipboard!;
    expect(pasted, startsWith('#N Soup\n'));
    expect(pasted, isNot(contains('#C Prompt:')), reason: 'a board saved by hand has no prompt');
    expect(find.textContaining('Paste it into the new file'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    life.dispose();
  });
}
