// Decides the version of the next deploy from the commits since the last
// release tag, following Conventional Commits:
//
//   feat: …                     → minor   (1.2.3 → 1.3.0)
//   fix: / docs: / chore: / …   → patch   (1.2.3 → 1.2.4)
//   feat!: … or BREAKING CHANGE → major   (1.2.3 → 2.0.0)
//
// With no release tag yet, the first release is 1.0.0. With no commits since
// the last tag (a re-run), it's that same version and nothing new is tagged.
//
//   dart tool/next_version.dart    # prints e.g. version=1.3.0 and tag=true
//
// (Plain `dart`, not `dart run`: the latter prints build-hook progress to stdout.)
//
// CI appends the output to $GITHUB_OUTPUT.
import 'dart:io';

enum Bump { none, patch, minor, major }

const firstVersion = '1.0.0';

final _tag = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$');
final _conventional = RegExp(r'^(\w+)(\([^)]*\))?(!)?:\s');

/// How much [message] (a whole commit message: subject, blank line, body) bumps the version.
Bump bumpFor(String message) {
  final lines = message.trim().split('\n');
  final subject = lines.first.trim();
  if (subject.isEmpty || subject.startsWith('Merge ')) return Bump.none; // the merged commits speak for themselves
  final m = _conventional.firstMatch(subject);
  if (m?.group(3) != null || lines.skip(1).any((l) => RegExp(r'^BREAKING[ -]CHANGE:').hasMatch(l.trim()))) return Bump.major;
  return m?.group(1) == 'feat' ? Bump.minor : Bump.patch;
}

/// The next version after [lastTag] (e.g. `v1.2.3`, or null when nothing is
/// tagged yet) given the commit [messages] since then.
({String version, bool isNew}) nextVersion(String? lastTag, List<String> messages) {
  if (lastTag == null) return (version: firstVersion, isNew: true);
  final m = _tag.firstMatch(lastTag);
  if (m == null) throw FormatException('Not a release tag: $lastTag');
  var (major, minor, patch) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  final bump = messages.map(bumpFor).fold(Bump.none, (a, b) => b.index > a.index ? b : a);
  switch (bump) {
    case Bump.none:
      return (version: '$major.$minor.$patch', isNew: false);
    case Bump.patch:
      patch++;
    case Bump.minor:
      (minor, patch) = (minor + 1, 0);
    case Bump.major:
      (major, minor, patch) = (major + 1, 0, 0);
  }
  return (version: '$major.$minor.$patch', isNew: true);
}

String _git(List<String> args) {
  final r = Process.runSync('git', args);
  if (r.exitCode != 0) throw ProcessException('git', args, '${r.stderr}', r.exitCode);
  return (r.stdout as String).trim();
}

void main() {
  // The newest v1.2.3-style tag reachable from HEAD.
  final tags = _git(['tag', '--merged', 'HEAD', '--list', 'v*', '--sort=-v:refname']).split('\n').where(_tag.hasMatch);
  final lastTag = tags.isEmpty ? null : tags.first;
  final range = lastTag == null ? 'HEAD' : '$lastTag..HEAD';
  // NUL-separated so multi-line bodies stay whole.
  final messages = _git(['log', range, '--format=%B%x00']).split('\x00').where((m) => m.trim().isNotEmpty).toList();
  final next = nextVersion(lastTag, messages);
  stdout
    ..writeln('version=${next.version}')
    ..writeln('tag=${next.isNew}');
}
