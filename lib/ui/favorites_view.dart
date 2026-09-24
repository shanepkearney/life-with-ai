import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/favorites.dart';
import '../app/life_controller.dart';
import '../app/share_link.dart';
import 'seed_thumbnail.dart';
import 'theme.dart';
import 'toasts.dart';

/// Hearted seeds, shown in the assistant panel in place of the chat. Clicking
/// a card plays it on the board straight away; the list stays open, so it
/// browses like a gallery.
class FavoritesView extends StatefulWidget {
  const FavoritesView({super.key, required this.favorites, required this.life});

  final FavoritesStore favorites;
  final LifeController life;

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  String? _playing;

  Future<void> _play(Favorite f) async {
    setState(() => _playing = f.code);
    await widget.life.playSeed(f.seed, title: f.title);
  }

  Future<void> _copyLink(Favorite f) async {
    final link = ShareLink.forSeed(f.seed, title: f.title);
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
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No favourites yet. When Claude finishes a seed you like, tap the heart on its summary card '
              'and it will be kept here, on this device.',
              style: Neon.mono.copyWith(color: Neon.muted, height: 1.5),
            ),
          );
        }
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: items.length, itemBuilder: (context, i) => _card(items[i]));
      },
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
