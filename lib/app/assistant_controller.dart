import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/anthropic_client.dart';
import '../ai/seed_agent.dart';
import '../ai/seed_tools.dart';
import '../core/grid.dart';
import '../core/seed_codec.dart';
import 'community.dart';
import 'favorites.dart';
import 'share_link.dart';
import 'life_controller.dart';

enum EntryKind { user, assistant, thinking, tool, error, done }

class ChatEntry {
  ChatEntry(this.kind, this.text, {this.detail, this.seed});
  final EntryKind kind;
  final String text;

  /// Expandable extra (the full tool result the model saw).
  final String? detail;

  /// What a replay button plays: Claude's final seed on a `done` entry, or the
  /// seed an experiment started from on a `simulate` entry.
  Grid? seed;

  /// Set on `simulate` entries: the replay stops here, like the original run.
  Experiment? experiment;

  bool get canReplay => seed != null || experiment != null;
}

/// Glue between the chat panel, the agent loop, and the live board.
class AssistantController extends ChangeNotifier {
  AssistantController(this._life, this.favorites, {http.Client? httpClient, Future<List<CommunitySeed>> Function()? communitySource})
    : _httpClient = httpClient,
      _communitySource = communitySource ?? (() => loadCommunitySeeds(rootBundle));

  final LifeController _life;
  final FavoritesStore favorites;
  LifeController get life => _life;
  final http.Client? _httpClient; // injectable for tests
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
      client: AnthropicClient(apiKey: apiKey!, model: model, httpClient: _httpClient),
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
            entries.add(ChatEntry(outcome.isError ? EntryKind.error : EntryKind.tool, _describe(name, outcome), detail: outcome.text));
          case AgentSeed(:final seed):
            await _life.load(seed); // live preview while the agent works
          case AgentExperiment(:final number, :final seed, :final generations):
            final experiment = Experiment(number: number, seed: seed, generations: generations);
            // Its tool row was just added; keep the run on it so it can be replayed later.
            entries.lastWhere((e) => e.kind == EntryKind.tool).experiment = experiment;
            // Replays while the next API call is in flight; Claude already has the report.
            await _life.playExperiment(experiment);
          case AgentUsage():
            break;
          case AgentDone(:final summary, :final play):
            if (summary != null) {
              entries.add(ChatEntry(EntryKind.done, summary, seed: play ? agent.workbench.seed.copy() : null));
            }
            if (play) await _life.handOff(agent.workbench.seed.copy(), title: promptFor(entries.last));
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

  /// The prompt that led to [entry], used as a favorite's title.
  /// The seed this app was opened with from a share link, if any. Shown at
  /// the top of the Favorites view, not in the conversation with Claude.
  SharedSeed? shared;

  /// Seeds contributed to the repo by pull request, shown on the Community tab.
  /// Null until [loadCommunity] has finished: they load when the tab is first
  /// opened, so startup never waits on them however many there are.
  List<CommunitySeed>? community;

  /// Why the last load failed, if it did. The tab offers a retry.
  Object? communityError;

  final Future<List<CommunitySeed>> Function() _communitySource;
  Future<void>? _communityLoad;

  /// Bumped by [showCommunity]; the panel switches to the Community tab (and
  /// the phone sheet opens) whenever it changes.
  int communityRequests = 0;

  /// Sends the user to the Community tab, e.g. from a broken link's message.
  void showCommunity() {
    communityRequests++;
    loadCommunity();
    notifyListeners();
  }

  /// Loads the community seeds once; later calls share the same load. After a
  /// failure, calling it again retries.
  Future<void> loadCommunity() => _communityLoad ??= _loadCommunity();

  Future<void> _loadCommunity() async {
    communityError = null;
    notifyListeners();
    try {
      community = await _communitySource();
    } catch (e) {
      communityError = e;
      _communityLoad = null;
    }
    notifyListeners();
  }

  void addShared(SharedSeed seed) {
    shared = seed;
    notifyListeners();
  }

  String promptFor(ChatEntry entry) {
    final i = entries.indexOf(entry);
    for (var j = i; j >= 0; j--) {
      if (entries[j].kind == EntryKind.user) return entries[j].text;
    }
    return 'Untitled seed';
  }

  bool isFavorite(ChatEntry entry) => entry.seed != null && favorites.contains(SeedCodec.encode(entry.seed!));

  Future<bool> toggleFavorite(ChatEntry entry) => favorites.toggle(entry.seed!, title: promptFor(entry), summary: entry.text);

  /// Link for [entry]'s seed, titled with the prompt that produced it.
  String shareLinkFor(ChatEntry entry) => ShareLink.forSeed(entry.seed!, title: promptFor(entry), note: entry.text);

  /// Replays a finished seed from generation 0, or an experiment exactly as
  /// Claude ran it. Not while Claude is working: it drives the board then.
  Future<void> replay(ChatEntry entry) async {
    if (busy) return;
    final e = entry.experiment;
    if (e != null) {
      await _life.replayExperiment(e);
    } else if (entry.seed != null) {
      await _life.playSeed(entry.seed!.copy(), title: promptFor(entry));
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
