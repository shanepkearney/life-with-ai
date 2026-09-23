import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/ai/seed_tools.dart';
import 'package:life_with_ai/ai/simulation.dart';

void main() {
  // Run simulations inline so tests don't depend on isolates.
  SeedWorkbench bench([int w = 64, int h = 48]) => SeedWorkbench(w, h, simulator: (r) async => runSimulation(r));

  test('place_pattern stamps the named pattern and reports the new population', () async {
    final b = bench();
    final o = await b.run('place_pattern', {'name': 'glider', 'x': 5, 'y': 5});
    expect(o.isError, isFalse);
    expect(o.seedChanged, isTrue);
    expect(b.seed.population, 5);
    expect(o.text, contains('population 5'));
  });

  test('bad input comes back as an error result, not an exception', () async {
    final b = bench();
    expect((await b.run('place_pattern', {'name': 'nope', 'x': 0, 'y': 0})).isError, isTrue);
    expect((await b.run('place_pattern', {'name': 'glider', 'x': 'left', 'y': 0})).isError, isTrue);
    expect((await b.run('place_pattern', {'name': 'glider', 'x': 1, 'y': 1, 'rotation': 45})).isError, isTrue);
    expect((await b.run('set_cells', {'cells': [[1]]})).isError, isTrue);
    expect((await b.run('simulate', {'generations': 99999})).isError, isTrue);
    expect((await b.run('teleport', {})).isError, isTrue);
    expect(b.seed.population, 0);
  });

  test('simulate reports fate without changing the seed', () async {
    final b = bench(128, 128);
    await b.run('place_pattern', {'name': 'diehard', 'x': 60, 'y': 60});
    final before = b.seed.stateHash;
    final o = await b.run('simulate', {'generations': 200, 'checkpoints': [0, 50]});
    expect(o.text, contains('died out at generation 130'));
    expect(o.text, contains('--- generation 50'));
    expect(b.seed.stateHash, before);
  });

  test('simulate detects still lifes and oscillators', () async {
    final b = bench();
    await b.run('place_pattern', {'name': 'block', 'x': 10, 'y': 10});
    expect((await b.run('simulate', {'generations': 10})).text, contains('still life'));
    await b.run('clear_board', {});
    await b.run('place_pattern', {'name': 'pulsar', 'x': 20, 'y': 20});
    expect((await b.run('simulate', {'generations': 10})).text, contains('period-3'));
  });

  test('include_image returns a PNG', () async {
    final b = bench();
    await b.run('draw_shape', {'shape': 'random_soup', 'x': 0, 'y': 0, 'width': 30, 'height': 30, 'seed': 1});
    final o = await b.run('simulate', {'generations': 5, 'include_image': true});
    expect(o.png, isNotNull);
    expect(o.png!.sublist(1, 4), 'PNG'.codeUnits);
  });

  test('draw_shape shapes', () async {
    final b = bench();
    await b.run('draw_shape', {'shape': 'filled_rect', 'x': 0, 'y': 0, 'width': 4, 'height': 3});
    expect(b.seed.population, 12);
    await b.run('clear_board', {});
    await b.run('draw_shape', {'shape': 'rect_outline', 'x': 0, 'y': 0, 'width': 4, 'height': 3});
    expect(b.seed.population, 10);
    await b.run('clear_board', {});
    await b.run('draw_shape', {'shape': 'line', 'x': 0, 'y': 0, 'width': 9, 'height': 0});
    expect(b.seed.population, 10);
  });

  test('view_board region is 1:1', () async {
    final b = bench();
    await b.run('place_pattern', {'name': 'glider', 'x': 2, 'y': 2});
    final o = await b.run('view_board', {'x': 2, 'y': 2, 'width': 3, 'height': 3});
    expect(o.text, endsWith(' # \n  #\n###\n'));
  });

  test('tool definitions all have a name, description and object schema', () {
    for (final t in seedToolDefinitions) {
      expect(t['name'], isA<String>());
      expect(t['description'], isA<String>());
      expect((t['input_schema'] as Map)['type'], 'object');
    }
  });
}
