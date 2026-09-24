import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/app/telemetry.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/render/shaders.dart';

Grid glider([int x = 10]) {
  final g = Grid(512, 384);
  patternLibrary['glider']!.stampOnto(g, x, 10);
  return g;
}

void main() {
  Telemetry live({http.Client? client}) => Telemetry(endpoint: 'https://events.example/v1/event', version: '1.1.1', platform: 'web', client: client);

  test('a fingerprint is stable, 12 hex characters, and different for different seeds', () {
    final a = Telemetry.fingerprint(glider()), b = Telemetry.fingerprint(glider());
    expect(a, b);
    expect(a, matches(RegExp(r'^[0-9a-f]{12}$')));
    expect(Telemetry.fingerprint(glider(40)), isNot(a));
  });

  test("the event carries exactly what the collector accepts (analytics/src/index.js), and never a seed's cells or title", () {
    final body = jsonDecode(live().seedOpenedBody(glider(), SeedSource.shareLink)!) as Map<String, Object?>;
    expect(body.keys.toSet(), {'event', 'seed', 'source', 'version', 'platform'});
    expect(body['event'], 'seed_opened');
    expect(body['seed'], matches(RegExp(r'^[0-9a-f]{12}$')));
    expect(body['source'], 'share_link');
    expect(body['version'], matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(body['platform'], anyOf('web', 'macos'));

    final community = jsonDecode(live().seedOpenedBody(glider(), SeedSource.community, communityName: 'Oscillator Garden')!) as Map;
    expect(community['name'], 'Oscillator Garden');
    final favorite = jsonDecode(live().seedOpenedBody(glider(), SeedSource.favorite, communityName: 'A prompt')!) as Map;
    expect(favorite.containsKey('name'), isFalse, reason: 'names only for community seeds; other titles are prompts');
  });

  test('a local build (no collector address, or no version) sends nothing', () async {
    var calls = 0;
    final counting = MockClient((r) async {
      calls++;
      return http.Response('', 204);
    });
    for (final t in [
      Telemetry(endpoint: '', version: '1.1.1', platform: 'web', client: counting),
      Telemetry(endpoint: 'https://events.example/v1/event', version: '', platform: 'web', client: counting),
      Telemetry(endpoint: 'https://events.example/v1/event', version: '1.1.1', platform: '', client: counting),
    ]) {
      expect(t.enabled, isFalse);
      await t.seedOpened(glider(), SeedSource.favorite);
    }
    expect(calls, 0);
    expect(Telemetry.fromEnvironment().enabled, isFalse, reason: 'tests, like local builds, have no TELEMETRY_URL');
  });

  test('a released build posts the event as text/plain, and a failure never throws', () async {
    final sent = <http.Request>[];
    await live(client: MockClient((r) async {
      sent.add(r);
      return http.Response('', 204);
    })).seedOpened(glider(), SeedSource.community, communityName: 'Tool Concert');
    expect(sent.single.url.toString(), 'https://events.example/v1/event');
    expect(sent.single.headers['Content-Type'], startsWith('text/plain'));
    expect((jsonDecode(sent.single.body) as Map)['name'], 'Tool Concert');

    await live(client: MockClient((_) async => throw Exception('offline'))).seedOpened(glider(), SeedSource.favorite);
  });

  group('the board reports what was opened', () {
    late LifeController life;
    final opened = <(String, SeedSource, String?)>[];
    setUp(() async {
      opened.clear();
      life = LifeController(await Shaders.load());
      await life.init();
      life.onSeedOpened = (seed, source, {communityName}) => opened.add((Telemetry.fingerprint(seed), source, communityName));
    });
    tearDown(() => life.dispose());

    testWidgets('playing with a source reports it; a replay without one does not', (tester) async {
      await tester.runAsync(() => life.playSeed(glider(), title: 'x', source: SeedSource.community, communityName: 'Neon Frame'));
      await tester.runAsync(() => life.playSeed(glider(), title: 'x'));
      expect(opened, [(Telemetry.fingerprint(glider()), SeedSource.community, 'Neon Frame')]);
    });

    testWidgets("Claude's finished seed reports as the assistant's", (tester) async {
      await tester.runAsync(() => life.handOff(glider(), title: 'A bloom'));
      expect(opened.single.$2, SeedSource.assistant);
    });
  });
}
