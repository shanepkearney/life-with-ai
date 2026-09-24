import '../core/grid.dart';
import '../core/seed_codec.dart';

/// What a share link carries: the seed, and optionally the prompt that made it.
typedef SharedSeed = ({Grid seed, String? title});

/// Share links carry the whole seed in the URL fragment:
/// `…/#seed=<code>&title=<prompt>`.
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

  static String forSeed(Grid seed, {String? title}) {
    final params = {'seed': SeedCodec.encode(seed), if (title != null && title.trim().isNotEmpty) 'title': _clean(title)};
    // Encoded by hand: Uri's `fragment` would leave `&`/`=` inside a title unescaped.
    final fragment = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return '$site#$fragment';
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
    final title = params['title'] == null ? null : _clean(params['title']!);
    return (seed: seed, title: title == null || title.isEmpty ? null : title);
  }

  /// Plain text only: no control characters or line breaks, capped in length.
  static String _clean(String s) {
    final flat = s.replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= maxTitleLength ? flat : '${flat.substring(0, maxTitleLength - 1)}…';
  }
}
