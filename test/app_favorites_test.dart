import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/share_link.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/core/seed_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

Grid seedWith(String pattern, int x, int y) {
  final g = Grid(512, 384);
  patternLibrary[pattern]!.stampOnto(g, x, y);
  return g;
}

void main() {
  group('FavoritesStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('hearting saves newest first and survives a reload', () async {
      final store = FavoritesStore();
      await store.load();
      expect(await store.toggle(seedWith('glider', 10, 10), title: 'One glider', summary: 'It flies.'), isTrue);
      await store.toggle(seedWith('pulsar', 50, 50), title: 'A pulsar', summary: 'It pulses.');

      final reloaded = FavoritesStore();
      await reloaded.load();
      expect(reloaded.items.map((f) => f.title), ['A pulsar', 'One glider']);
      expect(reloaded.items.last.seed.stateHash, seedWith('glider', 10, 10).stateHash);
    });

    test('hearting the same seed again removes it', () async {
      final store = FavoritesStore();
      final seed = seedWith('glider', 10, 10);
      await store.toggle(seed, title: 'a', summary: '');
      expect(await store.toggle(seed.copy(), title: 'a', summary: ''), isFalse);
      expect(store.items, isEmpty);
    });

    test('delete persists', () async {
      final store = FavoritesStore();
      await store.toggle(seedWith('glider', 10, 10), title: 'a', summary: '');
      await store.remove(store.items.single);
      final reloaded = FavoritesStore();
      await reloaded.load();
      expect(reloaded.items, isEmpty);
    });

    test('corrupt storage and bad entries are skipped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'favorites_v1': jsonEncode([
          {'code': SeedCodec.encode(seedWith('block', 5, 5)), 'title': 'ok', 'summary': '', 'savedAt': '2026-09-23T20:00:00Z'},
          {'code': 'not a seed', 'title': 'broken'},
          42,
        ]),
      });
      final store = FavoritesStore();
      await store.load();
      expect(store.items.map((f) => f.title), ['ok']);

      SharedPreferences.setMockInitialValues({'favorites_v1': '{not json'});
      final empty = FavoritesStore();
      await empty.load();
      expect(empty.items, isEmpty);
    });

    test('add() skips an identical board and refuses one too large to store safely', () async {
      final store = FavoritesStore();
      expect(await store.add(seedWith('glider', 10, 10), title: 'a', summary: ''), isTrue);
      expect(await store.add(seedWith('glider', 10, 10), title: 'again', summary: ''), isFalse);

      // A 1024x768 checkerboard encodes to ~390 KB: over the per-favourite cap.
      final noisy = Grid(1024, 768);
      for (var y = 0; y < noisy.height; y++) {
        for (var x = (y % 2); x < noisy.width; x += 2) {
          noisy.set(x, y, true);
        }
      }
      expect(SeedCodec.encode(noisy).length, greaterThan(FavoritesStore.maxCodeLength));
      await expectLater(store.add(noisy, title: 'noise', summary: ''), throwsA(isA<FavoriteTooLarge>()));
      expect(store.items.map((f) => f.title), ['a'], reason: 'the collection is untouched');
    });

    test('the collection is capped', () async {
      final store = FavoritesStore();
      for (var i = 0; i < FavoritesStore.maxFavorites + 5; i++) {
        await store.toggle(seedWith('block', i, 0), title: '$i', summary: '');
      }
      expect(store.items, hasLength(FavoritesStore.maxFavorites));
      expect(store.items.first.title, '${FavoritesStore.maxFavorites + 4}', reason: 'the oldest are dropped');
    });
  });

  group('ShareLink', () {
    test('puts the seed in the fragment of the live site URL, and reads it back', () {
      final seed = seedWith('glider', 210, 150);
      final link = ShareLink.forSeed(seed);
      expect(link, 'https://shanepkearney.github.io/life-with-ai/#seed=1_512x384_210_150_bo-2bo-3o');
      final shared = ShareLink.parse(Uri.parse(link))!;
      expect(shared.seed.stateHash, seed.stateHash);
      expect(shared.title, isNull);
    });

    test('carries the prompt as a title, escaping characters that would break the link', () {
      const title = 'Two gliders & a pulsar = chaos? 100% #yes';
      final link = ShareLink.forSeed(seedWith('glider', 10, 10), title: title);
      expect(link, contains('#seed=1_512x384_10_10_bo-2bo-3o&title='));
      expect(ShareLink.parse(Uri.parse(link))!.title, title);
    });

    test('titles are cleaned and capped; a bad title never loses the seed', () {
      final seed = seedWith('glider', 10, 10);
      final messy = ShareLink.parse(Uri.parse(ShareLink.forSeed(seed, title: 'line one\nline\ttwo\u0007')))!;
      expect(messy.title, 'line one line two');
      final long = ShareLink.parse(Uri.parse(ShareLink.forSeed(seed, title: 'x' * 500)))!;
      expect(long.title!.length, ShareLink.maxTitleLength);
      expect(ShareLink.parse(Uri.parse('${ShareLink.site}#seed=1_512x384_10_10_bo-2bo-3o&title=%%%'))?.seed.population, 5);
      expect(ShareLink.parse(Uri.parse('${ShareLink.site}#seed=1_512x384_10_10_bo-2bo-3o&title='))!.title, isNull);
    });

    test('carries a note, cleaned, capped and escaped', () {
      final seed = seedWith('glider', 10, 10);
      const note = 'Peaks near gen 136 & settles by ~330 = a period-2 garden.';
      final shared = ShareLink.parse(Uri.parse(ShareLink.forSeed(seed, title: 'Bloom', note: note)))!;
      expect((shared.title, shared.note), ('Bloom', note));
      final long = ShareLink.parse(Uri.parse(ShareLink.forSeed(seed, note: 'word ' * 200)))!;
      expect(long.note!.length, lessThanOrEqualTo(ShareLink.maxNoteLength));
      expect(long.note, endsWith('…'));
      expect(ShareLink.parse(Uri.parse(ShareLink.forSeed(seed, note: ' \n ')))!.note, isNull);
      expect(ShareLink.parse(Uri.parse(ShareLink.forSeed(seed, note: 'Short, and it fits.')))!.note, 'Short, and it fits.');
    });

    test('the seed comes first: a note only fills the room it leaves, and is cut to fit', () {
      // A seed whose link is ~1,700 characters leaves room for only part of a note.
      final roomy = Grid(512, 384);
      for (var x = 0; x < 120; x++) {
        for (var y = 0; y < 24; y++) {
          if ((x * 7 + y * 13) % 5 == 0) roomy.set(100 + x, 100 + y, true);
        }
      }
      final bare = ShareLink.forSeed(roomy, title: 'Dense');
      expect(bare.length, inInclusiveRange(1500, ShareLink.comfortableLength - 100));
      final note = 'Ünïcode & symbols = more bytes when encoded. ' * 9;
      final link = ShareLink.forSeed(roomy, title: 'Dense', note: note);
      expect(link.length, lessThanOrEqualTo(ShareLink.comfortableLength));
      final shared = ShareLink.parse(Uri.parse(link))!;
      expect(shared.seed.stateHash, roomy.stateHash, reason: 'the seed is never shortened');
      expect(shared.note, endsWith('…'));
      expect(note.startsWith(shared.note!.substring(0, shared.note!.length - 1)), isTrue);

      // A seed that fills the budget on its own gets no note at all.
      final huge = Grid(512, 384);
      for (var i = 0; i < 4000; i++) {
        huge.set((i * 37) % 512, (i * 91) % 384, true);
      }
      final full = ShareLink.forSeed(huge, note: note);
      expect(full, isNot(contains('note=')));
      expect(ShareLink.parse(Uri.parse(full))!.seed.stateHash, huge.stateHash);
    });

    test("stock summaries aren't sent as notes", () {
      Favorite fav(String summary) => Favorite(code: 'x', title: 't', summary: summary, savedAt: DateTime(2026));
      expect(fav(Favorite.momentSummary).linkNote, isNull);
      expect(fav(Favorite.sharedSummary).linkNote, isNull);
      expect(fav('').linkNote, isNull);
      expect(fav('A bloom that settles.').linkNote, 'A bloom that settles.');
    });

    test('ignores URLs without a valid seed', () {
      for (final url in [
        'https://shanepkearney.github.io/life-with-ai/',
        'https://shanepkearney.github.io/life-with-ai/#/',
        'https://shanepkearney.github.io/life-with-ai/#seed=',
        'https://shanepkearney.github.io/life-with-ai/#title=only-a-title',
        'https://shanepkearney.github.io/life-with-ai/#seed=1_10x10_0_0_99o',
      ]) {
        expect(ShareLink.parse(Uri.parse(url)), isNull, reason: url);
      }
    });
  });
}
