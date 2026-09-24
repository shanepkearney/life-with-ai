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
  const AssistantPanel({super.key, required this.assistant, this.embedded = false, this.showActions = true, this.onOpen});
  final AssistantController assistant;

  /// Fill the parent (the phone layout's bottom sheet) instead of being a
  /// fixed-width column with its own frame.
  final bool embedded;

  /// The phone sheet's open state: when false (resting) only its two tabs
  /// show; the chat, message box and buttons wait for the sheet to open.
  final bool showActions;

  /// Opens the phone sheet (a tab tapped while it rests).
  final VoidCallback? onOpen;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Opened from a share link, the panel starts on Favourites, where its card is.
  late bool _showFavorites = widget.assistant.shared != null;

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
          width: widget.embedded ? null : 380,
          margin: widget.embedded ? null : const EdgeInsets.fromLTRB(0, 16, 16, 16),
          decoration: widget.embedded ? null : Neon.panelDecoration(),
          child: Column(
            children: [
              _tabsHeader(a),
              const Divider(height: 1, color: Neon.border),
              if (widget.showActions && !_showFavorites) _assistantToolbar(a),
              Expanded(
                child: _showFavorites
                    ? FavoritesView(favorites: a.favorites, life: a.life, shared: a.shared)
                    : a.entries.isEmpty
                    ? _emptyState(a)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: a.entries.length + (a.busy ? 1 : 0),
                        itemBuilder: (_, i) => i == a.entries.length ? const _Working() : _EntryTile(a.entries[i], assistant: a),
                      ),
              ),
              if (!_showFavorites && widget.showActions) ...[const Divider(height: 1, color: Neon.border), _composer(a)],
            ],
          ),
        );
      },
    );
  }

  Widget _costMeter(AssistantController a) => Tooltip(
    message: '${a.usage!.input} in · ${a.usage!.cacheRead} cached · ${a.usage!.output} out',
    child: Text('≈\$${a.costUsd.toStringAsFixed(3)}', style: Neon.mono.copyWith(color: Neon.amber)),
  );

  /// Two tabs, Seed assistant and Favourites, on every layout. In the phone
  /// sheet at rest they're the whole bar and a tap opens the sheet on that view.
  Widget _tabsHeader(AssistantController a) {
    final open = widget.showActions;
    final n = a.favorites.items.length;
    void select(bool favourites) {
      setState(() => _showFavorites = favourites);
      widget.onOpen?.call();
    }

    final tabs = Row(
      children: [
        Expanded(
          child: _PhoneTab(
            icon: Icons.auto_awesome_rounded,
            label: 'Seed assistant',
            semantics: 'Seed assistant',
            selected: open && !_showFavorites,
            busy: a.busy,
            onTap: () => select(false),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _PhoneTab(
            icon: n > 0 ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            label: 'Favourites',
            semantics: n == 0 ? 'Favourites' : 'Favourites, $n saved',
            selected: open && _showFavorites,
            count: n,
            onTap: () => select(true),
          ),
        ),
      ],
    );
    return Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: tabs);
  }

  /// The Assistant view's own toolbar, under the tabs: the cost on the left,
  /// new chat and settings on the right. The Favourites view has none.
  Widget _assistantToolbar(AssistantController a) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
    child: Row(
      children: [
        if (a.usage != null) _costMeter(a),
        const Spacer(),
        IconButton(
          tooltip: 'New chat',
          visualDensity: VisualDensity.compact,
          onPressed: a.busy ? null : a.newChat,
          icon: const Icon(Icons.add_comment_rounded, size: 18),
        ),
        IconButton(
          tooltip: 'Settings',
          visualDensity: VisualDensity.compact,
          onPressed: () => showApiKeyDialog(context, a),
          icon: const Icon(Icons.key_rounded, size: 18),
        ),
      ],
    ),
  );

  Widget _emptyState(AssistantController a) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Describe what you want to see. Claude builds a seed from known patterns, simulates it, '
        'checks the result, and refines, all live on the board.',
        style: Neon.mono.copyWith(color: Neon.muted, height: 1.5),
      ),
      if (!a.hasKey) ...[
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => showApiKeyDialog(context, a),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          icon: const Icon(Icons.key_rounded, size: 16),
          label: const Text('Add your Anthropic API key'),
        ),
      ],
      const SizedBox(height: 22),
      for (final e in _examples)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PromptCard(text: e, onTap: () => _send(e)),
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
    };
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: body);
  }
}

class _PhoneTab extends StatelessWidget {
  const _PhoneTab({
    required this.icon,
    required this.label,
    required this.semantics,
    required this.selected,
    required this.onTap,
    this.count = 0,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String semantics;
  final bool selected;
  final VoidCallback onTap;
  final int count;

  /// Claude is working: a spinner replaces the icon, visible even at rest.
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: semantics,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      onTap: onTap,
      // Underlined, not boxed: the selected tab's bar sits on the divider below,
      // so there's one border (the panel's) rather than a box inside a box.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? Neon.magenta : Colors.transparent, width: 2)),
          boxShadow: selected ? [BoxShadow(color: Neon.magenta.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 6))] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Neon.magenta))
            else
              // A count sits inside the (filled) heart itself: one symbol, not a badge covering it.
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    icon,
                    size: count > 0 ? 24 : 20,
                    color: selected ? Neon.magenta : Neon.magenta.withValues(alpha: 0.8),
                    shadows: selected ? const [Shadow(color: Neon.magenta, blurRadius: 10)] : null,
                  ),
                  if (count > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2), // the heart's visual centre sits a little high
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: Neon.mono.copyWith(
                          fontSize: count > 99 ? 7 : (count > 9 ? 8.5 : 10),
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Neon.mono.copyWith(fontSize: 13, color: selected ? Neon.text : Neon.muted),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// An example prompt. Hover (or keyboard focus) lights it up clearly: the
/// default hover tint is nearly invisible on this dark panel.
class _PromptCard extends StatefulWidget {
  const _PromptCard({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  bool _hovered = false, _focused = false;
  bool get _hot => _hovered || _focused;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    // Hover straight from the mouse: FocusableActionDetector's hover highlight
    // depends on the focus system's "mouse mode", which isn't always in effect.
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap())},
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: _hot ? Neon.cyan.withValues(alpha: 0.08) : Colors.transparent,
              border: Border.all(color: _hot ? Neon.cyan.withValues(alpha: 0.7) : Neon.border),
              boxShadow: _hot ? [BoxShadow(color: Neon.cyan.withValues(alpha: 0.15), blurRadius: 14)] : null,
            ),
            child: Text(widget.text, style: Neon.mono.copyWith(color: Neon.cyan, height: 1.45)),
          ),
        ),
      ),
    ),
  );
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
