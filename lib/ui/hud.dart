import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import 'theme.dart';

/// Live stats. Generations/sec is the number to watch when switching engines.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.controller});

  final LifeController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget stat(String k, String v, Color color) => Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$k ',
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
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: Neon.panelDecoration(radius: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          stat('GEN', '${c.generation}', Neon.cyan),
          stat('POP', '${c.population}', Neon.magenta),
          stat('GEN/S', c.running ? c.gensPerSecond.toStringAsFixed(0) : '—', Neon.amber),
          stat('ENGINE', c.engineKind.label, Neon.text),
        ],
      ),
    );
  }
}
