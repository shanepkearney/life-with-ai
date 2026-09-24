/// Which build this is. Release builds get these from CI at compile time
/// (`--dart-define=APP_VERSION=1.2.0 --dart-define=APP_COMMIT=a1b2c3d`, see
/// .github/workflows/pages.yml); anything built locally is `dev`.
abstract final class BuildInfo {
  static const version = String.fromEnvironment('APP_VERSION');
  static const commit = String.fromEnvironment('APP_COMMIT');

  static const repo = 'shanepkearney/life-with-ai';

  static String get label => labelFor(version, commit);
  static Uri? get releaseUrl => releaseUrlFor(version);

  /// `v1.2.0 · a1b2c3d`, `v1.2.0` without a commit, or `dev` for a local build.
  static String labelFor(String version, String commit) {
    if (version.isEmpty) return 'dev';
    return commit.isEmpty ? 'v$version' : 'v$version · ${commit.length > 7 ? commit.substring(0, 7) : commit}';
  }

  /// The GitHub Release for [version]; a local build has none.
  static Uri? releaseUrlFor(String version) => version.isEmpty ? null : Uri.https('github.com', '/$repo/releases/tag/v$version');
}
