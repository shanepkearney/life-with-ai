import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/community.dart';
import '../app/community_submit.dart';
import '../app/favorites.dart';
import '../app/life_controller.dart';
import '../app/screenshot/save_png.dart';
import '../app/telemetry.dart';
import '../core/seed_codec.dart';
import 'about_modal.dart';
import 'seed_thumbnail.dart';
import 'theme.dart';
import 'toasts.dart';

/// Seeds other people found, contributed by pull request and credited to
/// their GitHub. Browses like Favorites: click a card to play it.
class CommunityView extends StatefulWidget {
  const CommunityView({super.key, required this.seeds, required this.favorites, required this.life, this.openUrl = openExternal, this.saveFile = saveDownload});

  final List<CommunitySeed> seeds;
  final FavoritesStore favorites;
  final LifeController life;
  final OpenUrl openUrl;

  /// Where Download puts the file: the browser's downloads, or ~/Downloads.
  final Future<SavedPng?> Function(Uint8List bytes, String fileName, String mimeType) saveFile;

  @override
  State<CommunityView> createState() => _CommunityViewState();
}

class _CommunityViewState extends State<CommunityView> {
  CommunitySeed? _playing;

  Future<void> _play(CommunitySeed s) async {
    setState(() => _playing = s);
    // Too big for any board, or sending things out that would wrap around and wreck it: the endless plane.
    if (s.playsOnPlane) return widget.life.openGiant(s.pattern);
    await widget.life.playSeed(s.seed!.copy(), title: s.name, source: SeedSource.community, communityName: s.name);
  }

  Future<void> _copyLink(CommunitySeed s) async {
    await Clipboard.setData(ClipboardData(text: s.shareLink!));
    if (mounted) Toasts.show(context, 'Link copied. Anyone who opens it sees this seed play.');
  }

  /// The file itself, as committed: standard RLE that Golly and LifeViewer open.
  Future<void> _download(CommunitySeed s) async {
    final name = CommunitySeed.fileNameFor(s.name);
    final saved = await widget.saveFile(Uint8List.fromList(utf8.encode(s.rle)), name, 'application/x-life');
    if (!mounted) return;
    Toasts.show(context, saved == null ? "Downloads can't be saved on this device yet." : 'Saved $name to ${saved.label}');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.favorites,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _intro(),
        if (widget.seeds.isEmpty)
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text('No community seeds yet. Yours could be the first.', style: Neon.mono.copyWith(color: Neon.muted)),
          )
        else
          for (final s in widget.seeds) _card(s),
      ],
    ),
  );

  Widget _intro() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Seeds people found and shared. Found a good one? Heart it, then use the submit button on its card in '
          'Favorites to send it in with a pull request, with credit to your GitHub.',
          style: Neon.mono.copyWith(fontSize: 11, color: Neon.muted, height: 1.5),
        ),
        TextButton.icon(
          onPressed: () => widget.openUrl(CommunitySubmit.contributing),
          style: TextButton.styleFrom(foregroundColor: Neon.cyan, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
          icon: const Icon(Icons.open_in_new_rounded, size: 14),
          label: Text('How to contribute', style: Neon.mono.copyWith(fontSize: 11, color: Neon.cyan)),
        ),
      ],
    ),
  );

  Widget _card(CommunitySeed s) {
    final playing = identical(_playing, s);
    final seed = s.seed;
    // A favorite is a board: only patterns that play on one can be kept as one.
    final board = s.playsOnPlane ? null : seed;
    final saved = board != null && widget.favorites.contains(SeedCodec.encode(board));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _play(s),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: playing ? Neon.magenta : Neon.border),
              color: playing ? Neon.magenta.withValues(alpha: 0.08) : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (seed != null) SeedThumbnail(seed) else const _GiantThumbnail(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: Neon.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      // The credit: a link to the finder's GitHub profile.
                      // A classic credits its discoverer and where it came from.
                      if (s.discoveredElsewhere)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text('Found by ${s.discoverer}', style: Neon.mono.copyWith(fontSize: 10.5, color: Neon.text)),
                        ),
                      if (s.playsOnPlane)
                        Text('∞ Plays on the endless plane', style: Neon.mono.copyWith(fontSize: 10, color: Neon.cyan)),
                      Semantics(
                        link: true,
                        label: '${s.discoveredElsewhere ? 'Added by' : 'By'} ${s.author}, on GitHub',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => widget.openUrl(s.authorUrl),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: s.discoveredElsewhere ? 'added by ' : 'by ',
                                    style: Neon.mono.copyWith(fontSize: 10.5, color: Neon.muted),
                                  ),
                                  TextSpan(
                                    text: '@${s.author}',
                                    style: Neon.mono.copyWith(fontSize: 10.5, color: Neon.cyan),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (s.prompt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('“${s.prompt}”', style: Neon.mono.copyWith(fontSize: 10.5, fontStyle: FontStyle.italic, height: 1.4)),
                        ),
                      const SizedBox(height: 4),
                      Text(s.description, style: Neon.mono.copyWith(fontSize: 10, color: Neon.muted, height: 1.45)),
                      Row(
                        children: [
                          Expanded(
                            child: Text(playing ? '▶ Playing on the board' : '', style: Neon.mono.copyWith(fontSize: 10, color: Neon.magenta)),
                          ),
                          // A giant is too big to keep as a favorite or send as a link; the file travels instead.
                          if (board != null)
                            IconButton(
                              tooltip: saved ? 'Remove from favorites' : 'Add to favorites',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => widget.favorites.toggle(board, title: s.name, summary: s.description),
                              icon: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 16, color: Neon.magenta),
                            ),
                          if (s.source case final source?)
                            IconButton(
                              tooltip: 'Where it came from: ${source.host}${s.license != null ? ' · ${s.license}' : ''}',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => widget.openUrl(source),
                              icon: const Icon(Icons.menu_book_rounded, size: 16),
                            ),
                          IconButton(
                            tooltip: 'Download .rle',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _download(s),
                            icon: const Icon(Icons.download_rounded, size: 16),
                          ),
                          if (s.shareLink != null)
                            IconButton(
                              tooltip: 'Copy share link',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _copyLink(s),
                              icon: const Icon(Icons.link_rounded, size: 16),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stands in for a thumbnail when a pattern is too big to draw as one.
class _GiantThumbnail extends StatelessWidget {
  const _GiantThumbnail();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Too big for a board: it runs on the endless plane',
    child: Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Neon.border),
        color: Colors.black,
      ),
      child: const Icon(Icons.all_inclusive_rounded, color: Neon.cyan, size: 26),
    ),
  );
}
