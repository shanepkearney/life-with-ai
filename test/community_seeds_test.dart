import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/community.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/seed_codec.dart';

/// The check every community pull request runs. Its failure messages are
/// written for the contributor, not for us.
void main() {
  final files = Directory('community/seeds').listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));

  test('there are community seeds, and nothing else in the folder', () {
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(f.path, endsWith('.json'), reason: 'community/seeds/ holds only .json entries');
    }
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test('community/seeds/$name is a valid entry', () {
      final Object? json;
      try {
        json = jsonDecode(file.readAsStringSync());
      } on FormatException catch (e) {
        fail('$name is not valid JSON: ${e.message}');
      }
      final CommunitySeed seed;
      try {
        seed = CommunitySeed.parse(json);
      } on FormatException catch (e) {
        fail('$name: ${e.message}');
      }
      expect(name, CommunitySeed.fileNameFor(seed.name), reason: 'name the file after the seed');
      expect(
        BoardSize.values.any((s) => s.width == seed.seed.width && s.height == seed.seed.height),
        isTrue,
        reason: 'the seed must be on one of the app\'s board sizes',
      );
    });
  }

  test('no two entries share a name or a seed', () {
    final names = <String>{}, codes = <String>{};
    for (final f in files) {
      final seed = CommunitySeed.parse(jsonDecode(f.readAsStringSync()));
      expect(names.add(seed.name.toLowerCase()), isTrue, reason: '"${seed.name}" is taken');
      expect(codes.add(SeedCodec.encode(seed.seed)), isTrue, reason: '${f.path} repeats an existing seed');
    }
  });

  test('every entry is bundled into the app, newest first', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final seeds = await loadCommunitySeeds(rootBundle);
    expect(seeds.length, files.length);
    for (var i = 1; i < seeds.length; i++) {
      expect(seeds[i - 1].added.isBefore(seeds[i].added), isFalse);
    }
  });

  group('CommunitySeed.parse rejects', () {
    final glider = Grid(512, 384)
      ..set(11, 10, true)
      ..set(12, 11, true)
      ..set(10, 12, true)
      ..set(11, 12, true)
      ..set(12, 12, true);
    Map<String, Object?> good() => {
      'name': 'Glider',
      'author': 'octocat',
      'added': '2026-09-24',
      'description': 'One glider.',
      'link': ShareLink.forSeed(glider),
    };

    test('nothing when the entry is good', () {
      final seed = CommunitySeed.parse(good());
      expect(seed.authorUrl.toString(), 'https://github.com/octocat');
      expect(seed.seed.population, 5);
    });

    final bad = <String, Map<String, Object?> Function(Map<String, Object?>)>{
      'unknown fields': (m) => m..['website'] = 'x',
      'a missing name': (m) => m..remove('name'),
      'a long name': (m) => m..['name'] = 'x' * 41,
      'a multi-line description': (m) => m..['description'] = 'a\nb',
      'a URL as the author': (m) => m..['author'] = 'https://github.com/octocat',
      'an author with a trailing hyphen': (m) => m..['author'] = 'octocat-',
      'a loose date': (m) => m..['added'] = 'Sep 24 2026',
      'another site\'s link': (m) => m..['link'] = 'https://evil.example/#seed=1_512x384_10_10_bo-2bo-3o',
      'a link with no seed': (m) => m..['link'] = '${ShareLink.site}#title=hi',
      'an empty board': (m) => m..['link'] = ShareLink.forSeed(Grid(512, 384)),
    };
    for (final MapEntry(key: what, value: spoil) in bad.entries) {
      test(what, () => expect(() => CommunitySeed.parse(spoil(good())), throwsFormatException));
    }
  });

  test('file names follow the seed name', () {
    expect(CommunitySeed.fileNameFor('Oscillator Garden'), 'oscillator-garden.json');
    expect(CommunitySeed.fileNameFor('  Glider #2: the return!  '), 'glider-2-the-return.json');
  });

  test('the JSON the Submit button writes parses back', () {
    final json = CommunitySeed.entryJson(
      name: 'Glider',
      author: 'octocat',
      added: DateTime(2026, 9, 4),
      description: 'One glider.',
      link: '${ShareLink.site}#seed=1_512x384_10_10_bo-2bo-3o',
    );
    expect(json, contains('"added": "2026-09-04"'));
    expect(CommunitySeed.parse(jsonDecode(json)).name, 'Glider');
  });
}
