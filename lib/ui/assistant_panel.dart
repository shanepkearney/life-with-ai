import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../app/assistant_controller.dart';
import 'favorites_view.dart';
import 'api_key_dialog.dart';
import 'theme.dart';
import 'toasts.dart';

const _examples = [
  'Two glider fleets that collide in the middle and explode into colour',
  'A symmetric bloom that slowly settles into a garden of oscillators',
  'Maximum hotspots: keep the whole board churning for a long time',
  'A Gosper gun whose gliders get eaten before they wrap around',
];

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({super.key, required this.assistant});
  final AssistantController assistant;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _showFavorites = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final a = widget.assistant;
    if (!a.hasKey) {
      showApiKeyDialog(context, a);
      return;
    }
    a.send(text ?? _input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.assistant, widget.assistant.favorites]),
      builder: (context, _) {
        final a = widget.assistant;
        if (!_showFavorites) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
          });
        }
        return Container(
          width: 380,
          margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
          decoration: Neon.panelDecoration(),
          child: Column(
            children: [
              _header(a),
              const Divider(height: 1, color: Neon.border),
              Expanded(
                child: _showFavorites
                    ? FavoritesView(favorites: a.favorites, life: a.life)
                    : a.entries.every((e) => e.kind == EntryKind.shared)
                    ? _emptyState(a)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: a.entries.length + (a.busy ? 1 : 0),
                        itemBuilder: (_, i) => i == a.entries.length ? const _Working() : _EntryTile(a.entries[i], assistant: a),
                      ),
              ),
              if (!_showFavorites) ...[const Divider(height: 1, color: Neon.border), _composer(a)],
            ],
          ),
        );
      },
    );
  }

  Widget _header(AssistantController a) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
    child: Row(
      children: [
        if (_showFavorites)
          IconButton(
            tooltip: 'Back to chat',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _showFavorites = false),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
          )
        else
          const Icon(
            Icons.auto_awesome_rounded,
            color: Neon.magenta,
            size: 18,
            shadows: [Shadow(color: Neon.magenta, blurRadius: 10)],
          ),
        const SizedBox(width: 8),
        // Shrinks before the cost meter and buttons do.
        Expanded(
          child: Text(
            _showFavorites ? 'Favourites' : 'Seed assistant',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Neon.mono.copyWith(fontSize: 14),
          ),
        ),
        if (!_showFavorites) _favoritesButton(a),
        if (a.usage != null && !_showFavorites)
          Tooltip(
            message: '${a.usage!.input} in · ${a.usage!.cacheRead} cached · ${a.usage!.output} out',
            child: Text('≈\$${a.costUsd.toStringAsFixed(3)}', style: Neon.mono.copyWith(color: Neon.amber)),
          ),
        IconButton(tooltip: 'New chat', onPressed: a.busy ? null : a.newChat, icon: const Icon(Icons.add_comment_rounded, size: 18)),
        IconButton(tooltip: 'Settings', onPressed: () => showApiKeyDialog(context, a), icon: const Icon(Icons.key_rounded, size: 18)),
      ],
    ),
  );

  Widget _favoritesButton(AssistantController a) {
    final n = a.favorites.items.length;
    return IconButton(
      tooltip: n == 0 ? 'Favourites' : 'Favourites ($n)',
      onPressed: () => setState(() => _showFavorites = true),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        backgroundColor: Neon.magenta,
        child: Icon(n > 0 ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 18, color: n > 0 ? Neon.magenta : null),
      ),
    );
  }

  Widget _emptyState(AssistantController a) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      for (final e in a.entries) _EntryTile(e, assistant: a),
      Text(
        'Describe what you want to see. Claude builds a seed from known patterns, simulates it, '
        'checks the result, and refines, all live on the board.',
        style: Neon.mono.copyWith(color: Neon.muted, height: 1.5),
      ),
      if (!a.hasKey) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => showApiKeyDialog(context, a),
          icon: const Icon(Icons.key_rounded, size: 16),
          label: const Text('Add your Anthropic API key'),
        ),
      ],
      const SizedBox(height: 16),
      for (final e in _examples)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _send(e),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Neon.border),
              ),
              child: Text(e, style: Neon.mono.copyWith(color: Neon.cyan)),
            ),
          ),
        ),
    ],
  );

  Widget _composer(AssistantController a) => Padding(
    padding: const EdgeInsets.all(10),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            enabled: !a.busy,
            minLines: 1,
            maxLines: 4,
            style: Neon.mono.copyWith(fontSize: 13),
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: a.entries.isEmpty ? 'What should happen?' : 'Refine it…',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 6),
        a.busy
            ? IconButton.filledTonal(tooltip: 'Stop', onPressed: a.stop, icon: const Icon(Icons.stop_rounded))
            : IconButton.filled(tooltip: 'Send', onPressed: _send, icon: const Icon(Icons.arrow_upward_rounded)),
      ],
    ),
  );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry, {required this.assistant});
  final ChatEntry entry;
  final AssistantController assistant;

  Widget _seedActions(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        _heartButton(context),
        IconButton(
          tooltip: 'Copy share link',
          visualDensity: VisualDensity.compact,
          color: Neon.cyan,
          onPressed: () => _copyLink(context),
          icon: const Icon(Icons.link_rounded, size: 18),
        ),
        const Spacer(),
        _replayButton('Replay seed', 'Put this seed back on the board and play it from generation 0'),
      ],
    ),
  );

  Widget _heartButton(BuildContext context) {
    final saved = assistant.isFavorite(entry);
    return IconButton(
      tooltip: saved ? 'Remove from favourites' : 'Add to favourites',
      visualDensity: VisualDensity.compact,
      onPressed: () => assistant.toggleFavorite(entry),
      icon: Icon(
        saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 18,
        color: Neon.magenta,
        shadows: saved ? const [Shadow(color: Neon.magenta, blurRadius: 10)] : null,
      ),
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    final link = assistant.shareLinkFor(entry);
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    Toasts.show(context, 'Link copied. Anyone who opens it sees this seed play.');
  }

  /// Disabled while Claude is working: it drives the board then.
  Widget _replayButton(String label, String tooltip) => Tooltip(
    message: assistant.busy ? 'Available when Claude has finished' : tooltip,
    child: TextButton.icon(
      onPressed: assistant.busy ? null : () => assistant.replay(entry),
      icon: const Icon(Icons.replay_rounded, size: 16),
      label: Text(label, style: Neon.mono.copyWith(fontSize: 11, color: null)),
      style: TextButton.styleFrom(
        foregroundColor: Neon.magenta,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final style = Neon.mono.copyWith(height: 1.45);
    Widget body = switch (e.kind) {
      EntryKind.user => Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Neon.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(e.text, style: style),
        ),
      ),
      EntryKind.assistant => Text(e.text, style: style),
      EntryKind.thinking => Text(
        e.text,
        style: style.copyWith(color: Neon.muted, fontStyle: FontStyle.italic, fontSize: 11),
      ),
      EntryKind.error when e.detail == null => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: Neon.amber),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(e.text, style: style.copyWith(fontSize: 12, color: Neon.amber)),
          ),
        ],
      ),
      EntryKind.tool || EntryKind.error => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: Icon(
            e.kind == EntryKind.error
                ? Icons.error_outline_rounded
                : e.experiment != null
                ? Icons.science_outlined
                : Icons.build_circle_outlined,
            size: 16,
            color: e.kind == EntryKind.error ? Neon.amber : Neon.cyan,
          ),
          title: Text(
            e.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(fontSize: 11, color: e.kind == EntryKind.error ? Neon.amber : Neon.text),
          ),
          children: [
            if (e.experiment != null)
              Align(
                alignment: Alignment.centerLeft,
                child: _replayButton(
                  'Replay experiment ${e.experiment!.number}',
                  'Play this test run again, from generation 0 to ${e.experiment!.generations}',
                ),
              ),
            if (e.detail != null) SelectableText(e.detail!, style: style.copyWith(fontSize: 9, color: Neon.muted, height: 1.1)),
          ],
        ),
      ),
      EntryKind.done => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Neon.magenta.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.play_circle_rounded, color: Neon.magenta, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(e.text, style: style)),
              ],
            ),
            if (e.seed != null) _seedActions(context),
          ],
        ),
      ),
      EntryKind.shared => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Neon.cyan.withValues(alpha: 0.6)),
          color: Neon.cyan.withValues(alpha: 0.06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded, color: Neon.cyan, size: 16),
                const SizedBox(width: 8),
                Text('SHARED WITH YOU', style: style.copyWith(fontSize: 10, color: Neon.cyan, letterSpacing: 1.5)),
              ],
            ),
            const SizedBox(height: 6),
            Text(e.text, style: style),
            _seedActions(context),
          ],
        ),
      ),
    };
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: body);
  }
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Neon.magenta)),
        const SizedBox(width: 10),
        Text('Claude is designing…', style: Neon.mono.copyWith(color: Neon.muted)),
      ],
    ),
  );
}
