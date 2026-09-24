import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glider_loader.dart';
import 'theme.dart';

/// Shown when the app was opened from a seed link that couldn't be used:
/// says what happened, then offers the Community tab or just carrying on
/// with the random board already playing behind it.
Future<void> showBrokenLinkDialog(BuildContext context, {required VoidCallback onExplore}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: Colors.black.withValues(alpha: 0.25),
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, _) => _BrokenLinkPanel(onExplore: onExplore),
  transitionBuilder: (context, anim, _, child) => FadeTransition(
    opacity: anim,
    child: ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: child,
    ),
  ),
);

class _BrokenLinkPanel extends StatelessWidget {
  const _BrokenLinkPanel({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final body = Neon.mono.copyWith(fontSize: 12.5, height: 1.55);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Material(
                  color: const Color(0xB30B0E17),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Neon.cyan.withValues(alpha: 0.25)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // A glider that got lost on the way: the loader, flying nowhere in particular.
                        const GliderLoader(size: 44, showAfter: Duration.zero),
                        const SizedBox(height: 16),
                        Text(
                          "This seed didn't make it",
                          textAlign: TextAlign.center,
                          style: Neon.mono.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: Neon.cyan),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'The link is broken or incomplete. It may have been cut off when it was shared. '
                          "Here's a random board instead, or explore seeds other people have found.",
                          textAlign: TextAlign.center,
                          style: body,
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(foregroundColor: Neon.muted),
                              child: Text('Just play', style: Neon.mono.copyWith(fontSize: 12, color: null)),
                            ),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onExplore();
                              },
                              style: FilledButton.styleFrom(backgroundColor: Neon.magenta, foregroundColor: Colors.white),
                              icon: const Icon(Icons.public_rounded, size: 16),
                              label: Text('Explore community seeds', style: Neon.mono.copyWith(fontSize: 12, color: null)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
