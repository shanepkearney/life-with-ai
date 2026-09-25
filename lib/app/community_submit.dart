import 'favorites.dart';
import 'community.dart';

/// Where a favorite goes to become a community seed: GitHub's "new file"
/// page in `community/seeds/`, pre-filled with its entry. For someone without
/// write access GitHub forks the repo and opens the pull request itself.
abstract final class CommunitySubmit {
  static const repo = 'shanepkearney/life-with-ai';
  static final contributing = Uri.https('github.com', '/$repo/blob/main/CONTRIBUTING.md');
  static const authorPlaceholder = 'your-github-username';

  /// Past this, GitHub refuses the URL, so the entry goes by clipboard instead.
  static const maxUrlLength = 6000;

  static String entryFor(Favorite f, {DateTime? now}) {
    final title = f.title.trim();
    return CommunitySeed.entryRle(
      name: title.isNotEmpty && title.length <= CommunitySeed.maxName ? title : 'Name your seed',
      author: authorPlaceholder,
      added: now ?? DateTime.now(),
      // Claude's descriptions can run past what the entry allows: cut at a sentence, so the file passes its checks.
      description: f.linkNote == null ? 'Describe what it does as it plays.' : clip(f.linkNote!, CommunitySeed.maxDescription),
      // A favorite's title is the prompt it was made from, when Claude made it.
      prompt: f.linkNote != null && title.length <= CommunitySeed.maxPrompt ? title : null,
      seed: f.seed,
      rule: f.rule,
    );
  }

  /// [text] cut to at most [max] characters: at the last sentence that fits,
  /// else at a word, marked with "…".
  static String clip(String text, int max) {
    final t = text.trim();
    if (t.length <= max) return t;
    final head = t.substring(0, max);
    final sentence = head.lastIndexOf(RegExp(r'[.!?](\s|$)'));
    if (sentence > max ~/ 2) return head.substring(0, sentence + 1);
    final word = head.substring(0, max - 1).lastIndexOf(' ');
    return '${head.substring(0, word > 0 ? word : max - 1).trimRight()}…';
  }

  /// The page to open, and whether the entry is in it (else: paste it).
  static ({Uri url, bool prefilled}) urlFor(Favorite f, String entry) {
    // The file is named after the entry's #N line: the favorite's title, or the "Name your seed"
    // placeholder when that won't do (a long prompt), so the two match until someone renames one.
    final title = f.title.trim();
    final fileName = CommunitySeed.fileNameFor(title.isNotEmpty && title.length <= CommunitySeed.maxName ? title : 'Name your seed');
    Uri page({String? value}) => Uri.https('github.com', '/$repo/new/main/community/seeds', {
      'filename': fileName == '.rle' ? 'name-your-seed.rle' : fileName,
      'value': ?value,
    });
    final full = page(value: entry);
    return full.toString().length <= maxUrlLength ? (url: full, prefilled: true) : (url: page(), prefilled: false);
  }
}
