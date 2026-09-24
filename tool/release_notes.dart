// Writes the GitHub Release notes for the version being released, from the
// Conventional Commits since the last release tag, grouped by kind:
//
//   dart tool/release_notes.dart 1.3.0 > notes.md
//
// Unlike GitHub's generated notes, which only list pull requests, this sees
// every commit, including the ones pushed straight to main before the project
// used pull requests. A hand-written intro in .github/releases/v<version>.md,
// if there is one, goes above the list.
import 'dart:convert';
import 'dart:io';

import 'next_version.dart';

const repo = 'shanepkearney/life-with-ai';
const site = 'https://shanepkearney.github.io/life-with-ai/';

/// One commit being released: its short hash, whole message, and the pull
/// request that brought it in, if any.
typedef ReleasedCommit = ({String sha, String message, int? pr});

/// A community seed added in this release: its name and author (from its
/// file) and the pull request, or commit, that brought it.
typedef SeedCredit = ({String name, String author, String sha, int? pr});

final _conventional = RegExp(r'^(\w+)(\([^)]*\))?(!)?:\s*(.*)$');

/// The notes, in Markdown. [commits] are newest first, as `git log` lists them.
String releaseNotes({
  required String version,
  required String? previousTag,
  required List<ReleasedCommit> commits,
  List<SeedCredit> newSeeds = const [],
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
  // What this release built, pinned to this version (not "latest").
  out
    ..writeln('## Downloads\n')
    ..writeln('- **Web:** $site (deployed from this release)')
    ..writeln('- **macOS:** [Life-with-AI.dmg](https://github.com/$repo/releases/download/v$version/Life-with-AI.dmg), '
        'Apple silicon and Intel, macOS 10.15 or later ([opening it the first time](https://github.com/$repo#installing-on-macos))\n');
  void section(String title, List<String> lines) {
    if (lines.isEmpty) return;
    out.writeln('## $title\n');
    lines.forEach(out.writeln);
    out.writeln();
  }

  section('Breaking changes', breaking);
  section('Features', features);
  section('Community seeds', [
    for (final s in newSeeds) '- "${s.name}" by @${s.author} (${s.pr != null ? '#${s.pr}' : s.sha})',
  ]);
  section('Fixes', fixes);
  section('Docs and maintenance', other);
  if (breaking.isEmpty && features.isEmpty && newSeeds.isEmpty && fixes.isEmpty && other.isEmpty) {
    out.writeln('No changes since $previousTag.\n');
  }
  out.writeln(
    previousTag == null
        ? '**Full history**: https://github.com/$repo/commits/v$version'
        : '**Full changelog**: https://github.com/$repo/compare/$previousTag...v$version',
  );
  return out.toString();
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart tool/release_notes.dart <version>');
    exit(64);
  }
  final version = args.single;
  // CI tags the release before building it, so skip this version's own tag.
  final previousTag = lastReleaseTag(except: 'v$version');
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

  // Community seed commits are credited in their own section (below), not listed as commits.
  final commits = <ReleasedCommit>[
    for (final c in commitsIn(range))
      if (!c.communityOnly) (sha: c.sha.substring(0, 7), message: c.message, pr: prOf[c.sha]),
  ];

  // Seeds added since the last release, named and credited from their files.
  final added = git(['log', range, '--diff-filter=A', '--name-only', '--format=%x1e%H', '--', communitySeedsDir]);
  final newSeeds = <SeedCredit>[];
  for (final block in added.split('\x1e').where((b) => b.trim().isNotEmpty).toList().reversed) {
    final [sha, ...paths] = block.trim().split('\n').where((l) => l.isNotEmpty).toList();
    for (final path in paths.where((p) => p.endsWith('.json'))) {
      Map<String, Object?> entry;
      try {
        entry = jsonDecode(git(['show', 'HEAD:$path'])) as Map<String, Object?>;
      } catch (_) {
        continue; // since removed, or unreadable: nothing to credit
      }
      newSeeds.add((
        name: '${entry['name'] ?? path.split('/').last}',
        author: '${entry['author'] ?? 'unknown'}',
        sha: sha.substring(0, 7),
        pr: prOf[sha],
      ));
    }
  }

  final introFile = File('.github/releases/v$version.md');
  stdout.write(
    releaseNotes(
      version: version,
      previousTag: previousTag,
      commits: commits,
      newSeeds: newSeeds,
      intro: introFile.existsSync() ? introFile.readAsStringSync() : null,
    ),
  );
}
