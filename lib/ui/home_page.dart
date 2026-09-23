import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/life_controller.dart';
import 'control_bar.dart';
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
      widget.controller.tick();
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
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) c.toggleRunning();
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
                        const Spacer(),
                        Hud(controller: c),
                      ]),
                      const SizedBox(height: 12),
                      Expanded(child: LifeCanvas(controller: c, clock: _clock, erase: _erase)),
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
