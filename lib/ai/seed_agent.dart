import 'dart:convert';

import '../core/grid.dart';
import '../core/patterns.dart';
import 'anthropic_client.dart';
import 'seed_tools.dart';

/// Everything the UI needs to narrate a run.
sealed class AgentEvent {}

class AgentThinking extends AgentEvent {
  AgentThinking(this.text);
  final String text;
}

class AgentText extends AgentEvent {
  AgentText(this.text);
  final String text;
}

class AgentToolCall extends AgentEvent {
  AgentToolCall(this.name, this.input);
  final String name;
  final Map<String, dynamic> input;
}

class AgentToolResult extends AgentEvent {
  AgentToolResult(this.name, this.outcome);
  final String name;
  final ToolOutcome outcome;
}

/// The seed changed — the UI previews it live.
class AgentSeed extends AgentEvent {
  AgentSeed(this.seed);
  final Grid seed;
}

/// Claude ran a simulation; the UI replays it on the board while Claude thinks.
class AgentExperiment extends AgentEvent {
  AgentExperiment(this.number, this.seed, this.generations);
  final int number;
  final Grid seed;
  final int generations;
}

class AgentUsage extends AgentEvent {
  AgentUsage(this.usage);
  final Usage usage;
}

/// The run ended. [play] is true when there is a seed to hand over.
class AgentDone extends AgentEvent {
  AgentDone(this.summary, {this.play = true});
  final String? summary;
  final bool play;
}

class AgentError extends AgentEvent {
  AgentError(this.message);
  final String message;
}

/// Drives the tool-use loop: ask Claude, run the tools it calls against the
/// workbench, feed the results back, repeat until it calls `finish`, stops on
/// its own, or hits [maxTurns].
///
/// The conversation persists across [send] calls so follow-ups ("now make it
/// symmetric") build on the same seed.
class SeedAgent {
  SeedAgent({required this.client, required this.workbench, this.maxTurns = 10});

  final AnthropicClient client;
  final SeedWorkbench workbench;
  final int maxTurns;
  final usage = Usage();
  final List<Map<String, dynamic>> messages = [];
  bool _cancelled = false;
  int _experiments = 0;

  void cancel() => _cancelled = true;

  Stream<AgentEvent> send(String prompt) async* {
    _cancelled = false;
    _appendUser([
      {'type': 'text', 'text': prompt},
    ]);

    for (var turn = 0; turn < maxTurns; turn++) {
      final Map<String, dynamic> response;
      try {
        response = await client.createMessage(_requestBody());
      } catch (e) {
        yield AgentError('$e');
        return;
      }
      usage.add(response['usage'] as Map<String, dynamic>?);
      yield AgentUsage(usage);
      if (_cancelled) {
        // Drop the unanswered response so the history stays valid.
        yield AgentDone('Stopped.', play: false);
        return;
      }

      // Append the content verbatim: thinking and fallback blocks must be
      // echoed back unchanged on the next request.
      final content = (response['content'] as List).cast<Map<String, dynamic>>();
      messages.add({'role': 'assistant', 'content': content});

      for (final block in content) {
        switch (block['type']) {
          case 'thinking' when (block['thinking'] as String? ?? '').isNotEmpty:
            yield AgentThinking(block['thinking'] as String);
          case 'text' when (block['text'] as String).trim().isNotEmpty:
            yield AgentText(block['text'] as String);
        }
      }

      switch (response['stop_reason']) {
        case 'tool_use':
          String? finishSummary;
          final results = <Map<String, dynamic>>[];
          // Run sequentially: the tools share one mutable seed, so order matters.
          for (final call in content.where((b) => b['type'] == 'tool_use')) {
            final name = call['name'] as String;
            final input = (call['input'] as Map?)?.cast<String, dynamic>() ?? {};
            yield AgentToolCall(name, input);
            final outcome = _cancelled ? const ToolOutcome('Cancelled by the user.', isError: true) : await workbench.run(name, input);
            yield AgentToolResult(name, outcome);
            if (outcome.seedChanged) yield AgentSeed(workbench.seed.copy());
            if (name == 'simulate' && !outcome.isError) {
              yield AgentExperiment(++_experiments, workbench.seed.copy(), (input['generations'] as num).toInt());
            }
            if (outcome.finished) finishSummary = input['summary'] as String?;
            results.add(_toolResult(call['id'] as String, outcome));
          }
          _appendUser(results);
          if (finishSummary != null) {
            yield AgentDone(finishSummary);
            return;
          }
          if (_cancelled) {
            yield AgentDone('Stopped.', play: false);
            return;
          }
        case 'end_turn':
          // Claude replied without calling finish — usually a question for the user.
          yield AgentDone(null, play: false);
          return;
        case 'refusal':
          yield AgentError('Claude declined that request. Try rephrasing it.');
          return;
        case 'max_tokens':
          yield AgentError('The response was cut off (max_tokens). Try a simpler request.');
          return;
        default:
          yield AgentError('Unexpected stop reason: ${response['stop_reason']}');
          return;
      }
    }
    yield AgentDone('Reached the $maxTurns-step limit, so here is the best seed so far.');
  }

  Map<String, dynamic> _requestBody() => {
    'max_tokens': 16000,
    'thinking': {'type': 'adaptive', 'display': 'summarized'},
    // Auto-places a cache breakpoint on the last cacheable block, so the
    // system prompt, tools and prior turns are re-read at 0.1x cost.
    'cache_control': {'type': 'ephemeral'},
    'system': systemPrompt(workbench.seed.width, workbench.seed.height),
    'tools': seedToolDefinitions,
    'messages': messages,
  };

  /// Tool results for one assistant turn go back in ONE user message; a new
  /// prompt after a finished run is merged into that same message.
  void _appendUser(List<Map<String, dynamic>> blocks) {
    if (messages.isNotEmpty && messages.last['role'] == 'user') {
      (messages.last['content'] as List).addAll(blocks);
    } else {
      messages.add({
        'role': 'user',
        'content': [...blocks],
      });
    }
  }

  static Map<String, dynamic> _toolResult(String id, ToolOutcome o) => {
    'type': 'tool_result',
    'tool_use_id': id,
    if (o.isError) 'is_error': true,
    'content': [
      {'type': 'text', 'text': o.text},
      if (o.png != null)
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': 'image/png', 'data': base64Encode(o.png!)},
        },
    ],
  };
}

/// Stable for a given board size, so it stays in the prompt cache.
String systemPrompt(int width, int height) {
  final library = patternLibrary.values.map((p) => '- ${p.name} (${p.width}x${p.height}): ${p.description}').join('\n');
  return '''
You design starting patterns ("seeds") for Conway's Game of Life. The user describes an outcome — a look, a behaviour, a story ("two glider fleets collide and explode", "slow bloom that settles into a symmetric garden", "as many colourful hotspots as possible") — and you build a seed that produces it, check it by simulating, and refine it.

The board is $width x $height cells: x runs left to right, y top to bottom, and the edges wrap (a torus), so anything leaving one side re-enters the opposite side. Rules are standard B3/S23. The seed board starts empty for a new request; on a follow-up it still holds your previous seed, which you can edit or clear.

How it looks to the user: live cells glow, moving cells leave neon trails, and regions where many cells congregate light up as hotspots — cool cyan when sparse, through magenta and amber to white-hot when dense. Churning, dense regions are the most colourful; lone still lifes are dim.

Pattern library (names for place_pattern; at rotation 0 spaceships travel right, gliders down-right; rotations are clockwise):
$library

Work like an engineer: sketch a plan, build the seed, simulate, read the report (fate, population curve, hotspots, thumbnails), and adjust — spacing, timing, orientation, or a different pattern. Game of Life is chaotic, so verify interactions rather than predicting them; a glider collision that is one cell off behaves completely differently. Use include_image when the shape itself matters. You have a limited number of steps, so batch several edits per turn and stop refining once the result is good. Then call finish with a short summary of what the user will see.

Keep text to the user brief: a sentence on the plan up front, and the finish summary. If the request is ambiguous in a way that changes the seed substantially, ask one short question instead of guessing.''';
}
