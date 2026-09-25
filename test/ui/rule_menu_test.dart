import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/life_rule.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/home_page.dart';
import 'package:life_with_ai/ui/theme.dart';

import 'board_only_test.dart' show FakeFullScreen;

final highLife = LifeRule.parse('B36/S23')!;

void main() {
  late LifeController life;

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load());
      await life.init();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Neon.theme(),
        home: HomePage(controller: life, fullScreen: FakeFullScreen()),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      life.dispose();
    });
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('choosing a rule keeps the board and runs it by the new rule from there', (tester) async {
    await start(tester);
    if (life.running) life.toggleRunning();
    await settle(tester);
    final before = (await tester.runAsync(() => life.captureMoment()))!.seed;
    final generation = life.generation;
    expect(find.text('RULE Conway', findRichText: true), findsOneWidget, reason: "the HUD always names the rule, Conway's too");

    // The HUD's RULE is the menu.
    await tester.tap(find.byKey(const Key('hud-rule')));
    await settle(tester);
    await tester.tap(find.text('HighLife  B36/S23').last);
    await settle(tester);

    expect(life.rule, highLife);
    expect(life.engine.rule, highLife, reason: 'the engine runs by it');
    expect(life.generation, generation, reason: 'the board carries on from where it was');
    final after = (await tester.runAsync(() => life.captureMoment()))!.seed;
    expect(after.stateHash, before.stateHash, reason: 'the same board');

    // One step, by HighLife exactly.
    await tester.runAsync(life.stepOnce);
    await tester.pump();
    final stepped = (await tester.runAsync(() => life.captureMoment()))!.seed;
    expect(stepped.stateHash, before.step(highLife).stateHash);
    expect(life.timeline!.rule, highLife, reason: 'rewind replays by it too');
    expect(find.text('RULE HighLife', findRichText: true), findsOneWidget, reason: 'the HUD names it, in amber');
  });

  testWidgets("a seed plays by its own rule; Claude's designs go back to Conway's", (tester) async {
    await start(tester);
    final g = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(g, 100, 100);
    await tester.runAsync(() => life.playSeed(g, title: 'A HighLife seed', rule: highLife));
    expect((life.rule, life.engine.rule), (highLife, highLife));
    await tester.runAsync(() => life.handOff(g, title: 'Claude'));
    expect((life.rule, life.engine.rule), (LifeRule.conway, LifeRule.conway));
  });

  test("favorites keep a seed's rule; ones saved before rules are Conway's", () {
    final g = Grid(64, 48)..set(10, 10, true);
    final f = Favorite(code: 'x', title: 't', summary: 's', savedAt: DateTime(2026), rule: highLife);
    expect(f.toJson()['rule'], 'B36/S23');
    expect(Favorite(code: 'x', title: 't', summary: 's', savedAt: DateTime(2026)).toJson().containsKey('rule'), isFalse);
    final json = {'code': ShareLink.forSeed(g).split('seed=')[1].split('&').first, 'title': 't', 'summary': 's', 'savedAt': '2026-01-01T00:00:00.000'};
    expect(Favorite.fromJson(json)!.rule, LifeRule.conway, reason: 'an old favorite');
    expect(Favorite.fromJson({...json, 'rule': 'B36/S23'})!.rule, highLife);
    expect(Favorite.fromJson({...json, 'rule': 'nonsense'})!.rule, LifeRule.conway);
  });

  test("share links carry a rule other than Conway's, and old links are Conway's", () {
    final g = Grid(64, 48)..set(10, 10, true);
    final conway = ShareLink.forSeed(g, title: 'x');
    expect(conway, isNot(contains('rule=')));
    expect(ShareLink.parse(Uri.parse(conway))!.rule, LifeRule.conway);
    final high = ShareLink.forSeed(g, title: 'x', rule: highLife);
    expect(high, contains('rule=B36%2FS23'));
    expect(ShareLink.parse(Uri.parse(high))!.rule, highLife);
    expect(ShareLink.parse(Uri.parse('$conway&rule=garbage'))!.rule, LifeRule.conway, reason: 'a bad rule never loses the seed');
  });
}
