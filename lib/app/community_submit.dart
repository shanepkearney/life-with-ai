import 'favorites.dart';
import 'community.dart';
import 'share_link.dart';

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
    return CommunitySeed.entryJson(
      name: title.isNotEmpty && title.length <= CommunitySeed.maxName ? title : 'Name your seed',
      author: authorPlaceholder,
      added: now ?? DateTime.now(),
      description: f.linkNote ?? 'Describe what it does as it plays.',
      // A favorite's title is the prompt it was made from, when Claude made it.
      prompt: f.linkNote != null && title.length <= CommunitySeed.maxPrompt ? title : null,
      link: ShareLink.forSeed(f.seed),
    );
  }

  /// The page to open, and whether the entry is in it (else: paste it).
  static ({Uri url, bool prefilled}) urlFor(Favorite f, String entry) {
    final name = f.title.trim().length <= CommunitySeed.maxName ? f.title : 'my-seed';
    final fileName = CommunitySeed.fileNameFor(name);
    Uri page({String? value}) => Uri.https('github.com', '/$repo/new/main/community/seeds', {
      'filename': fileName == '.json' ? 'my-seed.json' : fileName,
      'value': ?value,
    });
    final full = page(value: entry);
    return full.toString().length <= maxUrlLength ? (url: full, prefilled: true) : (url: page(), prefilled: false);
  }
}
