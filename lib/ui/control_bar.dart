import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import '../engine/life_engine.dart';
import 'theme.dart';

class ControlBar extends StatelessWidget {
  const ControlBar({super.key, required this.controller, required this.erase, required this.onEraseChanged, this.onSaveMoment});

  final LifeController controller;
  final bool erase;
  final ValueChanged<bool> onEraseChanged;

  /// Hearts whatever is on the board right now.
  final VoidCallback? onSaveMoment;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: Neon.panelDecoration(),
      child: Wrap(
        spacing: 4,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Icon(icon: Icons.first_page_rounded, tip: 'Back to the start', onTap: c.atBeginning ? null : c.rewindToStart),
          _Icon(icon: Icons.skip_previous_rounded, tip: 'Step back one generation (←)', onTap: c.canStepBack ? c.stepBack : null),
          _Icon(
            icon: c.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tip: c.running ? 'Pause (space)' : 'Play (space)',
            glow: true,
            onTap: c.toggleRunning,
          ),
          _Icon(icon: Icons.skip_next_rounded, tip: 'Step one generation (→)', onTap: c.running ? null : c.stepOnce),
          _Icon(icon: Icons.shuffle_rounded, tip: 'Randomise', onTap: () => c.randomize()),
          _Icon(icon: Icons.delete_sweep_rounded, tip: 'Clear', onTap: c.clear),
          _Icon(
            icon: erase ? Icons.auto_fix_normal_rounded : Icons.edit_rounded,
            tip: erase ? 'Drawing erases — tap to draw' : 'Drawing adds cells — tap to erase',
            onTap: () => onEraseChanged(!erase),
          ),
          if (onSaveMoment != null) _Icon(icon: Icons.favorite_border_rounded, tip: 'Save this moment to favourites', onTap: onSaveMoment),
          const _Divider(),
          _Labeled(
            label: 'Speed ${c.targetRate.toString().padLeft(3)}/s',
            child: SizedBox(
              width: 90,
              child: Slider(
                // Default side padding (~24px) is room for the thumb's glow; here it ate the track.
                padding: const EdgeInsets.symmetric(horizontal: 10),
                // Geometric steps: fine control at the slow end, where it matters.
                value: c.speedIndex.toDouble(),
                min: 0,
                max: (LifeController.speedLevels.length - 1).toDouble(),
                divisions: LifeController.speedLevels.length - 1,
                label: '${c.targetRate} generations/s',
                onChanged: (v) => c.setSpeedIndex(v.round()),
              ),
            ),
          ),
          _Labeled(
            label: 'Glow',
            child: SizedBox(
              width: 70,
              child: Slider(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                value: c.pipeline.glow,
                min: 0,
                max: 2,
                onChanged: c.setGlow,
              ),
            ),
          ),
          const _Divider(),
          SegmentedButton<EngineKind>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              selectedBackgroundColor: Neon.cyan.withValues(alpha: 0.18),
              selectedForegroundColor: Neon.cyan,
              side: const BorderSide(color: Neon.border),
            ),
            showSelectedIcon: false,
            segments: [
              for (final k in EngineKind.values)
                ButtonSegment(
                  value: k,
                  label: Text(k.label, style: const TextStyle(fontSize: 12)),
                ),
            ],
            selected: {c.engineKind},
            onSelectionChanged: (s) => c.switchEngine(s.first),
          ),
          const SizedBox(width: 4), // with the Wrap's gap: 8px off the engine toggle, like the dividers
          DropdownButtonHideUnderline(
            child: DropdownButton<BoardSize>(
              value: c.boardSize,
              isDense: true,
              style: Neon.mono,
              dropdownColor: const Color(0xFF0B0E17),
              items: [
                for (final s in {...BoardSize.desktop, c.boardSize}) DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (s) => s == null ? null : c.setBoardSize(s),
            ),
          ),
        ],
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.icon, required this.tip, required this.onTap, this.glow = false});

  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, shadows: glow ? const [Shadow(color: Neon.cyan, blurRadius: 12)] : null),
      color: glow ? Neon.cyan : Neon.text,
      disabledColor: Neon.muted.withValues(alpha: 0.4),
    ),
  );
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Neon.mono.copyWith(color: Neon.muted)),
      child,
    ],
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  // Its own margin: icon buttons carry built-in padding, but the labels and the
  // engine toggle beside a divider don't, so the Wrap's gap alone looks cramped.
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 8), color: Neon.border);
}
