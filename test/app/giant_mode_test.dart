import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/giant_mode.dart';
import 'package:life_with_ai/engine/giant_runner.dart';

void main() {
  GiantMode turing() => GiantMode('Turing machine', GiantRunner.inline())
    ..canvas = const Size(1000, 800)
    ..bounds = (x: 0, y: 0, width: 12699, height: 12652);

  test('Fit centres the whole pattern at the closest zoom that shows it', () {
    final g = turing()..fit();
    expect((g.centreX, g.centreY), (6349.5, 6326.0));
    expect(g.zoom, -4, reason: '12,699 cells in 1,000 pixels needs 16 cells a pixel');
    expect(g.zoomLabel, '16 cells a pixel');
    final v = g.view;
    expect((v.k, v.width, v.height), (4, 1000, 800), reason: 'one image pixel per screen pixel when zoomed out');
    expect(v.left + (v.width << v.k) / 2, closeTo(g.centreX, 16));
  });

  test('zoomed in, the image is one pixel per cell and the shader scales it up', () {
    final g = turing()
      ..zoom = 3
      ..centreX = 100
      ..centreY = 100;
    final v = g.view;
    expect((v.k, v.width, v.height), (0, 125, 100));
    expect((v.left, v.top), (37, 50)); // 100 - 125/2, floored
    expect(g.zoomLabel, '8 px a cell');
  });

  test('zooming keeps the cell under the pointer where it is', () {
    final g = turing()..fit();
    const focal = Offset(800, 150);
    double cellX(Offset p) => g.centreX + (p.dx - g.canvas.width / 2) * g.cellsPerPixel;
    double cellY(Offset p) => g.centreY + (p.dy - g.canvas.height / 2) * g.cellsPerPixel;
    final before = (cellX(focal), cellY(focal));
    g.zoomBy(2, focal);
    expect(g.zoom, -2);
    expect((cellX(focal), cellY(focal)), before);
    g.zoomBy(-1, focal);
    expect((cellX(focal), cellY(focal)), before);
  });

  test('zoom and jump stay in range; a drag moves the view by what it covers', () {
    final g = turing()..zoom = -4;
    g.zoomBy(-100, Offset.zero);
    expect(g.zoom, GiantMode.minZoom);
    g.zoomBy(100, Offset.zero);
    expect(g.zoom, GiantMode.maxZoom);
    g
      ..zoom = -2
      ..centreX = 0
      ..pan(10, 0);
    expect(g.centreX, -40, reason: 'at 4 cells a pixel, 10 pixels right shows 40 cells further left');
    g.jump = 20;
    expect((g.jumpShort, g.jumpLabel), ('1M', '×1,048,576'));
    g.limitedJump = 10;
    expect(g.jumpShort, '1K', reason: 'the jump actually taken, on the web');
  });

  test('the frame on screen follows a drag or zoom at once, until the next one arrives', () {
    final g = turing()
      ..zoom = -2
      ..centreX = 1000
      ..centreY = 500;
    g.shown = g.here;
    expect(g.shift(g.canvas), (scale: 1.0, dx: 0.0, dy: 0.0), reason: 'drawn where it is');
    g.pan(30, -10); // drag right and up by 30, 10 pixels
    expect(g.shift(g.canvas), (scale: 1.0, dx: 30.0, dy: -10.0), reason: 'the old frame moves with the pointer');
    g.shown = g.here;
    g.zoomBy(1, g.canvas.center(Offset.zero)); // twice as close, about the middle
    expect(g.shift(g.canvas), (scale: 2.0, dx: 0.0, dy: 0.0));
  });
}
