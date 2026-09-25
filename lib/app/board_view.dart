import 'dart:ui';

/// A board's zoom and pan: which part of it is on screen. At zoom 1 the whole
/// board shows. Zoomed in, the view stops at the board's edges.
class BoardView {
  static const maxZoom = 32.0;

  /// Screen pixels per board pixel at "the whole board fits": 1 to [maxZoom].
  double zoom = 1;

  /// The view's centre, as a fraction of the board's width and height.
  double cx = 0.5, cy = 0.5;

  bool get zoomed => zoom > 1;

  /// "×4" for the zoom readout.
  String get label => '×${zoom < 10 ? zoom.toStringAsFixed(zoom == zoom.roundToDouble() ? 0 : 1) : zoom.round()}';

  void fit() {
    zoom = 1;
    cx = cy = 0.5;
  }

  /// Zooms by [factor] around [focal], a point on a canvas of [size]: the
  /// part of the board under it stays under it.
  void zoomBy(double factor, Offset focal, Size size) {
    final under = toBoard(focal, size);
    zoom = (zoom * factor).clamp(1.0, maxZoom);
    cx = under.dx - (focal.dx / size.width - 0.5) / zoom;
    cy = under.dy - (focal.dy / size.height - 0.5) / zoom;
    _keepInside();
  }

  /// Moves the board by a drag of [delta] screen pixels.
  void pan(Offset delta, Size size) {
    cx -= delta.dx / size.width / zoom;
    cy -= delta.dy / size.height / zoom;
    _keepInside();
  }

  /// A point on the canvas as a fraction of the board, 0 to 1 each way.
  Offset toBoard(Offset p, Size size) => Offset(cx + (p.dx / size.width - 0.5) / zoom, cy + (p.dy / size.height - 0.5) / zoom);

  /// Where the whole board, drawn [zoom] times the canvas size, starts.
  Offset origin(Size size) => Offset((0.5 - cx * zoom) * size.width, (0.5 - cy * zoom) * size.height);

  void _keepInside() {
    final half = 0.5 / zoom;
    cx = cx.clamp(half, 1 - half);
    cy = cy.clamp(half, 1 - half);
  }
}
