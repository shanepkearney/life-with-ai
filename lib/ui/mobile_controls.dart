import 'package:flutter/material.dart';

import '../app/giant_mode.dart';
import '../app/life_controller.dart';
import '../engine/life_engine.dart';
import 'colors_dialog.dart';
import 'control_bar.dart' show RuleMenu;
import 'screen_board.dart';
import 'theme.dart';
import 'zoom_controls.dart';

/// The phone control strip: the buttons used constantly, in one row, with
/// speed, glow, engine and board size behind a ⚙ sheet. Tooltips match the
/// desktop control bar, so both layouts are driven the same way.
class MobileControls extends StatelessWidget {
  const MobileControls({super.key, required this.controller, required this.erase, required this.onEraseChanged, this.onSaveMoment, this.onRle});

  final LifeController controller;
  final bool erase;
  final ValueChanged<bool> onEraseChanged;
  final VoidCallback? onSaveMoment;

  /// In the ⚙ sheet rather than the strip: the strip is full, and RLE is a desk job.
  final VoidCallback? onRle;

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
            c.giant != null ? null : () => onEraseChanged(!erase),
          ),
          if (onSaveMoment != null) button(Icons.favorite_border_rounded, 'Save this moment to favorites', c.giant != null ? null : onSaveMoment),
          button(Icons.tune_rounded, 'Speed, glow and engine', () => _showTuning(context)),
        ],
      ),
    );
  }

  void _showTuning(BuildContext pageContext) => showModalBottomSheet<void>(
    context: pageContext,
    backgroundColor: const Color(0xFA0B0E17),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    // Taller than the default 9/16 of the screen when it needs to be, and it
    // scrolls past that: it outgrew the default once it held Colors and RLE.
    isScrollControlled: true,
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        Widget label(String text) => Text(text, style: Neon.mono.copyWith(color: Neon.muted));
        // Each setting on one line: its label in a fixed column, so the controls line up,
        // and the control to its right, dropping to a second row when it doesn't fit.
        const labelWidth = 92.0;
        Widget field(String text, Widget control) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: labelWidth, child: label(text)),
              control,
            ],
          ),
        );
        // A slider has no width of its own to wrap by: it takes the rest of the line.
        Widget sliderField(String text, Widget slider) => Row(
          children: [
            SizedBox(width: labelWidth, child: label(text)),
            Expanded(child: slider),
          ],
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.giant case final g?)
                  sliderField(
                    g.speedShort,
                    Slider(
                      value: g.speed.toDouble(),
                      min: GiantMode.minSpeed.toDouble(),
                      max: GiantMode.maxJump.toDouble(),
                      divisions: GiantMode.maxJump - GiantMode.minSpeed,
                      label: g.speedLabel,
                      onChanged: (v) => c.setGiantSpeed(v.round()),
                    ),
                  )
                else
                  sliderField(
                    'Speed ${c.targetRate}/s',
                    Slider(
                      value: c.speedIndex.toDouble(),
                      max: (LifeController.speedLevels.length - 1).toDouble(),
                      divisions: LifeController.speedLevels.length - 1,
                      label: '${c.targetRate} generations/s',
                      onChanged: (v) => c.setSpeedIndex(v.round()),
                    ),
                  ),
                // The colors editor (with the glow) needs the board to preview on, so the sheet makes way.
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.of(context).pop();
                    showColorsDialog(pageContext, c);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(width: labelWidth + 12, child: label('Colors')),
                        PaletteSwatch(c.palette, width: 64, height: 14),
                        const SizedBox(width: 10),
                        Text(c.palette.name, style: Neon.mono),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded, color: Neon.muted),
                      ],
                    ),
                  ),
                ),
                field(
                  'Engine',
                  SegmentedButton<EngineKind>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: Neon.cyan.withValues(alpha: 0.18),
                      selectedForegroundColor: Neon.cyan,
                      side: const BorderSide(color: Neon.border),
                    ),
                    showSelectedIcon: false,
                    segments: [for (final k in EngineKind.values) ButtonSegment(value: k, tooltip: '${k.label}: ${k.about}', label: Text(k.short))],
                    selected: {c.engineKind},
                    onSelectionChanged: c.giant != null ? null : (s) => c.switchEngine(s.first),
                  ),
                ),
                field('Rule', RuleMenu(controller: c, width: 200)), // room here for the full name
                // A pattern on the endless plane has no board to size.
                if (c.giant == null)
                  field(
                    'Board size',
                    SegmentedButton<BoardSize>(
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: Neon.cyan.withValues(alpha: 0.18),
                        selectedForegroundColor: Neon.cyan,
                        side: const BorderSide(color: Neon.border),
                      ),
                      showSelectedIcon: false,
                      segments: [
                        for (final s in {...BoardSize.mobile, screenBoardFor(context), c.boardSize})
                          ButtonSegment(
                            value: s,
                            tooltip: s.label,
                            // Four segments share a phone's width: "Fit screen" would wrap.
                            label: Text(s.fitsScreen ? 'Fit' : s.label, style: Neon.mono),
                          ),
                      ],
                      selected: {c.boardSize},
                      onSelectionChanged: (s) => c.setBoardSize(s.first),
                    ),
                  ),
                field('Zoom ${c.giant?.zoomShort ?? c.boardView.label}', ZoomControls(controller: c)),
                const SizedBox(height: 12),
                // Clear and RLE live here on phones, to keep the strip to one row.
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        c.clear();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                      label: const Text('Clear the board'),
                    ),
                    if (onRle != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onRle!();
                        },
                        icon: const Icon(Icons.import_export_rounded, size: 18),
                        label: const Text('Import or export RLE'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
