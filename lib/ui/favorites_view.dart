import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/favorites.dart';
import '../app/life_controller.dart';
import '../app/share_link.dart';
import '../core/grid.dart';
import '../core/seed_codec.dart';
import 'seed_thumbnail.dart';
import 'theme.dart';
import 'toasts.dart';

/// Hearted seeds, shown in the assistant panel in place of the chat. Clicking
/// a card plays it on the board straight away; the list stays open, so it
/// browses like a gallery.
class FavoritesView extends StatefulWidget {
  const FavoritesView({super.key, required this.favorites, required this.life, this.shared});

  final FavoritesStore favorites;
  final LifeController life;

  /// A seed the app was opened with from a share link: pinned above the list
  /// for this visit, with replay, save (its heart fills once saved) and copy-link.
  final SharedSeed? shared;

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  String? _playing;

  Future<void> _play(Favorite f) async {
    setState(() => _playing = f.code);
    await widget.life.playSeed(f.seed, title: f.title);
  }

  Future<void> _copyLink(Favorite f) => _copyLinkFor(f.seed, f.title);

  Future<void> _copyLinkFor(Grid seed, String title) async {
    final link = ShareLink.forSeed(seed, title: title);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    final long = link.length > ShareLink.comfortableLength;
    Toasts.show(
      context,
      long
          ? 'Link copied (${link.length} characters, so some chat apps may cut it off)'
          : 'Link copied. Anyone who opens it sees this seed play.',
    );
  }

  Future<void> _delete(Favorite f) async {
    await widget.favorites.remove(f);
    if (!mounted) return;
    // Undo instead of a confirm dialog: deleting is one click, and so is getting it back.
    Toasts.show(
      context,
      'Removed "${f.title}"',
      actionLabel: 'Undo',
      onAction: () => widget.favorites.toggle(f.seed, title: f.title, summary: f.summary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.favorites,
      builder: (context, _) {
        final items = widget.favorites.items;
        final shared = widget.shared;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (shared != null) _sharedCard(shared),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  'No favourites yet. When Claude finishes a seed you like, tap the heart on its summary card '
                  'and it will be kept here, on this device.',
                  style: Neon.mono.copyWith(color: Neon.muted, height: 1.5),
                ),
              )
            else
              for (final f in items) _card(f),
          ],
        );
      },
    );
  }

  /// The seed from the link the app was opened with.
  Widget _sharedCard(SharedSeed shared) {
    final title = shared.title ?? 'A seed shared with you';
    final saved = widget.favorites.contains(SeedCodec.encode(shared.seed));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Neon.cyan.withValues(alpha: 0.6)),
          color: Neon.cyan.withValues(alpha: 0.06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded, color: Neon.cyan, size: 16),
                const SizedBox(width: 8),
                Text('SHARED WITH YOU', style: Neon.mono.copyWith(fontSize: 10, color: Neon.cyan, letterSpacing: 1.5)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SeedThumbnail(shared.seed),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: Neon.mono.copyWith(fontSize: 12, height: 1.45))),
              ],
            ),
            Row(
              children: [
                IconButton(
                  tooltip: saved ? 'Remove from favourites' : 'Add to favourites',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.favorites.toggle(shared.seed, title: title, summary: 'Shared with you'),
                  icon: Icon(
                    saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 18,
                    color: Neon.magenta,
                    shadows: saved ? const [Shadow(color: Neon.magenta, blurRadius: 10)] : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy share link',
                  visualDensity: VisualDensity.compact,
                  color: Neon.cyan,
                  onPressed: () => _copyLinkFor(shared.seed, title),
                  icon: const Icon(Icons.link_rounded, size: 18),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => widget.life.playSeed(shared.seed.copy(), title: title),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: Text('Replay seed', style: Neon.mono.copyWith(fontSize: 11, color: null)),
                  style: TextButton.styleFrom(foregroundColor: Neon.magenta, visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Favorite f) {
    final playing = _playing == f.code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _play(f),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: playing ? Neon.magenta : Neon.border),
              color: playing ? Neon.magenta.withValues(alpha: 0.08) : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SeedThumbnail(f.seed),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Neon.mono.copyWith(fontSize: 12)),
                      if (f.summary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          f.summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Neon.mono.copyWith(fontSize: 10, color: Neon.muted, height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              playing ? '▶ Playing on the board' : _date(f.savedAt),
                              style: Neon.mono.copyWith(fontSize: 10, color: playing ? Neon.magenta : Neon.muted),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy share link',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _copyLink(f),
                            icon: const Icon(Icons.link_rounded, size: 16),
                          ),
                          IconButton(
                            tooltip: 'Remove from favourites',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _delete(f),
                            icon: const Icon(Icons.delete_outline_rounded, size: 16),
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

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${months[l.month - 1]} ${l.day}, ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
