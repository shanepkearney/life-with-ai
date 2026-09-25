import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/community.dart';
import 'package:life_with_ai/core/grid.dart';

/// The check every community pull request runs. Its failure messages are
/// written for the contributor, not for us.
void main() {
  final files = Directory('community/seeds').listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));

  test('there are community patterns, and nothing else in the folder', () {
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(f.path, endsWith('.rle'), reason: 'community/seeds/ holds only .rle files');
    }
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test('community/seeds/$name is a valid entry', () {
      final CommunitySeed seed;
      try {
        seed = CommunitySeed.parse(file.readAsStringSync());
      } on FormatException catch (e) {
        fail('$name: ${e.message}');
      }
      expect(name, CommunitySeed.fileNameFor(seed.name), reason: 'name the file after the pattern\'s #N line');
      expect(seed.pattern.cells, isNotEmpty);
    });
  }

  test('no two entries share a name or a pattern', () {
    final names = <String>{}, patterns = <String>{};
    for (final f in files) {
      final seed = CommunitySeed.parse(f.readAsStringSync());
      expect(names.add(seed.name.toLowerCase()), isTrue, reason: '"${seed.name}" is taken');
      final cells = [...seed.pattern.cells]..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
      expect(patterns.add('${seed.pattern.width}x${seed.pattern.height}:$cells'), isTrue, reason: '${f.path} repeats an existing pattern');
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

  test('the converted seeds keep their exact boards; classics get the medium board, centered', () {
    final garden = CommunitySeed.parse(File('community/seeds/oscillator-garden.rle').readAsStringSync());
    expect((garden.seed!.width, garden.seed!.height), (512, 384));
    expect(garden.seed!.boundingBox, (x: 216, y: 152, width: 83, height: 83), reason: 'its #CXRLE Pos, exactly');
    final gun = CommunitySeed.parse(File('community/seeds/gosper-glider-gun.rle').readAsStringSync());
    expect(gun.discoveredElsewhere, isTrue);
    expect(gun.discoverer, 'Bill Gosper, 1970');
    expect(gun.source.toString(), 'https://conwaylife.com/wiki/Gosper_glider_gun');
    expect((gun.seed!.width, gun.seed!.height), (512, 384));
    expect(gun.seed!.population, 36);
    // A classic behaves as it should: the pulsar is period 3.
    final pulsar = CommunitySeed.parse(File('community/seeds/pulsar.rle').readAsStringSync()).seed!;
    expect(pulsar.step().step().step().stateHash, pulsar.stateHash);
  });

  group('CommunitySeed.parse', () {
    const good = '''#N Glider
#O octocat
#C One glider, drifting.
#C Added: 2026-09-24 by @octocat
x = 3, y = 3, rule = B3/S23
bo\$2bo\$3o!''';

    test('reads a good entry', () {
      final seed = CommunitySeed.parse(good);
      expect((seed.name, seed.author, seed.description), ('Glider', 'octocat', 'One glider, drifting.'));
      expect(seed.authorUrl.toString(), 'https://github.com/octocat');
      expect(seed.seed!.population, 5);
      expect(seed.giant, isFalse);
      expect(seed.discoveredElsewhere, isFalse);
    });

    test('a giant plays on the plane: no board, no link', () {
      final seed = CommunitySeed.parse(good.replaceFirst('x = 3, y = 3, rule = B3/S23\nbo\$2bo\$3o!', 'x = 5000, y = 1\n3o4994b3o!'));
      expect(seed.giant, isTrue);
      expect(seed.seed, isNull);
      expect(seed.shareLink, isNull);
    });

    final bad = <String, String Function(String)>{
      'a missing name': (t) => t.replaceFirst('#N Glider\n', ''),
      'a long name': (t) => t.replaceFirst('#N Glider', '#N ${'x' * 41}'),
      'a missing #O': (t) => t.replaceFirst('#O octocat\n', ''),
      'no description': (t) => t.replaceFirst('#C One glider, drifting.\n', ''),
      'no Added line': (t) => t.replaceFirst('#C Added: 2026-09-24 by @octocat\n', ''),
      'a loose date': (t) => t.replaceFirst('2026-09-24', 'Sep 24 2026'),
      'a URL as the GitHub user': (t) => t.replaceFirst('@octocat', '@https://github.com/octocat'),
      'a user with a trailing hyphen': (t) => t.replaceFirst('@octocat', '@octocat-'),
      "someone else's find with no source": (t) => t.replaceFirst('#O octocat', '#O Richard Guy, 1969'),
      'a source that is not https': (t) => t.replaceFirst('#O octocat', '#O Richard Guy, 1969\n#C Source: http://example.com'),
      'another rule': (t) => t.replaceFirst('B3/S23', 'B36/S23'),
      'no live cells': (t) => t.replaceFirst('bo\$2bo\$3o!', '3b!'),
      'a pattern off its board': (t) => t.replaceFirst('x = 3, y = 3, rule = B3/S23', '#CXRLE Pos=10,10\nx = 3, y = 3, rule = B3/S23:T11,11'),
      'two names': (t) => t.replaceFirst('#N Glider', '#N Glider\n#N Another'),
    };
    for (final MapEntry(key: what, value: spoil) in bad.entries) {
      test('rejects $what', () => expect(() => CommunitySeed.parse(spoil(good)), throwsFormatException));
    }

    test('someone else\'s find is fine with its source', () {
      final seed = CommunitySeed.parse(good.replaceFirst('#O octocat', '#O Richard Guy, 1969\n#C Source: https://conwaylife.com/wiki/Glider'));
      expect(seed.discoveredElsewhere, isTrue);
    });
  });

  test('file names follow the pattern name', () {
    expect(CommunitySeed.fileNameFor('Oscillator Garden'), 'oscillator-garden.rle');
    expect(CommunitySeed.fileNameFor('  Glider #2: the return!  '), 'glider-2-the-return.rle');
    expect(CommunitySeed.slugFor('Gosper glider gun'), 'gosper-glider-gun');
  });

  test('the RLE the Submit button writes parses back, exactly, board and all', () {
    final g = Grid(512, 384)
      ..set(11, 10, true)
      ..set(12, 11, true)
      ..set(10, 12, true)
      ..set(11, 12, true)
      ..set(12, 12, true);
    final text = CommunitySeed.entryRle(
      name: 'Glider',
      author: 'octocat',
      added: DateTime(2026, 9, 4),
      description: 'One glider.',
      prompt: 'A glider',
      seed: g,
    );
    expect(text, contains('#C Added: 2026-09-04 by @octocat'));
    expect(text, contains('#CXRLE Pos=10,10'));
    expect(text, contains('rule = B3/S23:T512,384'));
    final back = CommunitySeed.parse(text);
    expect((back.name, back.prompt, back.discoverer), ('Glider', 'A glider', 'octocat'));
    expect(back.seed!.stateHash, g.stateHash);
  });
}
