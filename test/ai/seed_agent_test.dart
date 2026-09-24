import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_with_ai/ai/anthropic_client.dart';
import 'package:life_with_ai/ai/seed_agent.dart';
import 'package:life_with_ai/ai/seed_tools.dart';
import 'package:life_with_ai/ai/simulation.dart';

/// Replays scripted API responses and records every request body.
class ScriptedApi {
  ScriptedApi(this.responses);

  final List<Map<String, dynamic>> responses;
  final requests = <Map<String, dynamic>>[];
  final headers = <Map<String, String>>[];

  http.Client get client => MockClient((req) async {
    requests.add(jsonDecode(req.body) as Map<String, dynamic>);
    headers.add(req.headers);
    final next = responses.removeAt(0);
    final status = next.remove('_status') as int? ?? 200;
    return http.Response(jsonEncode(next), status);
  });
}

Map<String, dynamic> reply(String stop, List<Map<String, dynamic>> content) => {
  'id': 'msg',
  'type': 'message',
  'role': 'assistant',
  'content': content,
  'stop_reason': stop,
  'usage': {'input_tokens': 100, 'output_tokens': 50, 'cache_read_input_tokens': 1000},
};

Map<String, dynamic> toolUse(String id, String name, Map<String, dynamic> input) => {
  'type': 'tool_use',
  'id': id,
  'name': name,
  'input': input,
};

SeedAgent agentFor(ScriptedApi api, {int maxTurns = 10, ClaudeModel model = ClaudeModel.opus5}) => SeedAgent(
  client: AnthropicClient(apiKey: 'sk-test', model: model, httpClient: api.client, maxRetries: 0),
  workbench: SeedWorkbench(64, 48, simulator: (r) async => runSimulation(r)),
  maxTurns: maxTurns,
);

void main() {
  test('runs tools, feeds results back, and hands over the seed on finish', () async {
    final api = ScriptedApi([
      reply('tool_use', [
        {'type': 'thinking', 'thinking': 'A glider is enough.', 'signature': 'sig'},
        {'type': 'text', 'text': 'Placing a glider.'},
        toolUse('t1', 'place_pattern', {'name': 'glider', 'x': 3, 'y': 3}),
        toolUse('t2', 'simulate', {'generations': 8}),
      ]),
      reply('tool_use', [
        toolUse('t3', 'finish', {'summary': 'A lone glider drifts across.'}),
      ]),
    ]);
    final agent = agentFor(api);
    final events = await agent.send('one glider please').toList();

    expect(events.whereType<AgentThinking>().single.text, 'A glider is enough.');
    expect(events.whereType<AgentToolCall>().map((e) => e.name), ['place_pattern', 'simulate', 'finish']);
    expect(events.whereType<AgentSeed>().single.seed.population, 5);
    final experiment = events.whereType<AgentExperiment>().single;
    expect((experiment.number, experiment.generations, experiment.seed.population), (1, 8, 5));
    final done = events.last as AgentDone;
    expect(done.summary, 'A lone glider drifts across.');
    expect(done.play, isTrue);

    // Second request: assistant turn echoed verbatim (incl. thinking signature),
    // then ONE user message holding both tool results, in order.
    final second = api.requests[1]['messages'] as List;
    expect(second[1]['content'][0]['signature'], 'sig');
    final results = second[2]['content'] as List;
    expect(results.map((r) => r['tool_use_id']), ['t1', 't2']);
    expect(results[1]['content'][0]['text'], contains('Simulated 8 generations'));
  });

  test('sends auth, browser-access and fallback headers, and caches the prefix', () async {
    final api = ScriptedApi([
      reply('end_turn', [
        {'type': 'text', 'text': 'Which color?'},
      ]),
    ]);
    final events = await agentFor(api).send('something pretty').toList();
    expect((events.last as AgentDone).play, isFalse);

    final h = api.headers.single;
    expect(h['x-api-key'], 'sk-test');
    expect(h['anthropic-version'], '2023-06-01');
    expect(h['anthropic-dangerous-direct-browser-access'], 'true');
    expect(h['anthropic-beta'], 'server-side-fallback-2026-07-01');
    final body = api.requests.single;
    expect(body['model'], 'claude-opus-5');
    expect(body['fallbacks'], 'default');
    expect(body['cache_control'], {'type': 'ephemeral'});
    expect(body['thinking'], {'type': 'adaptive', 'display': 'summarized'});
  });

  test('Sonnet requests carry no fallback parameters', () async {
    final api = ScriptedApi([
      reply('end_turn', [
        {'type': 'text', 'text': 'ok'},
      ]),
    ]);
    await agentFor(api, model: ClaudeModel.sonnet5).send('hi').toList();
    expect(api.headers.single.containsKey('anthropic-beta'), isFalse);
    expect(api.requests.single.containsKey('fallbacks'), isFalse);
  });

  test('stops at the turn cap and still hands over the seed', () async {
    final api = ScriptedApi([
      for (var i = 0; i < 3; i++)
        reply('tool_use', [
          toolUse('t$i', 'place_pattern', {'name': 'block', 'x': i * 4, 'y': 0}),
        ]),
    ]);
    final events = await agentFor(api, maxTurns: 3).send('keep going forever').toList();
    expect(api.requests, hasLength(3));
    expect((events.last as AgentDone).summary, contains('3-step limit'));
  });

  test('a tool error is reported to the model, which can recover', () async {
    final api = ScriptedApi([
      reply('tool_use', [
        toolUse('t1', 'place_pattern', {'name': 'unicorn', 'x': 0, 'y': 0}),
      ]),
      reply('tool_use', [
        toolUse('t2', 'finish', {'summary': 'done'}),
      ]),
    ]);
    await agentFor(api).send('x').toList();
    final result = (api.requests[1]['messages'] as List)[2]['content'][0];
    expect(result['is_error'], isTrue);
    expect(result['content'][0]['text'], contains('No pattern "unicorn"'));
  });

  test('API errors surface as a readable message', () async {
    final api = ScriptedApi([
      {
        '_status': 401,
        'type': 'error',
        'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'},
      },
    ]);
    final events = await agentFor(api).send('x').toList();
    expect((events.last as AgentError).message, contains('API key was rejected'));
  });

  test('a follow-up prompt keeps history valid and reuses the seed', () async {
    final api = ScriptedApi([
      reply('tool_use', [
        toolUse('t1', 'place_pattern', {'name': 'glider', 'x': 3, 'y': 3}),
      ]),
      reply('tool_use', [
        toolUse('t2', 'finish', {'summary': 'one'}),
      ]),
      reply('tool_use', [
        toolUse('t3', 'finish', {'summary': 'two'}),
      ]),
    ]);
    final agent = agentFor(api);
    await agent.send('first').toList();
    await agent.send('second').toList();
    // Roles must alternate: the new prompt is merged into the trailing tool-result message.
    final roles = (api.requests.last['messages'] as List).map((m) => m['role']).toList();
    expect(roles, ['user', 'assistant', 'user', 'assistant', 'user']);
    final last = (api.requests.last['messages'] as List).last['content'] as List;
    expect(last.last, {'type': 'text', 'text': 'second'});
    expect(agent.workbench.seed.population, 5);
  });

  test('workspace spend-limit errors say where to fix them', () async {
    final api = ScriptedApi([
      {
        '_status': 400,
        'type': 'error',
        'error': {
          'type': 'invalid_request_error',
          'message': 'You have reached your specified workspace API usage limits. You will regain access on 2026-10-01 at 00:00 UTC.',
        },
      },
    ]);
    final events = await agentFor(api).send('x').toList();
    final msg = (events.last as AgentError).message;
    expect(msg, contains('regain access on 2026-10-01'));
    expect(msg, contains('platform.claude.com/settings/limits'));
  });

  test('cost meter prices cache reads at a tenth of input', () {
    final u = Usage()..add({'input_tokens': 1000000, 'cache_read_input_tokens': 1000000, 'output_tokens': 0});
    expect(u.costUsd(ClaudeModel.opus5), closeTo(5.5, 1e-9));
  });
}
