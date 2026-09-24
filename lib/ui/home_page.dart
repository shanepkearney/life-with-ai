import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/assistant_controller.dart';
import '../app/favorites.dart';
import '../app/life_controller.dart';
import '../core/seed_codec.dart';
import 'assistant_panel.dart';
import 'breakpoints.dart';
import 'control_bar.dart';
import 'experiment_overlay.dart';
import 'hud.dart';
import 'life_canvas.dart';
import 'mobile_controls.dart';
import 'mobile_sheet.dart';
import 'theme.dart';
import 'toasts.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, this.assistant, this.notice, this.favorites});

  final LifeController controller;
  final FavoritesStore? favorites;

  /// Shown as a side panel on desktop and a bottom sheet on phones.
  final AssistantController? assistant;
  final String? notice;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _focus = FocusNode();
  final _toasts = ToastController();
  bool _erase = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _clock.value = elapsed.inMicroseconds / 1e6;
      widget.controller.tick(_clock.value);
    })..start();
    final notice = widget.notice;
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toasts.show(notice);
      });
    }
  }

  /// Hearts the board as it is right now, titled after where it came from.
  Future<void> _saveMoment() async {
    final favorites = widget.favorites!;
    void say(String text, {String? actionLabel, VoidCallback? onAction}) =>
        _toasts.show(text, actionLabel: actionLabel, onAction: onAction);

    final moment = await widget.controller.captureMoment();
    if (moment.seed.population == 0) return say('The board is empty, so there is nothing to save.');
    try {
      final added = await favorites.add(moment.seed, title: moment.title, summary: 'Saved from the board.');
      if (!added) return say('That exact board is already in your favourites.');
      final code = SeedCodec.encode(moment.seed);
      say(
        'Saved "${moment.title}" to favourites',
        actionLabel: 'Undo',
        onAction: () => favorites.remove(favorites.items.firstWhere((f) => f.code == code)),
      );
    } on FavoriteTooLarge catch (e) {
      say(e.message);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _focus.dispose();
    _toasts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Toasts(
      controller: _toasts,
      child: Scaffold(
        body: KeyboardListener(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (e) {
            final key = e.logicalKey;
            if (e is! KeyDownEvent && e is! KeyRepeatEvent) return;
            if (key != LogicalKeyboardKey.space && key != LogicalKeyboardKey.arrowLeft && key != LogicalKeyboardKey.arrowRight) return;
            // Key events bubble up from the chat box; a space typed there is text, not play/pause.
            final focused = FocusManager.instance.primaryFocus?.context;
            final typing =
                focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null);
            if (typing) return;
            // Holding an arrow repeats, scrubbing through generations; space doesn't repeat.
            if (key == LogicalKeyboardKey.space) {
              if (e is KeyDownEvent) c.toggleRunning();
            } else if (!c.running) {
              key == LogicalKeyboardKey.arrowLeft ? c.stepBack() : c.stepOnce();
            }
          },
          child: ListenableBuilder(
            listenable: c,
            // The phone layout only below the breakpoint; everything wider is the desktop layout, unchanged.
            builder: (context, _) => LayoutBuilder(builder: (context, box) => Breakpoints.isMobile(box.biggest) ? _mobile(c) : _desktop(c)),
          ),
        ),
      ),
    );
  }

  /// The desktop layout: board and controls beside the assistant panel.
  Widget _desktop(LifeController c) => Row(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'LIFE',
                    style: Neon.mono.copyWith(
                      fontSize: 18,
                      letterSpacing: 6,
                      color: Neon.cyan,
                      shadows: const [Shadow(color: Neon.cyan, blurRadius: 14)],
                    ),
                  ),
                  Text(
                    ' with AI',
                    style: Neon.mono.copyWith(
                      fontSize: 18,
                      color: Neon.magenta,
                      shadows: const [Shadow(color: Neon.magenta, blurRadius: 14)],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Scale the stats down rather than overflow on narrow windows.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Hud(controller: c),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _board(c)),
              const SizedBox(height: 12),
              ControlBar(
                controller: c,
                erase: _erase,
                onEraseChanged: (v) => setState(() => _erase = v),
                onSaveMoment: widget.favorites == null ? null : _saveMoment,
              ),
            ],
          ),
        ),
      ),
      if (widget.assistant != null) AssistantPanel(assistant: widget.assistant!),
    ],
  );

  /// The board with its overlays, shared by both layouts.
  Widget _board(LifeController c) => Stack(
    children: [
      Positioned.fill(
        child: LifeCanvas(controller: c, clock: _clock, erase: _erase),
      ),
      Positioned(top: 12, left: 12, child: ExperimentOverlay(controller: c)),
      // Bottom of the board area: always above the controls, however they wrap.
      Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: Center(child: ToastView(controller: _toasts)),
      ),
    ],
  );

  /// The phone layout: board on top, a one-row control strip, and the
  /// assistant in a bottom sheet that peeks and swipes up over the board.
  Widget _mobile(LifeController c) {
    const peek = 100.0; // handle + the panel's title bar
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 0),
                child: Row(
                  children: [
                    Text(
                      'LIFE',
                      style: Neon.mono.copyWith(
                        fontSize: 15,
                        letterSpacing: 4,
                        color: Neon.cyan,
                        shadows: const [Shadow(color: Neon.cyan, blurRadius: 12)],
                      ),
                    ),
                    Text(
                      ' with AI',
                      style: Neon.mono.copyWith(
                        fontSize: 15,
                        color: Neon.magenta,
                        shadows: const [Shadow(color: Neon.magenta, blurRadius: 12)],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Hud(controller: c, compact: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _board(c)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: MobileControls(
                  controller: c,
                  erase: _erase,
                  onEraseChanged: (v) => setState(() => _erase = v),
                  onSaveMoment: widget.favorites == null ? null : _saveMoment,
                ),
              ),
              // Room for the sheet's resting height, so it never hides the controls.
              SizedBox(height: widget.assistant == null ? 8 : peek + 8),
            ],
          ),
          if (widget.assistant != null)
            MobileSheet(
              peekHeight: peek,
              builder: (context, expanded, open) =>
                  AssistantPanel(assistant: widget.assistant!, embedded: true, showActions: expanded, onOpen: open),
            ),
        ],
      ),
    );
  }
}
