import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import 'theme.dart';

/// Labels the board while an AI experiment replays, so it's clear the user is
/// watching Claude's test run rather than the final result.
class ExperimentOverlay extends StatelessWidget {
  const ExperimentOverlay({super.key, required this.controller});

  final LifeController controller;

  @override
  Widget build(BuildContext context) {
    final e = controller.experiment;
    if (e == null) return const SizedBox.shrink();
    final done = controller.experimentFinished;
    final progress = (controller.generation / e.generations).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Container(
        width: 260,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: Neon.panelDecoration(radius: 10).copyWith(border: Border.all(color: Neon.magenta.withValues(alpha: 0.6))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.science_rounded,
                  size: 14,
                  color: Neon.magenta,
                  shadows: [Shadow(color: Neon.magenta, blurRadius: 8)],
                ),
                const SizedBox(width: 6),
                Text('EXPERIMENT ${e.number}', style: Neon.mono.copyWith(color: Neon.magenta, letterSpacing: 1.5)),
                const Spacer(),
                Text(
                  done ? 'DONE' : 'GEN ${controller.generation} / ${e.generations}',
                  style: Neon.mono.copyWith(color: done ? Neon.amber : Neon.text, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: Neon.magenta,
                backgroundColor: Neon.magenta.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              done ? 'This is where Claude\'s test run ended.' : 'Replaying Claude\'s test run, ${e.rate.round()} gen/s',
              style: Neon.mono.copyWith(color: Neon.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
