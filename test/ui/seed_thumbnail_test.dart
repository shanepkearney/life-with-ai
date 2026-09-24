import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/core/grid.dart';
import 'package:life_with_ai/core/patterns.dart';
import 'package:life_with_ai/ui/seed_thumbnail.dart';

/// Renders a thumbnail in the middle of a larger transparent canvas and
/// returns the pixels, so a test can see exactly where it painted.
Future<({ByteData pixels, int size})> render(Grid seed, {int canvas = 160, double tile = 56}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  final offset = (canvas - tile) / 2;
  c.translate(offset, offset);
  c.clipRect(Rect.fromLTWH(0, 0, tile, tile)); // what ClipRRect does in the widget
  SeedPainter(seed).paint(c, Size.square(tile));
  final image = await recorder.endRecording().toImage(canvas, canvas);
  final data = await image.toByteData();
  return (pixels: data!, size: canvas);
}

/// Counts painted pixels inside and outside the tile.
({int inside, int outside}) painted(({ByteData pixels, int size}) r, {double tile = 56}) {
  final lo = (r.size - tile) / 2, hi = lo + tile;
  var inside = 0, outside = 0;
  for (var y = 0; y < r.size; y++) {
    for (var x = 0; x < r.size; x++) {
      if (r.pixels.getUint8((y * r.size + x) * 4 + 3) == 0) continue;
      (x >= lo && x < hi && y >= lo && y < hi) ? inside++ : outside++;
    }
  }
  return (inside: inside, outside: outside);
}

void main() {
  testWidgets('a whole random board stays inside its tile (the ghost-overlay bug)', (tester) async {
    final board = Grid(512, 384);
    final rnd = Random(1);
    for (var i = 0; i < board.cells.length; i++) {
      if (rnd.nextDouble() < 0.25) board.cells[i] = 1;
    }
    final r = await tester.runAsync(() => render(board));
    final p = painted(r!);
    expect(p.outside, 0);
    expect(p.inside, greaterThan(1000), reason: 'reads as a textured board, not blank');
  });

  testWidgets('a sparse seed spread across the board is still visible (the black-tile bug)', (tester) async {
    final seed = Grid(512, 384);
    for (final (x, y) in [(100, 100), (400, 100), (100, 300), (400, 300)]) {
      patternLibrary['r_pentomino']!.stampOnto(seed, x, y);
    }
    final p = painted((await tester.runAsync(() => render(seed)))!);
    expect(p.outside, 0);
    expect(p.inside, greaterThanOrEqualTo(4), reason: 'each cluster shows up');
  });

  testWidgets('a small seed draws crisp cells inside the tile', (tester) async {
    final seed = Grid(512, 384);
    patternLibrary['glider']!.stampOnto(seed, 10, 10);
    final p = painted((await tester.runAsync(() => render(seed)))!);
    expect(p.outside, 0);
    expect(p.inside, greaterThan(5 * 36), reason: '5 cells of ~6-8px each');
  });

  testWidgets('the widget clips even if the painter overdraws', (tester) async {
    await tester.pumpWidget(Center(child: SeedThumbnail(Grid(4, 4)..set(1, 1, true))));
    expect(find.byType(ClipRRect), findsOneWidget);
  });
}
