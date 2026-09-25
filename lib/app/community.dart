import 'package:flutter/services.dart';

import '../core/grid.dart';
import '../core/life_rule.dart';
import '../core/rle.dart';
import 'life_controller.dart';
import 'share_link.dart';

/// A pattern someone contributed by pull request: one RLE file in
/// `community/seeds/`, bundled into the app, credited to its discoverer and
/// to the GitHub user who added it. Standard RLE, so Golly and LifeViewer
/// open the files unchanged; the app's own details ride in comment lines:
///
///     #N Boxed Chaos
///     #O shanepkearney                     who found or discovered it
///     #C The Neon Frame packed with …      what it does (one or more lines)
///     #C Prompt: …                         the prompt, when Claude made it
///     #C Source: https://…                 where it came from, if elsewhere
///     #C License: GFDL 1.2, from the LifeWiki   its license, if not CC BY 4.0
///     #C Plays on: endless plane           no board: it needs room to run
///     #C Added: 2026-09-23 by @shanepkearney
///     #CXRLE Pos=120,150                   where it sits on its board
///     x = 200, y = 150, rule = B3/S23:T512,384
///
/// A seed made in the app keeps its exact board (the torus in its rule) and
/// place on it. A pattern from elsewhere, such as a gun from the LifeWiki,
/// plays centered on the smallest board that holds it, or on HashLife's
/// endless plane when no board can.
class CommunitySeed {
  CommunitySeed._({
    required this.name,
    required this.author,
    required this.added,
    required this.description,
    required this.prompt,
    required this.discoverer,
    required this.source,
    required this.pattern,
    required this.rle,
    required this.license,
    required this.endless,
    required Grid? board,
  }) : _board = board;

  final String name;

  /// The GitHub user who added it, shown as "added by @author".
  final String author;
  final DateTime added;
  final String description;

  /// The prompt it was made from, when it was made with the assistant.
  final String? prompt;

  /// Who found or discovered it: a GitHub user for seeds made here, or a
  /// person (and year) for a classic, e.g. "Bill Gosper, 1970".
  final String discoverer;

  /// Where a pattern from elsewhere came from.
  final Uri? source;

  /// The license, when it isn't the community's CC BY 4.0 (e.g. the
  /// LifeWiki's GFDL 1.2).
  final String? license;

  /// Asks for HashLife's endless plane: on a wrap-around board what it sends
  /// out (Primer's spaceships, a gun's gliders) would come back and wreck it.
  final bool endless;

  final RlePattern pattern;

  /// The file as committed: what Download saves.
  final String rle;

  final Grid? _board;

  /// The seed on a board: its own for a seed made here, otherwise centered on
  /// the smallest board that holds it. Null for a giant pattern (see [giant]).
  Grid? get seed => _board;

  /// Too big for any board: it plays on HashLife's endless plane.
  bool get giant => _board == null;

  /// Plays on the endless plane, because it asks to or because it must.
  bool get playsOnPlane => endless || giant;

  Uri get authorUrl => Uri.https('github.com', '/$author');

  /// Whether the discoverer is someone other than the person who added it.
  bool get discoveredElsewhere => discoverer != author;

  /// `boxed-chaos`, from `boxed-chaos.rle`: the name in file names and routes.
  String get slug => slugFor(name);

  /// A seed link, for seeds played on a board; null on the plane, which a
  /// link can't describe.
  String? get shareLink => playsOnPlane ? null : ShareLink.forSeed(_board!, title: name, note: description, rule: pattern.rule);

  static const maxName = 40, maxDescription = 400, maxPrompt = ShareLink.maxTitleLength, maxDiscoverer = 80;

  /// Files are small, but a giant like the Turing machine is 680 KB.
  static const maxFileBytes = 2 * 1024 * 1024;

  /// GitHub's rules: letters, digits and single hyphens, not at either end, at most 39 characters.
  static final githubHandle = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$');

  /// `Oscillator Garden` → `oscillator-garden`.
  static String slugFor(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  /// The file name a seed called [name] must have: `oscillator-garden.rle`.
  static String fileNameFor(String name) => '${slugFor(name)}.rle';

  static final _added = RegExp(r'^Added:\s*(\d{4}-\d{2}-\d{2})\s+by\s+@(\S+)$');

  /// Parses one file, or throws [FormatException] saying what is wrong: the
  /// message is what a contributor sees when the CI check fails their PR.
  static CommunitySeed parse(String text) {
    if (text.length > maxFileBytes) throw FormatException('The file is ${text.length} bytes; the most is $maxFileBytes.');
    String? name, discoverer, prompt, source, addedLine, license, playsOn;
    final description = <String>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (!line.startsWith('#') || line.length < 2) continue;
      final tag = line[1], rest = line.substring(2).trim();
      if (tag == 'N') name = _once(name, rest, '#N (the name)');
      if (tag == 'O') discoverer = _once(discoverer, rest, '#O (who found it)');
      if (tag != 'C' || rest.startsWith('XRLE')) continue;
      if (rest.startsWith('Prompt:')) {
        prompt = _once(prompt, rest.substring(7).trim(), '#C Prompt:');
      } else if (rest.startsWith('Source:')) {
        source = _once(source, rest.substring(7).trim(), '#C Source:');
      } else if (rest.startsWith('Added:')) {
        addedLine = _once(addedLine, rest, '#C Added:');
      } else if (rest.startsWith('License:')) {
        license = _once(license, rest.substring(8).trim(), '#C License:');
      } else if (rest.startsWith('Plays on:')) {
        playsOn = _once(playsOn, rest.substring(9).trim(), '#C Plays on:');
      } else if (rest.isNotEmpty) {
        description.add(rest);
      }
    }

    String required(String? v, String what, int max) {
      if (v == null || v.isEmpty) throw FormatException('$what is required.');
      if (v.length > max) throw FormatException('$what is ${v.length} characters; the most is $max.');
      return v;
    }

    final n = required(name, 'A #N line (the name)', maxName);
    final o = required(discoverer, 'A #O line (who found or discovered it)', maxDiscoverer);
    final d = required(description.join(' '), 'A #C line describing what it does', maxDescription);
    if (prompt != null && prompt.length > maxPrompt) throw FormatException('The prompt is ${prompt.length} characters; the most is $maxPrompt.');
    final a = _added.firstMatch(addedLine ?? '');
    if (a == null) throw const FormatException('A "#C Added: 2026-09-25 by @your-github-username" line is required.');
    final added = DateTime.tryParse(a[1]!);
    if (added == null) throw FormatException('"${a[1]}" is not a date like 2026-09-25.');
    final author = a[2]!;
    if (!githubHandle.hasMatch(author)) throw FormatException('"@$author" in the Added line must be a GitHub username.');
    Uri? src;
    if (source != null) {
      src = Uri.tryParse(source);
      if (src == null || src.scheme != 'https' || src.host.isEmpty) throw FormatException('"$source" must be an https:// link to where the pattern came from.');
    } else if (o != author) {
      throw FormatException('It was found by "$o", not @$author: add a "#C Source: https://…" line saying where it came from.');
    }

    if (license != null && (license.isEmpty || license.length > 80)) throw const FormatException('"#C License:" names the license in up to 80 characters.');
    if (playsOn != null && playsOn != 'endless plane') throw FormatException('"#C Plays on: $playsOn" isn\'t known; the only choice is "endless plane".');

    final RlePattern pattern;
    try {
      pattern = Rle.decode(text, unbounded: true);
    } on FormatException catch (e) {
      throw FormatException('The pattern: ${e.message}');
    }

    final pos = RegExp(r'^#CXRLE.*\bPos=(-?\d+),(-?\d+)', multiLine: true).firstMatch(text);
    final Grid? board;
    final t = pattern.torus;
    if (t != null && playsOn != null) throw const FormatException('A pattern with its own board (a torus in its rule) can\'t also ask for the endless plane.');
    if (t != null) {
      // Made here: its own board, and its place on it.
      final x = pos == null ? (t.width - pattern.width) ~/ 2 : int.parse(pos[1]!);
      final y = pos == null ? (t.height - pattern.height) ~/ 2 : int.parse(pos[2]!);
      if (x < 0 || y < 0 || x + pattern.width > t.width || y + pattern.height > t.height) {
        throw FormatException('The pattern at $x,$y runs off its ${t.width}x${t.height} board.');
      }
      board = Grid(t.width, t.height);
      for (final (cx, cy) in pattern.cells) {
        board.set(x + cx, y + cy, true);
      }
    } else {
      // At least the medium board: a pattern from elsewhere often throws gliders, and needs room before they wrap.
      final size = BoardSize.holding(pattern.width, pattern.height, current: BoardSize.medium);
      board = size == null ? null : pattern.centeredOn(size.width, size.height);
    }

    // An endless plane can't hold a rule that brings empty space to life.
    if ((playsOn != null || board == null) && pattern.rule.birthFromNothing) {
      throw FormatException('${pattern.rule.notation} brings empty space to life, so it can\'t play on the endless plane.');
    }

    return CommunitySeed._(
      name: n,
      author: author,
      added: added,
      description: d,
      prompt: prompt,
      discoverer: o,
      source: src,
      pattern: pattern,
      rle: text,
      license: license,
      endless: playsOn != null,
      board: board,
    );
  }

  static String _once(String? previous, String value, String what) {
    if (previous != null) throw FormatException('$what appears twice.');
    return value;
  }

  /// The file a contributor commits, e.g. from the Submit button: [seed] on
  /// its board, with its details in comment lines.
  static String entryRle({
    required String name,
    required String author,
    required DateTime added,
    required String description,
    String? prompt,
    String? discoverer,
    Uri? source,
    required Grid seed,
    LifeRule rule = LifeRule.conway,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    final comments = [
      ..._wrap(description),
      if (prompt != null && prompt.isNotEmpty) 'Prompt: $prompt',
      if (source != null) 'Source: $source',
      'Added: ${added.year}-${two(added.month)}-${two(added.day)} by @$author',
    ];
    return '${Rle.encode(seed, name: name, origin: discoverer ?? author, comments: comments, onBoard: true, rule: rule)}\n';
  }

  /// Description lines of about 70 characters, split between words.
  static List<String> _wrap(String text) {
    final lines = <String>[];
    var line = StringBuffer();
    for (final word in text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      if (line.isNotEmpty && line.length + 1 + word.length > 70) {
        lines.add(line.toString());
        line = StringBuffer();
      }
      if (line.isNotEmpty) line.write(' ');
      line.write(word);
    }
    if (line.isNotEmpty) lines.add(line.toString());
    return lines;
  }
}

/// Every bundled community pattern, newest first. A broken file is skipped
/// rather than taking the tab down with it; CI keeps broken files out of main.
Future<List<CommunitySeed>> loadCommunitySeeds(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final seeds = <CommunitySeed>[];
  for (final path in manifest.listAssets().where((p) => p.startsWith('community/seeds/') && p.endsWith('.rle'))) {
    try {
      seeds.add(CommunitySeed.parse(await bundle.loadString(path)));
    } on FormatException {
      // skipped; see above
    }
  }
  seeds.sort((a, b) => b.added.compareTo(a.added) != 0 ? b.added.compareTo(a.added) : a.name.compareTo(b.name));
  return seeds;
}
