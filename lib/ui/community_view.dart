import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/community.dart';
import '../app/community_submit.dart';
import '../app/favorites.dart';
import '../app/life_controller.dart';
import '../core/seed_codec.dart';
import 'about_modal.dart';
import 'seed_thumbnail.dart';
import 'theme.dart';
import 'toasts.dart';

/// Seeds other people found, contributed by pull request and credited to
/// their GitHub. Browses like Favorites: click a card to play it.
class CommunityView extends StatefulWidget {
  const CommunityView({super.key, required this.seeds, required this.favorites, required this.life, this.openUrl = openExternal});

  final List<CommunitySeed> seeds;
  final FavoritesStore favorites;
  final LifeController life;
  final OpenUrl openUrl;

  @override
  State<CommunityView> createState() => _CommunityViewState();
}

class _CommunityViewState extends State<CommunityView> {
  CommunitySeed? _playing;

  Future<void> _play(CommunitySeed s) async {
    setState(() => _playing = s);
    await widget.life.playSeed(s.seed.copy(), title: s.name);
  }

  Future<void> _copyLink(CommunitySeed s) async {
    await Clipboard.setData(ClipboardData(text: s.shareLink));
    if (mounted) Toasts.show(context, 'Link copied. Anyone who opens it sees this seed play.');
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
    final saved = widget.favorites.contains(SeedCodec.encode(s.seed));
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
                SeedThumbnail(s.seed),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: Neon.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      // The credit: a link to the finder's GitHub profile.
                      Semantics(
                        link: true,
                        label: 'By ${s.author}, on GitHub',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => widget.openUrl(s.authorUrl),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'by ',
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
                            child: Text(
                              playing ? '▶ Playing on the board' : '',
                              style: Neon.mono.copyWith(fontSize: 10, color: Neon.magenta),
                            ),
                          ),
                          IconButton(
                            tooltip: saved ? 'Remove from favorites' : 'Add to favorites',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => widget.favorites.toggle(s.seed, title: s.name, summary: s.description),
                            icon: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 16, color: Neon.magenta),
                          ),
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
