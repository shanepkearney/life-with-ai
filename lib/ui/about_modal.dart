import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/build_info.dart';
import 'theme.dart';

/// Who made this, and whose rules it runs. Opened from the logo or the ⓘ
/// beside it: a frosted-glass panel over the board, closed by the ✕, a tap
/// outside, or Esc.
abstract final class About {
  static const author = 'Shane Kearney';
  static final authorGitHub = Uri.parse('https://github.com/shanepkearney');

  static const authorLinkedIn = 'https://www.linkedin.com/in/shanepkearney/';
  static final repo = Uri.parse('https://github.com/shanepkearney/life-with-ai');
  static final original = Uri.parse('https://github.com/shanepkearney/life');
  static final wikipedia = Uri.parse('https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life');
  static final lifeWiki = Uri.parse('https://conwaylife.com/wiki/Conway%27s_Game_of_Life');
}

typedef OpenUrl = Future<void> Function(Uri url);

/// What the Game of Life shows, in three lines: kept short so the panel stays scannable.
const _lessons = [
  ('Simple rules, complex worlds.', 'Two rules are enough for gliders, glider guns, even a working computer.'),
  (
    'Beginnings matter.',
    'One cell\'s difference can decide whether a pattern dies out, freezes, or grows forever: the butterfly effect in miniature.',
  ),
  ('Chaos settles into order.', 'Left to run, most random boards calm down into still lifes, oscillators and gliders.'),
];

/// New tab on the web, the default browser on desktop.
Future<void> openExternal(Uri url) async {
  await launchUrl(url, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
}

Future<void> showAboutModal(BuildContext context, {OpenUrl openUrl = openExternal}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close about',
  barrierColor: Colors.black.withValues(alpha: 0.25),
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, _) => _AboutPanel(openUrl: openUrl),
  transitionBuilder: (context, anim, _, child) => FadeTransition(
    opacity: anim,
    child: ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: child,
    ),
  ),
);

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({required this.openUrl});

  final OpenUrl openUrl;

  @override
  Widget build(BuildContext context) {
    final body = Neon.mono.copyWith(fontSize: 12.5, height: 1.55);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(text, style: Neon.mono.copyWith(fontSize: 11, color: Neon.cyan, letterSpacing: 2)),
    );
    Widget link(String label, Uri url) => Padding(
      padding: const EdgeInsets.only(right: 8, top: 2),
      child: TextButton.icon(
        onPressed: () => openUrl(url),
        style: TextButton.styleFrom(
          foregroundColor: Neon.magenta,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: const Icon(Icons.open_in_new_rounded, size: 14),
        label: Text(label, style: Neon.mono.copyWith(fontSize: 12, color: Neon.magenta)),
      ),
    );

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              // Frosted glass: the board stays visible, blurred, behind the panel.
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Material(
                  color: const Color(0xB30B0E17),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Neon.cyan.withValues(alpha: 0.25)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 12, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // The logo shrinks to fit rather than push the ✕ off a narrow phone.
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'LIFE',
                                      style: Neon.mono.copyWith(
                                        fontSize: 20,
                                        letterSpacing: 6,
                                        color: Neon.cyan,
                                        shadows: const [Shadow(color: Neon.cyan, blurRadius: 14)],
                                      ),
                                    ),
                                    Text(
                                      ' with AI',
                                      style: Neon.mono.copyWith(
                                        fontSize: 20,
                                        color: Neon.magenta,
                                        shadows: const [Shadow(color: Neon.magenta, blurRadius: 14)],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _VersionTag(openUrl: openUrl),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        // A byline, like an article's: the credit comes first, without a whole
                        // section standing between the reader and "what is this?".
                        const SizedBox(height: 20), // breathing room under the logo
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Created By ',
                                style: body.copyWith(color: Neon.cyan, letterSpacing: 0.5),
                              ),
                              TextSpan(
                                text: About.author,
                                style: body.copyWith(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        // The links get their own line, so none is stranded on a wrap.
                        Wrap(
                          children: [
                            link('GitHub', About.authorGitHub),
                            if (About.authorLinkedIn.isNotEmpty) link('LinkedIn', Uri.parse(About.authorLinkedIn)),
                            link('Source code', About.repo),
                          ],
                        ),
                        heading('ABOUT'),
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            "Conway's Game of Life has always been a place to experiment: set a few cells, press play, and "
                            'see what grows. Life with AI makes those experiments easy to share. Every seed becomes a link, '
                            'and anyone who opens it, on a phone or in a browser, watches it unfold with no install or account.',
                            style: body,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            "It also lets AI take a turn at the seeds. Describe what you'd like to see, and Claude designs a "
                            'starting pattern, tests it, and refines it until the board does what you imagined. Bring your own '
                            "Claude account to create, share the results with everyone, or just have fun with Conway's Game of "
                            'Life — with AI.',
                            style: body,
                          ),
                        ),
                        heading("CONWAY'S GAME OF LIFE"),
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            'The rules are the cellular automaton devised by mathematician John Horton Conway in 1970. '
                            'Each cell lives or dies by its eight neighbors: a dead cell with exactly 3 comes alive, '
                            'and a live cell with 2 or 3 survives (B3/S23). The board wraps at its edges.',
                            style: body,
                          ),
                        ),
                        Wrap(children: [link('Wikipedia', About.wikipedia), link('LifeWiki', About.lifeWiki)]),
                        heading('KEY LESSONS TO TAKE FROM IT'),
                        for (final (lead, rest) in _lessons)
                          Padding(
                            padding: const EdgeInsets.only(right: 10, bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 7, right: 10),
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(color: Neon.magenta, shape: BoxShape.circle),
                                  ),
                                ),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '$lead ',
                                          style: body.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                        TextSpan(
                                          text: rest,
                                          style: body.copyWith(color: Neon.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        heading('ORIGINS'),
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text('The earlier Java/Swing version this grew from:', style: body),
                        ),
                        Wrap(children: [link('The original', About.original)]),
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

/// Which build this is, e.g. `v1.2.0 · a1b2c3d`, linked to its GitHub Release.
/// A local build says `dev` and links nowhere.
class _VersionTag extends StatelessWidget {
  const _VersionTag({required this.openUrl});

  final OpenUrl openUrl;

  @override
  Widget build(BuildContext context) {
    final url = BuildInfo.releaseUrl;
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Neon.border),
      ),
      child: Text(BuildInfo.label, style: Neon.mono.copyWith(fontSize: 11, color: Neon.muted)),
    );
    if (url == null) return Tooltip(message: 'A local build', child: tag);
    return Tooltip(
      message: 'Release notes',
      child: InkWell(borderRadius: BorderRadius.circular(6), onTap: () => openUrl(url), child: tag),
    );
  }
}

/// The logo, clickable, with an ⓘ beside it. Both open [showAboutModal].
class LogoButton extends StatelessWidget {
  const LogoButton({super.key, this.size = 18, this.letterSpacing = 6});

  final double size;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        label: 'About Life with AI',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => showAboutModal(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LIFE',
                  style: Neon.mono.copyWith(
                    fontSize: size,
                    letterSpacing: letterSpacing,
                    color: Neon.cyan,
                    shadows: const [Shadow(color: Neon.cyan, blurRadius: 14)],
                  ),
                ),
                Text(
                  ' with AI',
                  style: Neon.mono.copyWith(
                    fontSize: size,
                    color: Neon.magenta,
                    shadows: const [Shadow(color: Neon.magenta, blurRadius: 14)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: 'About this app',
        visualDensity: VisualDensity.compact,
        onPressed: () => showAboutModal(context),
        icon: Icon(Icons.info_outline_rounded, size: size, color: Neon.muted),
      ),
    ],
  );
}
