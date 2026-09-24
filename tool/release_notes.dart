// Writes the GitHub Release notes for the version being released, from the
// Conventional Commits since the last release tag, grouped by kind:
//
//   dart tool/release_notes.dart 1.3.0 > notes.md
//
// Unlike GitHub's generated notes, which only list pull requests, this sees
// every commit, including the ones pushed straight to main before the project
// used pull requests. A hand-written intro in .github/releases/v<version>.md,
// if there is one, goes above the list.
import 'dart:io';

import 'next_version.dart';

const repo = 'shanepkearney/life-with-ai';
const site = 'https://shanepkearney.github.io/life-with-ai/';

/// One commit being released: its short hash, whole message, and the pull
/// request that brought it in, if any.
typedef ReleasedCommit = ({String sha, String message, int? pr});

final _conventional = RegExp(r'^(\w+)(\([^)]*\))?(!)?:\s*(.*)$');

/// The notes, in Markdown. [commits] are newest first, as `git log` lists them.
String releaseNotes({
  required String version,
  required String? previousTag,
  required List<ReleasedCommit> commits,
  String? intro,
}) {
  final breaking = <String>[], features = <String>[], fixes = <String>[], other = <String>[];
  for (final c in commits.reversed) {
    final bump = bumpFor(c.message);
    if (bump == Bump.none) continue; // merge commits
    final subject = c.message.trim().split('\n').first.trim();
    final m = _conventional.firstMatch(subject);
    final type = m?.group(1);
    var text = m == null ? subject : m.group(4)!;
    // Drop a trailing "(#12)" that a squash merge adds: the link below says it.
    text = text.replaceFirst(RegExp(r'\s*\(#\d+\)$'), '');
    if (text.isEmpty) continue;
    final line = '- ${text[0].toUpperCase()}${text.substring(1)} (${c.pr != null ? '#${c.pr}' : c.sha})';
    if (bump == Bump.major) {
      breaking.add(line);
    } else if (type == 'feat') {
      features.add(line);
    } else if (type == 'fix' || type == 'perf') {
      fixes.add(line);
    } else {
      other.add(line);
    }
  }

  final out = StringBuffer();
  if (intro != null && intro.trim().isNotEmpty) out.writeln('${intro.trim()}\n');
  void section(String title, List<String> lines) {
    if (lines.isEmpty) return;
    out.writeln('## $title\n');
    lines.forEach(out.writeln);
    out.writeln();
  }

  section('Breaking changes', breaking);
  section('Features', features);
  section('Fixes', fixes);
  section('Docs and maintenance', other);
  if (breaking.isEmpty && features.isEmpty && fixes.isEmpty && other.isEmpty) out.writeln('No changes since $previousTag.\n');
  out.writeln(
    previousTag == null
        ? '**Full history**: https://github.com/$repo/commits/v$version'
        : '**Full changelog**: https://github.com/$repo/compare/$previousTag...v$version',
  );
  out.write('\n▶ **Play it**: $site\n');
  return out.toString();
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart tool/release_notes.dart <version>');
    exit(64);
  }
  final version = args.single;
  final previousTag = lastReleaseTag();
  final range = previousTag == null ? 'HEAD' : '$previousTag..HEAD';

  // Which pull request brought in each commit: everything a "Merge pull
  // request #N" merge added, i.e. between its two parents.
  final prOf = <String, int>{};
  for (final line in git(['log', range, '--merges', '--format=%H %s']).split('\n').where((l) => l.isNotEmpty)) {
    final m = RegExp(r'^(\w+) Merge pull request #(\d+)').firstMatch(line);
    if (m == null) continue;
    for (final sha in git(['rev-list', '${m[1]}^1..${m[1]}^2']).split('\n').where((s) => s.isNotEmpty)) {
      prOf.putIfAbsent(sha, () => int.parse(m[2]!));
    }
  }

  final commits = <ReleasedCommit>[
    for (final record in git(['log', range, '--format=%H%x1f%h%x1f%B%x00']).split('\x00'))
      if (record.trim().isNotEmpty)
        () {
          final [full, short, message] = record.trim().split('\x1f');
          return (sha: short, message: message, pr: prOf[full]);
        }(),
  ];

  final introFile = File('.github/releases/v$version.md');
  stdout.write(
    releaseNotes(
      version: version,
      previousTag: previousTag,
      commits: commits,
      intro: introFile.existsSync() ? introFile.readAsStringSync() : null,
    ),
  );
}
