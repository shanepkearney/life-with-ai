import 'dart:async';

import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import 'breakpoints.dart';
import 'control_bar.dart' show SpeedControl;
import 'hud.dart';
import 'life_canvas.dart';
import 'screen_board.dart';
import 'theme.dart';
import 'zoom_controls.dart';

/// Just the board, edge to edge. Moving the mouse or tapping brings up the
/// stats along the top, a small playback bar along the bottom, and the pointer;
/// all fade after a moment of stillness, so what's left is the glowing board.
/// Drawing is off: a tap only wakes them.
class BoardOnlyView extends StatefulWidget {
  const BoardOnlyView({super.key, required this.controller, required this.clock, required this.onExit});

  final LifeController controller;
  final ValueNotifier<double> clock;

  /// Leaves Board only (the bar's ✕; Esc and B are handled by the page).
  final VoidCallback onExit;

  /// How long the bar stays after the last movement or tap.
  static const linger = Duration(milliseconds: 2500);

  @override
  State<BoardOnlyView> createState() => _BoardOnlyViewState();
}

class _BoardOnlyViewState extends State<BoardOnlyView> {
  bool _visible = true; // shown on entry, so it's clear how to leave
  bool _overBar = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _wake();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  /// Shows the bar, and hides it again after [BoardOnlyView.linger], unless the pointer rests on it.
  void _wake() {
    _hide?.cancel();
    if (!_visible) setState(() => _visible = true);
    if (!_overBar) _hide = Timer(BoardOnlyView.linger, () => mounted ? setState(() => _visible = false) : null);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
    onHover: (_) => _wake(),
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      child: ColoredBox(
        color: Neon.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LifeCanvas(controller: widget.controller, clock: widget.clock, erase: false, drawable: false),
            // The stats along the top, the bar along the bottom: they come and go together.
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: SafeArea(
                bottom: false,
                child: Center(
                  // One line of stats: on a narrow screen it scales down rather than overflow.
                  child: _fading(
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) => Hud(controller: widget.controller, compact: Breakpoints.isMobile(MediaQuery.sizeOf(context))),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: Center(
                  // As wide as the screen allows: on a narrow phone the bar wraps onto a second row.
                  child: _fading(ListenableBuilder(listenable: widget.controller, builder: (context, _) => _bar(widget.controller))),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// The board's size (Fit screen fills the screen with no bars). Closed, it
  /// shows the short name, so the bar stays compact.
  Widget _sizeMenu(LifeController c) {
    final sizes = boardSizeChoices(context, c.boardSize, phone: Breakpoints.isMobile(MediaQuery.sizeOf(context)));
    return Tooltip(
      message: 'Board size',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BoardSize>(
          value: c.boardSize,
          isDense: true,
          style: Neon.mono,
          dropdownColor: const Color(0xFF0B0E17),
          items: [for (final s in sizes) DropdownMenuItem(value: s, child: Text(s.label))],
          selectedItemBuilder: (_) => [for (final s in sizes) Center(child: Text(s.shortLabel))],
          onChanged: (s) {
            if (s != null) c.setBoardSize(s);
            _wake();
          },
        ),
      ),
    );
  }

  /// Shown while [_visible], faded out otherwise; resting the pointer on it keeps it up.
  Widget _fading(Widget child) => IgnorePointer(
    ignoring: !_visible,
    child: AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: MouseRegion(
        onEnter: (_) {
          _overBar = true;
          _wake();
        },
        onExit: (_) {
          _overBar = false;
          _wake();
        },
        child: child,
      ),
    ),
  );

  Widget _bar(LifeController c) {
    // Compact buttons; on a narrow phone the bar wraps onto a second row rather than overflow.
    Widget button(IconData icon, String tip, VoidCallback? onTap, {bool glow = false}) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      color: glow ? Neon.cyan : Neon.text,
      disabledColor: Neon.muted.withValues(alpha: 0.4),
      icon: Icon(icon, shadows: glow ? const [Shadow(color: Neon.cyan, blurRadius: 12)] : null),
    );
    Widget divider() => Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 6), color: Neon.border);
    return DecoratedBox(
      decoration: Neon.panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
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
            divider(),
            // The speed and the zoom stay to hand with nothing else on screen.
            SpeedControl(controller: c),
            divider(),
            ZoomControls(controller: c),
            divider(),
            // A pattern on the endless plane has no board to size.
            if (c.giant == null) ...[_sizeMenu(c), divider()],
            button(Icons.fullscreen_exit_rounded, 'Exit full screen (Esc)', widget.onExit),
          ],
        ),
      ),
    );
  }
}
