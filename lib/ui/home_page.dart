import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/life_controller.dart';
import 'control_bar.dart';
import 'experiment_overlay.dart';
import 'hud.dart';
import 'life_canvas.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, this.sidePanel});

  final LifeController controller;
  final Widget? sidePanel;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _focus = FocusNode();
  bool _erase = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _clock.value = elapsed.inMicroseconds / 1e6;
      widget.controller.tick(_clock.value);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (e) {
          if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.space) return;
          // Key events bubble up from the chat box; a space typed there is text, not play/pause.
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null)) return;
          c.toggleRunning();
        },
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(children: [
                        Text('LIFE', style: Neon.mono.copyWith(fontSize: 18, letterSpacing: 6, color: Neon.cyan, shadows: const [Shadow(color: Neon.cyan, blurRadius: 14)])),
                        Text(' with AI', style: Neon.mono.copyWith(fontSize: 18, color: Neon.magenta, shadows: const [Shadow(color: Neon.magenta, blurRadius: 14)])),
                        const SizedBox(width: 16),
                        // Scale the stats down rather than overflow on narrow windows.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(fit: BoxFit.scaleDown, child: Hud(controller: c)),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Stack(children: [
                          Positioned.fill(child: LifeCanvas(controller: c, clock: _clock, erase: _erase)),
                          Positioned(top: 12, left: 12, child: ExperimentOverlay(controller: c)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      ControlBar(controller: c, erase: _erase, onEraseChanged: (v) => setState(() => _erase = v)),
                    ],
                  ),
                ),
              ),
              if (widget.sidePanel != null) widget.sidePanel!,
            ],
          ),
        ),
      ),
    );
  }
}
