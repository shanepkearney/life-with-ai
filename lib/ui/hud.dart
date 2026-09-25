import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import '../engine/life_engine.dart';
import 'control_bar.dart' show ruleChoices, ruleTip;
import 'screen_board.dart';
import 'theme.dart';

/// Live stats. Generations/sec is the number to watch when switching engines.
/// On desktop ENGINE and RULE are menus too: click either to change it.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.controller, this.compact = false});

  final LifeController controller;

  /// Phones: generation and population only.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    // The Row spaces the stats: nothing after the last, so the box ends where they do.
    Widget stat(String k, String v, Color color) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$k: ',
            style: Neon.mono.copyWith(color: Neon.muted),
          ),
          TextSpan(
            text: v,
            style: Neon.mono.copyWith(
              color: color,
              shadows: [Shadow(color: color, blurRadius: 8)],
            ),
          ),
        ],
      ),
    );
    return Container(
      // Phones: a little tighter, the HUD shares the header with the logo and buttons.
      padding: compact ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: Neon.panelDecoration(radius: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: compact ? 14 : 18,
        children: [
          stat('GEN', _grouped(c.generation), Neon.cyan),
          stat('POP', _grouped(c.population), Neon.magenta),
          if (!compact) ...[
            stat('GEN/S', c.running ? _grouped(c.gensPerSecond.round()) : '—', Neon.amber),
            // On the plane, what's playing and how close in: it replaces the board's own chip here.
            if (c.giant case final g?) stat('PATTERN', _short(g.name), Neon.text),
            // How far in: before the menus, so SIZE, ENGINE and RULE stay side by side.
            if (c.giant case final g?)
              stat('ZOOM', g.zoomShort, Neon.cyan)
            else if (c.boardView.zoomed)
              stat('ZOOM', c.boardView.label, Neon.cyan),
            // The plane has no board to size.
            if (c.giant == null)
              _HudMenu<BoardSize>(
                key: const Key('hud-size'),
                stat: stat('SIZE', c.boardSize.shortLabel, Neon.text),
                tooltip: 'Board size · ${c.boardSize.label}',
                value: c.boardSize,
                items: [
                  for (final s in boardSizeChoices(context, c.boardSize, phone: false))
                    (value: s, text: s.label, detail: '${_grouped(s.width * s.height)} cells'),
                ],
                onSelected: (s) => s == c.boardSize ? null : c.setBoardSize(s),
              ),
            // A giant pattern runs on HashLife's endless plane only: no menu there.
            _HudMenu<EngineKind>(
              key: const Key('hud-engine'),
              stat: stat('ENGINE', c.giant != null ? 'HashLife · endless plane' : c.engineKind.label, Neon.text),
              tooltip: c.giant != null ? 'A giant pattern runs on HashLife' : '${c.engineKind.label}: ${c.engineKind.about}',
              value: c.engineKind,
              items: [for (final k in EngineKind.values) (value: k, text: k.label, detail: k.about)],
              onSelected: c.giant != null ? null : c.switchEngine,
            ),
            // Always shown; amber when it isn't Conway's, a reminder that this isn't standard Life.
            _HudMenu(
              key: const Key('hud-rule'),
              stat: stat('RULE', c.rule.label, c.rule.isConway ? Neon.text : Neon.amber),
              tooltip: ruleTip(c),
              value: c.rule,
              items: ruleChoices(c.rule),
              onSelected: c.giant != null ? null : c.setRule,
            ),
          ],
        ],
      ),
    );
  }
}

/// A stat that opens a menu below it to change it, marked by a small ▾.
/// Without [onSelected] it's a plain stat.
class _HudMenu<T> extends StatelessWidget {
  const _HudMenu({super.key, required this.stat, required this.tooltip, required this.value, required this.items, required this.onSelected});

  final Widget stat;
  final String tooltip;
  final T value;
  final List<({T value, String text, String detail})> items;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    if (onSelected == null) return Tooltip(message: tooltip, child: stat);
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: value,
      position: PopupMenuPosition.under,
      color: const Color(0xFF0B0E17),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final i in items)
          PopupMenuItem<T>(
            value: i.value,
            child: Tooltip(
              message: i.detail,
              child: Text(i.text, style: Neon.mono.copyWith(color: i.value == value ? Neon.cyan : Neon.text)),
            ),
          ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            stat,
            const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Neon.muted),
          ],
        ),
      ),
    );
  }
}

/// A long name cut short, so the header never runs out of room.
String _short(String name) => name.length <= 18 ? name : '${name.substring(0, 17)}…';

/// 1398033 as "1,398,033": giant patterns run into the millions.
String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
