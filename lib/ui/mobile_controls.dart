import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import '../engine/life_engine.dart';
import 'theme.dart';

/// The phone control strip: the buttons used constantly, in one row, with
/// speed, glow, engine and board size behind a ⚙ sheet. Tooltips match the
/// desktop control bar, so both layouts are driven the same way.
class MobileControls extends StatelessWidget {
  const MobileControls({super.key, required this.controller, required this.erase, required this.onEraseChanged, this.onSaveMoment});

  final LifeController controller;
  final bool erase;
  final ValueChanged<bool> onEraseChanged;
  final VoidCallback? onSaveMoment;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget button(IconData icon, String tip, VoidCallback? onTap, {bool glow = false}) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, shadows: glow ? const [Shadow(color: Neon.cyan, blurRadius: 12)] : null),
      color: glow ? Neon.cyan : Neon.text,
      disabledColor: Neon.muted.withValues(alpha: 0.4),
      // Eight buttons across a 375pt phone: 40pt targets, still above the 36pt minimum.
      visualDensity: VisualDensity.compact,
    );
    return Container(
      decoration: Neon.panelDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          button(Icons.first_page_rounded, 'Back to the start', c.atBeginning ? null : c.rewindToStart),
          button(Icons.skip_previous_rounded, 'Step back one generation (←)', c.canStepBack ? c.stepBack : null),
          button(
            c.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
            c.running ? 'Pause (space)' : 'Play (space)',
            c.toggleRunning,
            glow: true,
          ),
          button(Icons.skip_next_rounded, 'Step one generation (→)', c.running ? null : c.stepOnce),
          button(Icons.shuffle_rounded, 'Randomize', () => c.randomize()),
          button(
            erase ? Icons.auto_fix_normal_rounded : Icons.edit_rounded,
            erase ? 'Drawing erases — tap to draw' : 'Drawing adds cells — tap to erase',
            () => onEraseChanged(!erase),
          ),
          if (onSaveMoment != null) button(Icons.favorite_border_rounded, 'Save this moment to favorites', onSaveMoment),
          button(Icons.tune_rounded, 'Speed, glow and engine', () => _showTuning(context)),
        ],
      ),
    );
  }

  void _showTuning(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFA0B0E17),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        Widget label(String text) => Text(text, style: Neon.mono.copyWith(color: Neon.muted));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label('Speed · ${c.targetRate} generations/s'),
                Slider(
                  value: c.speedIndex.toDouble(),
                  max: (LifeController.speedLevels.length - 1).toDouble(),
                  divisions: LifeController.speedLevels.length - 1,
                  onChanged: (v) => c.setSpeedIndex(v.round()),
                ),
                label('Glow'),
                Slider(value: c.pipeline.glow, max: 2, onChanged: c.setGlow),
                const SizedBox(height: 8),
                label('Engine'),
                const SizedBox(height: 6),
                SegmentedButton<EngineKind>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: Neon.cyan.withValues(alpha: 0.18),
                    selectedForegroundColor: Neon.cyan,
                    side: const BorderSide(color: Neon.border),
                  ),
                  showSelectedIcon: false,
                  segments: [for (final k in EngineKind.values) ButtonSegment(value: k, label: Text(k.label))],
                  selected: {c.engineKind},
                  onSelectionChanged: (s) => c.switchEngine(s.first),
                ),
                const SizedBox(height: 16),
                // Clear lives here on phones, to keep the strip to one row.
                OutlinedButton.icon(
                  onPressed: () {
                    c.clear();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text('Clear the board'),
                ),
                const SizedBox(height: 16),
                label('Board size'),
                const SizedBox(height: 6),
                SegmentedButton<BoardSize>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: Neon.cyan.withValues(alpha: 0.18),
                    selectedForegroundColor: Neon.cyan,
                    side: const BorderSide(color: Neon.border),
                  ),
                  showSelectedIcon: false,
                  segments: [
                    for (final s in {...BoardSize.mobile, c.boardSize})
                      ButtonSegment(
                        value: s,
                        label: Text(s.label, style: Neon.mono),
                      ),
                  ],
                  selected: {c.boardSize},
                  onSelectionChanged: (s) => c.setBoardSize(s.first),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
