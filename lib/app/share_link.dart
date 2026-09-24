import '../core/grid.dart';
import '../core/seed_codec.dart';
import '../render/board_palette.dart';

/// What a share link carries: the seed, and optionally the prompt that made it,
/// a note about it (Claude's summary, or a favorite's description) and the
/// sender's board colors.
typedef SharedSeed = ({Grid seed, String? title, String? note, BoardPalette? palette});

/// Share links carry the whole seed in the URL fragment:
/// `…/#seed=<code>&title=<prompt>&colors=<palette>&note=<description>`.
/// `colors` is left out only by callers with no palette to give (community seeds).
///
/// The fragment is never sent to the server, so GitHub Pages can't reject a
/// long link (servers refuse URLs past ~8 KB) and shared seeds stay out of
/// server logs. Claude's designs encode to a few hundred characters.
abstract final class ShareLink {
  static final site = Uri.parse('https://shanepkearney.github.io/life-with-ai/');

  /// Some chat apps truncate links beyond roughly this length.
  static const comfortableLength = 2000;

  /// Titles are the sender's prompt; keep links reasonable even for long ones.
  static const maxTitleLength = 160;

  /// Notes are longer than titles, but never at the seed's expense.
  static const maxNoteLength = 400;

  /// The seed always travels whole. A note only fills whatever room is left
  /// under [comfortableLength], shortened with an ellipsis to fit, and is
  /// dropped when the seed (and title) already use it all.
  static String forSeed(Grid seed, {String? title, String? note, BoardPalette? palette}) {
    final colors = palette?.linkForm;
    final base = _link({
      'seed': SeedCodec.encode(seed),
      if (title != null && title.trim().isNotEmpty) 'title': _clean(title),
      'colors': ?colors,
    });
    final text = note == null ? '' : _clean(note, maxNoteLength);
    if (text.isEmpty) return base;
    final room = comfortableLength - base.length - '&note='.length;
    // Percent-encoding makes the encoded length uneven, so search for the longest prefix that fits.
    var lo = 0, hi = text.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_encodedLength(_shorten(text, mid)) <= room) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    // Cut down to a stub of a few words, a note says less than no note at all.
    if (lo < text.length && lo < 24) return base;
    return '$base&note=${Uri.encodeQueryComponent(_shorten(text, lo))}';
  }

  // Encoded by hand: Uri's `fragment` would leave `&`/`=` inside a title unescaped.
  static String _link(Map<String, String> params) =>
      '$site#${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';

  static int _encodedLength(String s) => Uri.encodeQueryComponent(s).length;

  /// [s] cut to [n] characters, the last one an ellipsis when anything was cut.
  static String _shorten(String s, int n) => n >= s.length ? s : '${s.substring(0, n - 1).trimRight()}…';

  /// Whether [uri] was meant to share a seed (it has a `seed=` in its
  /// fragment), whether or not that seed is any good. Tells a broken link
  /// apart from an ordinary visit.
  static bool carriesSeed(Uri uri) {
    try {
      return Uri.splitQueryString(uri.fragment).containsKey('seed');
    } on ArgumentError {
      return RegExp(r'(^|&)seed=').hasMatch(uri.fragment);
    }
  }

  /// The seed (and title) in [uri]'s fragment, or null without a valid seed.
  /// Links are untrusted input: the seed is fully validated and the title is
  /// cleaned and capped. A bad title never costs you the seed.
  static SharedSeed? parse(Uri uri) {
    final Map<String, String> params;
    try {
      params = Uri.splitQueryString(uri.fragment);
    } on ArgumentError {
      return null;
    }
    final code = params['seed'];
    final seed = code == null ? null : SeedCodec.tryDecode(code);
    if (seed == null) return null;
    String? text(String key, int max) {
      final value = params[key] == null ? null : _clean(params[key]!, max);
      return value == null || value.isEmpty ? null : value;
    }

    return (seed: seed, title: text('title', maxTitleLength), note: text('note', maxNoteLength), palette: BoardPalette.fromWire(params['colors']));
  }

  /// Plain text only: no control characters or line breaks, capped in length.
  static String _clean(String s, [int max = maxTitleLength]) {
    final flat = s.replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= max ? flat : '${flat.substring(0, max - 1)}…';
  }
}
