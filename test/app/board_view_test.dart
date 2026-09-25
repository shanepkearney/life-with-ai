import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/board_view.dart';

void main() {
  const size = Size(800, 600);

  test('at zoom 1 the canvas is the whole board', () {
    final v = BoardView();
    expect(v.toBoard(Offset.zero, size), Offset.zero);
    expect(v.toBoard(const Offset(800, 600), size), const Offset(1, 1));
    expect(v.origin(size), Offset.zero);
    expect(v.zoomed, isFalse);
  });

  test('zooming keeps the part of the board under the pointer where it is', () {
    final v = BoardView();
    const pointer = Offset(200, 150);
    final under = v.toBoard(pointer, size);
    v.zoomBy(4, pointer, size);
    expect(v.zoom, 4);
    expect(v.toBoard(pointer, size), under);
    // And the drawing agrees: that board point is drawn under the pointer.
    final o = v.origin(size);
    expect(o + Offset(under.dx * size.width * v.zoom, under.dy * size.height * v.zoom), pointer);
  });

  test('the view stops at the edges, and zoom stays between 1 and the maximum', () {
    final v = BoardView()..zoomBy(2, const Offset(400, 300), size);
    v.pan(const Offset(10000, 10000), size);
    expect((v.cx, v.cy), (0.25, 0.25), reason: 'the top-left corner, not past it');
    expect(v.toBoard(Offset.zero, size), Offset.zero);
    v.zoomBy(1000, Offset.zero, size);
    expect(v.zoom, BoardView.maxZoom);
    v.zoomBy(0.0001, Offset.zero, size);
    expect((v.zoom, v.cx, v.cy), (1.0, 0.5, 0.5), reason: 'all the way out is the whole board, centred');
    expect(v.label, '×1');
  });
}
