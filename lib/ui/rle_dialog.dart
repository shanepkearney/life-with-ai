import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/life_controller.dart';
import '../app/share_link.dart';
import '../core/grid.dart';
import '../core/rle.dart';
import 'theme.dart';

/// The board as RLE, the text form Golly, LifeViewer and the ConwayLife
/// forums use: copy it out, or paste a pattern over it and load it. The board
/// pauses while it's open, so what you copy is what you saw; it plays on
/// afterwards if it was playing.
///
/// Returns what was loaded (its `#N` name, or "Pasted pattern"), or null.
Future<String?> showRleDialog(BuildContext context, LifeController life) async {
  final wasRunning = life.running;
  if (wasRunning) life.toggleRunning();
  // A giant pattern isn't a board to export; the box starts empty, ready for a paste.
  final moment = life.giant != null ? null : await life.captureMoment();
  final text = moment == null || moment.seed.population == 0
      ? ''
      : Rle.encode(moment.seed, name: life.boardTitle, comments: _comments(life, moment.seed));
  if (!context.mounted) return null;
  final loaded = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.25),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => _RlePanel(life: life, initial: text),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
  if (loaded == null && wasRunning && !life.running) life.toggleRunning();
  return loaded;
}

/// Where the board came from, as `#C` lines: the generation, and a link that
/// opens this exact board in the app (when it's short enough to paste).
List<String> _comments(LifeController life, Grid seed) {
  final link = ShareLink.forSeed(seed, title: life.boardTitle);
  return [
    'Generation ${life.generation} on a ${life.boardSize.width}x${life.boardSize.height} board.',
    if (link.length <= ShareLink.comfortableLength) 'Open it in Life with AI: $link' else 'Made with Life with AI: ${ShareLink.site}',
  ];
}

class _RlePanel extends StatefulWidget {
  const _RlePanel({required this.life, required this.initial});

  final LifeController life;
  final String initial;

  @override
  State<_RlePanel> createState() => _RlePanelState();
}

class _RlePanelState extends State<_RlePanel> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;
  bool _copied = false;
  Timer? _copiedTimer;

  static const _example = '#N Glider\nx = 3, y = 3, rule = B3/S23\nbob\$2bo\$3o!';

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _load() async {
    RlePattern pattern;
    var giant = false;
    try {
      pattern = Rle.decode(_text.text);
    } on RleTooBig {
      // Too big for any board: read it again for HashLife's endless plane.
      try {
        pattern = Rle.decode(_text.text, unbounded: true);
        giant = true;
      } on RleTooBig catch (e) {
        return setState(() => _error = _tooBig(e.width, e.height));
      } on FormatException catch (e) {
        return setState(() => _error = e.message);
      }
    } on FormatException catch (e) {
      return setState(() => _error = e.message);
    }
    if (!giant) giant = !await widget.life.playPattern(pattern);
    if (giant) await widget.life.openGiant(pattern);
    if (!mounted) return;
    Navigator.of(context).pop(pattern.name ?? 'Pasted pattern');
  }

  /// Too big even for the endless plane: say how big, and what can run it.
  static String _tooBig(int width, int height) =>
      'This pattern is ${_n(width)} × ${_n(height)} cells, too big even for the endless plane '
      '(${_n(Rle.maxSideUnbounded)} cells across). Golly may manage it.';

  /// 12699 as "12,699".
  static String _n(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final body = Neon.mono.copyWith(fontSize: 12, height: 1.5, color: Neon.muted);
    final empty = widget.initial.isEmpty;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Pattern as RLE',
                                style: Neon.mono.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: Neon.cyan),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded, color: Neon.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          empty
                              ? 'The board is empty. Paste a pattern in RLE, the format Golly, LifeViewer and the LifeWiki use, and load it.'
                              : 'The board as RLE, the format Golly, LifeViewer and the LifeWiki use. '
                                    'Copy it, or paste a pattern over it and load it.',
                          style: body,
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: TextField(
                            controller: _text,
                            autofocus: empty,
                            minLines: 6,
                            maxLines: 12,
                            keyboardType: TextInputType.multiline,
                            style: Neon.mono.copyWith(fontSize: 11.5, height: 1.4),
                            onChanged: (_) {
                              if (_error != null) setState(() => _error = null);
                            },
                            decoration: InputDecoration(
                              hintText: _example,
                              hintStyle: Neon.mono.copyWith(fontSize: 11.5, height: 1.4, color: Neon.muted.withValues(alpha: 0.6)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, style: Neon.mono.copyWith(fontSize: 12, height: 1.45, color: Neon.amber)),
                        ],
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _copy,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Neon.cyan,
                                side: BorderSide(color: Neon.cyan.withValues(alpha: 0.5)),
                              ),
                              icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 16),
                              label: Text(_copied ? 'Copied' : 'Copy', style: Neon.mono.copyWith(fontSize: 12, color: null)),
                            ),
                            FilledButton.icon(
                              onPressed: _load,
                              style: FilledButton.styleFrom(backgroundColor: Neon.magenta, foregroundColor: Colors.white),
                              icon: const Icon(Icons.play_arrow_rounded, size: 18),
                              label: Text('Load', style: Neon.mono.copyWith(fontSize: 12, color: null)),
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
