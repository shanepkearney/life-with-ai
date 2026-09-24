import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/grid.dart';
import 'share_link.dart';

/// A seed someone found and contributed by pull request: one JSON file in
/// `community/seeds/`, bundled into the app, credited to its author's GitHub.
class CommunitySeed {
  CommunitySeed._({
    required this.name,
    required this.author,
    required this.added,
    required this.description,
    required this.prompt,
    required this.seed,
  });

  final String name;

  /// A GitHub username, shown as "by @author" and linked to their profile.
  final String author;
  final DateTime added;
  final String description;

  /// The prompt the seed was made from, when it was made with the assistant.
  final String? prompt;
  final Grid seed;

  Uri get authorUrl => Uri.https('github.com', '/$author');

  String get shareLink => ShareLink.forSeed(seed, title: name, note: description);

  static const fields = {'name', 'author', 'added', 'description', 'prompt', 'link'};
  static const maxName = 40, maxDescription = 400, maxPrompt = ShareLink.maxTitleLength;

  /// GitHub's rules: letters, digits and single hyphens, not at either end, at most 39 characters.
  static final githubHandle = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$');

  /// The file name a seed called [name] must have: `Oscillator Garden` → `oscillator-garden.json`.
  static String fileNameFor(String name) =>
      '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '')}.json';

  /// Parses one entry, or throws [FormatException] saying what is wrong: the
  /// message is what a contributor sees when the CI check fails their PR.
  static CommunitySeed parse(Object? json) {
    if (json is! Map) throw const FormatException('An entry is a JSON object.');
    final unknown = json.keys.where((k) => !fields.contains(k)).toList();
    if (unknown.isNotEmpty) throw FormatException('Unknown fields: ${unknown.join(', ')}. Allowed: ${fields.join(', ')}.');

    String text(String key, int max, {bool required = true}) {
      final v = json[key];
      if (v == null && !required) return '';
      if (v is! String || v.trim().isEmpty) throw FormatException('"$key" is required and must be text.');
      if (v != v.trim() || RegExp(r'[\u0000-\u001F\u007F]').hasMatch(v)) {
        throw FormatException('"$key" must be one line, with no leading or trailing spaces.');
      }
      if (v.length > max) throw FormatException('"$key" is ${v.length} characters; the most is $max.');
      return v;
    }

    final name = text('name', maxName);
    final author = text('author', 39);
    if (!githubHandle.hasMatch(author)) throw FormatException('"author" must be a GitHub username, not "$author".');
    final added = DateTime.tryParse(text('added', 10));
    if (added == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(json['added'] as String)) {
      throw const FormatException('"added" must be a date like 2026-09-24.');
    }
    final description = text('description', maxDescription);
    final prompt = text('prompt', maxPrompt, required: false);

    final link = Uri.tryParse(text('link', 64 * 1024));
    if (link == null || link.replace(fragment: '').toString() != '${ShareLink.site}#') {
      throw FormatException('"link" must be a share link from ${ShareLink.site}.');
    }
    final shared = ShareLink.parse(link);
    if (shared == null) throw const FormatException('"link" has no valid seed. Copy it again with the link button.');
    if (shared.seed.population == 0) throw const FormatException('"link" is an empty board.');

    return CommunitySeed._(
      name: name,
      author: author,
      added: added,
      description: description,
      prompt: prompt.isEmpty ? null : prompt,
      seed: shared.seed,
    );
  }

  /// The JSON a contributor commits, e.g. from the Submit button.
  static String entryJson({
    required String name,
    required String author,
    required DateTime added,
    required String description,
    String? prompt,
    required String link,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${const JsonEncoder.withIndent('  ').convert({'name': name, 'author': author, 'added': '${added.year}-${two(added.month)}-${two(added.day)}', 'description': description, if (prompt != null && prompt.isNotEmpty) 'prompt': prompt, 'link': link})}\n';
  }
}

/// Every bundled community seed, newest first. A broken entry is skipped rather
/// than taking the tab down with it; CI keeps broken entries out of main anyway.
Future<List<CommunitySeed>> loadCommunitySeeds(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final seeds = <CommunitySeed>[];
  for (final path in manifest.listAssets().where((p) => p.startsWith('community/seeds/') && p.endsWith('.json'))) {
    try {
      seeds.add(CommunitySeed.parse(jsonDecode(await bundle.loadString(path))));
    } on FormatException {
      // skipped; see above
    }
  }
  seeds.sort((a, b) => b.added.compareTo(a.added) != 0 ? b.added.compareTo(a.added) : a.name.compareTo(b.name));
  return seeds;
}
