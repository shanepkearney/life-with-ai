import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/anthropic_client.dart';
import '../ai/seed_agent.dart';
import '../ai/seed_tools.dart';
import 'life_controller.dart';

enum EntryKind { user, assistant, thinking, tool, error, done }

class ChatEntry {
  ChatEntry(this.kind, this.text, {this.detail});
  final EntryKind kind;
  final String text;

  /// Expandable extra (the full tool result the model saw).
  final String? detail;
}

/// Glue between the chat panel, the agent loop, and the live board.
class AssistantController extends ChangeNotifier {
  AssistantController(this._life);

  final LifeController _life;
  final entries = <ChatEntry>[];

  String? apiKey;
  ClaudeModel model = ClaudeModel.opus5;
  bool rememberKey = false;
  bool busy = false;
  SeedAgent? _agent;

  static const _keyPref = 'anthropic_api_key';
  static const _modelPref = 'anthropic_model';

  bool get hasKey => (apiKey ?? '').isNotEmpty;
  Usage? get usage => _agent?.usage;
  double get costUsd => _agent?.usage.costUsd(model) ?? 0;
  int get maxTurns => 10;

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      apiKey = prefs.getString(_keyPref);
      rememberKey = apiKey != null;
      model = ClaudeModel.byId(prefs.getString(_modelPref));
    } catch (_) {
      // Storage can be unavailable (private browsing); the key then lives in memory only.
    }
    notifyListeners();
  }

  Future<void> saveSettings({required String key, required ClaudeModel model, required bool remember}) async {
    apiKey = key.trim();
    rememberKey = remember;
    if (model != this.model) {
      this.model = model;
      _resetAgent();
    } else {
      _agent = null; // pick up the new key
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelPref, model.id);
      remember ? await prefs.setString(_keyPref, apiKey!) : await prefs.remove(_keyPref);
    } catch (_) {}
    notifyListeners();
  }

  void newChat() {
    _resetAgent();
    entries.clear();
    notifyListeners();
  }

  void _resetAgent() {
    _agent?.client.close();
    _agent = null;
  }

  void stop() => _agent?.cancel();

  Future<void> send(String prompt) async {
    if (busy || !hasKey || prompt.trim().isEmpty) return;
    // A new board size invalidates the seed and the coordinates in the history.
    if (_agent != null && (_agent!.workbench.seed.width != _life.width || _agent!.workbench.seed.height != _life.height)) {
      _resetAgent();
    }
    final agent = _agent ??= SeedAgent(
      client: AnthropicClient(apiKey: apiKey!, model: model),
      workbench: SeedWorkbench(_life.width, _life.height),
      maxTurns: maxTurns,
    );

    busy = true;
    entries.add(ChatEntry(EntryKind.user, prompt.trim()));
    if (_life.running) _life.toggleRunning();
    notifyListeners();

    try {
      await for (final e in agent.send(prompt.trim())) {
        switch (e) {
          case AgentThinking(:final text):
            entries.add(ChatEntry(EntryKind.thinking, text));
          case AgentText(:final text):
            entries.add(ChatEntry(EntryKind.assistant, text));
          case AgentToolCall():
            break; // shown together with its result
          case AgentToolResult(:final name, :final outcome):
            entries.add(ChatEntry(
              outcome.isError ? EntryKind.error : EntryKind.tool,
              _describe(name, outcome),
              detail: outcome.text,
            ));
          case AgentSeed(:final seed):
            await _life.load(seed); // live preview while the agent works
          case AgentExperiment(:final number, :final seed, :final generations):
            // Replays while the next API call is in flight; Claude already has the report.
            await _life.playExperiment(Experiment(number: number, seed: seed, generations: generations));
          case AgentUsage():
            break;
          case AgentDone(:final summary, :final play):
            if (summary != null) entries.add(ChatEntry(EntryKind.done, summary));
            if (play) await _life.handOff(agent.workbench.seed.copy());
          case AgentError(:final message):
            entries.add(ChatEntry(EntryKind.error, message));
        }
        notifyListeners();
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static String _describe(String tool, ToolOutcome o) {
    final first = o.text.split('\n').first;
    return switch (tool) {
      'simulate' => 'simulate · ${o.text.split('\n').skip(1).first.replaceFirst('Fate: ', '')}${o.png != null ? ' · 🖼' : ''}',
      'view_board' => 'view_board',
      'finish' => 'finish',
      _ => '$tool · $first',
    };
  }
}
