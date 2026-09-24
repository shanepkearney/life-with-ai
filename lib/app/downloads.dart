/// Where the macOS app is downloaded from. Every GitHub Release carries it as
/// `Life-with-AI.dmg` (see .github/workflows/pages.yml), so the "latest" link
/// always serves the newest version.
abstract final class Downloads {
  static final macDmg = Uri.https('github.com', '/shanepkearney/life-with-ai/releases/latest/download/Life-with-AI.dmg');
}
