import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/downloads.dart';
import 'about_modal.dart';
import 'theme.dart';

/// "Life with AI for macOS": the download, and how to open an app that isn't
/// signed with an Apple Developer ID yet (macOS asks once).
Future<void> showMacDownloadDialog(BuildContext context, {OpenUrl openUrl = openExternal}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: Colors.black.withValues(alpha: 0.25),
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, _) => _MacDownloadPanel(openUrl: openUrl),
  transitionBuilder: (context, anim, _, child) => FadeTransition(
    opacity: anim,
    child: ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: child,
    ),
  ),
);

class _MacDownloadPanel extends StatelessWidget {
  const _MacDownloadPanel({required this.openUrl});

  final OpenUrl openUrl;

  static const steps = [
    'Open Life-with-AI.dmg and drag Life with AI into Applications.',
    "Open the app. macOS says it can't verify it: click Done.",
    'In System Settings → Privacy & Security, scroll down and click Open Anyway, then confirm. From then on it opens like any other app.',
  ];

  @override
  Widget build(BuildContext context) {
    final body = Neon.mono.copyWith(fontSize: 12.5, height: 1.55);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 12, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Life with AI for macOS',
                                style: Neon.mono.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: Neon.cyan),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            'The whole app, running natively: Apple silicon and Intel, macOS 10.15 or later.',
                            style: body.copyWith(color: Neon.muted),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => openUrl(Downloads.macDmg),
                          style: FilledButton.styleFrom(backgroundColor: Neon.magenta, foregroundColor: Colors.white),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text('Download for macOS', style: Neon.mono.copyWith(fontSize: 12.5, color: null)),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'OPENING IT THE FIRST TIME',
                          style: Neon.mono.copyWith(fontSize: 11, color: Neon.cyan, letterSpacing: 2),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(right: 12, bottom: 6),
                          child: Text(
                            "The app isn't signed with an Apple Developer ID yet, so macOS asks you to allow it once:",
                            style: body.copyWith(color: Neon.muted),
                          ),
                        ),
                        for (final (i, step) in steps.indexed)
                          Padding(
                            padding: const EdgeInsets.only(right: 12, bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: Text('${i + 1}.', style: body.copyWith(color: Neon.magenta, fontWeight: FontWeight.bold)),
                                ),
                                Expanded(child: Text(step, style: body)),
                              ],
                            ),
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
