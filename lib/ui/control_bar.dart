import 'package:flutter/material.dart';

import '../app/giant_mode.dart';
import '../app/life_controller.dart';
import '../core/life_rule.dart';
import 'colors_dialog.dart';
import 'section_wrap.dart';
import 'theme.dart';
import 'zoom_controls.dart';

class ControlBar extends StatelessWidget {
  const ControlBar({
    super.key,
    required this.controller,
    this.erase = false,
    this.onEraseChanged,
    this.onSaveMoment,
    this.onFullScreen,
    this.fullScreen = false,
  });

  final LifeController controller;
  final bool erase;
  final ValueChanged<bool>? onEraseChanged;

  /// Hearts whatever is on the board right now.
  final VoidCallback? onSaveMoment;

  /// ⛶: expands the board, or in [fullScreen] brings everything back. At the bar's far right.
  final VoidCallback? onFullScreen;

  /// The same bar in full screen, without what edits the board or its looks
  /// (randomize, clear, draw, heart, colors): there it's for watching.
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final giant = c.giant;
    final sections = <List<Widget>>[
      // Playback.
      [
        _Icon(icon: Icons.first_page_rounded, tip: 'Back to the start', onTap: c.atBeginning ? null : c.rewindToStart),
        _Icon(icon: Icons.skip_previous_rounded, tip: 'Step back one generation (←)', onTap: c.canStepBack ? c.stepBack : null),
        _Icon(
          icon: c.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tip: c.running ? 'Pause (space)' : 'Play (space)',
          glow: true,
          onTap: c.toggleRunning,
        ),
        _Icon(
          icon: Icons.skip_next_rounded,
          tip: giant == null ? 'Step one generation (→)' : 'Jump ${giant.jumpLabel} generations (→)',
          onTap: c.running ? null : c.stepOnce,
        ),
      ],
      // What edits the board, and its colors (with the glow): not in full screen, which is for watching.
      if (!fullScreen) ...[
        [
          _Icon(icon: Icons.shuffle_rounded, tip: 'Randomize', onTap: () => c.randomize()),
          _Icon(icon: Icons.delete_sweep_rounded, tip: 'Clear', onTap: c.clear),
          // A giant pattern pans instead of drawing, and is too big to save as a moment.
          _Icon(
            icon: erase ? Icons.auto_fix_normal_rounded : Icons.edit_rounded,
            tip: erase ? 'Drawing erases — tap to draw' : 'Drawing adds cells — tap to erase',
            onTap: giant != null || onEraseChanged == null ? null : () => onEraseChanged!(!erase),
          ),
          if (onSaveMoment != null)
            _Icon(icon: Icons.favorite_border_rounded, tip: 'Save this moment to favorites', onTap: giant != null ? null : onSaveMoment),
        ],
        [_PaletteButton(controller: c)],
      ],
      // The speed; engine, rule and size are chosen from the HUD at the top.
      [SpeedControl(controller: c)],
      // How the board is shown: zoom out, Fit, zoom in (the HUD shows how far in), then ⛶,
      // divided from them but one section, so the two always wrap together.
      [
        ZoomControls(controller: c),
        if (onFullScreen != null) const _InlineDivider(),
        if (onFullScreen != null)
          fullScreen
              ? _Icon(icon: Icons.fullscreen_exit_rounded, tip: 'Exit full screen (Esc)', onTap: onFullScreen)
              : _Icon(icon: Icons.fullscreen_rounded, tip: 'Full screen (F)', onTap: onFullScreen),
      ],
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: Neon.panelDecoration(),
      // As wide as the controls need (the bar isn't stretched to the window). On a
      // narrower window it wraps between sections, never inside one, with a divider
      // only between sections that share a line.
      child: SectionWrap(
        dividerColor: Neon.border,
        children: [
          for (final section in sections) Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: section),
        ],
      ),
    );
  }
}

/// The speed: generations a second on a board, or on the endless plane the
/// jump (and, below ×1, a paced rate). In the control bar and in Board only.
class SpeedControl extends StatelessWidget {
  const SpeedControl({super.key, required this.controller});

  final LifeController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final giant = c.giant;
    if (giant == null) {
      return _Labeled(
        // Just the rate: the slider says what it is. Five characters, so the bar never shifts.
        label: '${c.targetRate}/s'.padLeft(5),
        child: SizedBox(
          width: 76,
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
      );
    }
    // HashLife jumps 2^j generations a step, as fast as it can: the size of the jump is the speed.
    // Below ×1, the slider's left end, it steps one generation at a paced rate instead.
    return _Labeled(
      label: giant.speedShort,
      child: SizedBox(
        width: 76,
        child: Slider(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          value: giant.speed.toDouble(),
          min: GiantMode.minSpeed.toDouble(),
          max: GiantMode.maxJump.toDouble(),
          divisions: GiantMode.maxJump - GiantMode.minSpeed,
          label: giant.speedLabel,
          onChanged: (v) => c.setGiantSpeed(v.round()),
        ),
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

/// A divider inside a section, spaced like [SectionWrap]'s between sections
/// (with the Row's 4px either side: 21px in all).
class _InlineDivider extends StatelessWidget {
  const _InlineDivider();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 6), color: Neon.border);
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

/// The board's colors as a small swatch; opens the colors dialog.
class _PaletteButton extends StatelessWidget {
  const _PaletteButton({required this.controller});

  final LifeController controller;

  // A standard icon button, like the rest of the bar; the dialog shows the colors themselves.
  @override
  Widget build(BuildContext context) => _Icon(
    icon: Icons.palette_rounded,
    tip: 'Board colors and glow · ${controller.palette.name}',
    onTap: () => showColorsDialog(context, controller),
  );
}

/// The rule the board runs by: the well-known ones by name, plus whatever
/// rule a loaded pattern brought. Locked while a giant pattern is loaded.
class RuleMenu extends StatelessWidget {
  const RuleMenu({super.key, required this.controller, this.width});

  final LifeController controller;

  /// Fixed, or else just wide enough for "Conway": longer names end in "…".
  final double? width;

  /// "Conway" in the menu's font, plus its arrow.
  static double conwayWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Conway', style: Neon.mono),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w.ceilToDouble() + 26; // the 24px arrow, and a hair so "Conway" never ellipsizes
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final current = c.rule;
    return CompactMenu<LifeRule>(
      width: width ?? conwayWidth(context),
      value: current,
      label: current.label,
      // Amber off Conway's: a reminder this isn't standard Life.
      color: current.isConway ? Neon.text : Neon.amber,
      tooltip: ruleTip(c),
      items: ruleChoices(current),
      onSelected: c.giant != null ? null : c.setRule,
    );
  }
}

/// The rules to choose from: the well-known ones, plus [current] when a pattern brought another.
List<({LifeRule value, String text, String detail})> ruleChoices(LifeRule current) => [
  for (final n in LifeRule.named) (value: n.rule, text: '${n.name}  ${n.rule.notation}', detail: n.about),
  if (current.name == null) (value: current, text: current.notation, detail: 'The rule of the pattern you loaded'),
];

/// What the rule does, or why it can't be changed right now.
String ruleTip(LifeController c) {
  final r = c.rule;
  if (c.giant != null) return 'The rule is fixed while a giant pattern is loaded';
  return '${r.label} (${r.notation}): ${LifeRule.named.where((n) => n.rule == r).map((n) => n.about).firstOrNull ?? 'a rule from a pattern'}';
}

/// A menu button that shows only the current choice, in a fixed [width], and
/// opens a list as wide as its items need. (A DropdownButton sizes itself to
/// its widest item, which the control bar has no room for.)
class CompactMenu<T> extends StatelessWidget {
  const CompactMenu({
    super.key,
    required this.width,
    required this.value,
    required this.label,
    required this.items,
    required this.onSelected,
    this.tooltip,
    this.color,
  });

  final double width;
  final T value;
  final String label;
  final List<({T value, String text, String detail})> items;
  final ValueChanged<T>? onSelected;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final enabled = onSelected != null;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      enabled: enabled,
      initialValue: value,
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
      child: SizedBox(
        width: width,
        height: 32,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Neon.mono.copyWith(color: enabled ? (color ?? Neon.text) : Neon.muted),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: enabled ? Neon.muted : Neon.muted.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
