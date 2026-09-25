import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import 'theme.dart';

/// Live stats. Generations/sec is the number to watch when switching engines.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.controller, this.compact = false});

  final LifeController controller;

  /// Phones: generation and population only.
  final bool compact;

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
          stat('GEN', _grouped(c.generation), Neon.cyan),
          stat('POP', _grouped(c.population), Neon.magenta),
          if (!compact) ...[
            stat('GEN/S', c.running ? _grouped(c.gensPerSecond.round()) : '—', Neon.amber),
            stat('ENGINE', c.giant != null ? 'HashLife · endless plane' : c.engineKind.label, Neon.text),
          ],
        ],
      ),
    );
  }
}

/// 1398033 as "1,398,033": giant patterns run into the millions.
String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
