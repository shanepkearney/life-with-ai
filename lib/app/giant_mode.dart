import 'dart:math';
import 'dart:ui';

import '../engine/giant_runner.dart';

/// A pattern too big for any board (Paul Rendell's 12,699 x 12,652-cell
/// Turing machine), running on HashLife's endless plane in the main board
/// area: what part of the plane is on screen, at what zoom, and how far each
/// step jumps.
class GiantMode {
  GiantMode(this.name, this.runner);

  final String name;
  final GiantRunner runner;

  int generation = 0;
  int population = 0;
  ({int x, int y, int width, int height})? bounds;

  /// The plane coordinates at the middle of the screen.
  double centreX = 0, centreY = 0;

  /// 2^zoom screen pixels per cell: 3 is 8 pixels a cell, -4 is 16 cells a pixel.
  int zoom = 0;
  static const minZoom = -14, maxZoom = 5;

  /// The board area's size, in logical pixels.
  Size canvas = const Size(800, 600);

  /// Refit whenever the board area changes size, until the view is moved by hand.
  bool autoFit = true;

  /// Each step moves on 2^jump generations. The Turing machine barely
  /// changes in a few hundred, so a true giant starts at a thousand; a
  /// small pattern on the plane (see [LifeController.openGiant]) at 1.
  int jump = giantJump;
  static const giantJump = 10;
  static const maxJump = 24;

  /// Slower than one generation a step as fast as HashLife goes: steps of one
  /// generation paced at [paces]\[pace\] a second, like a board's speed. Null
  /// runs flat out, [jump] generations a step.
  int? pace;
  static const paces = [1, 2, 4, 8, 15, 30, 60];

  /// Generations a second while paced, else null.
  int? get rate => pace == null ? null : paces[pace!];

  /// One slider for both: the paced speeds below zero, then the jumps.
  int get speed => pace == null ? jump : pace! - paces.length;
  static const minSpeed = -7; // -paces.length

  /// On the web, where a jump runs on the UI thread, the jump actually taken
  /// shrinks while steps are slow, so the page stays responsive.
  int? limitedJump;
  int get effectiveJump => min(jump, limitedJump ?? jump);

  /// Cells per screen pixel.
  double get cellsPerPixel => pow(2, -zoom).toDouble();

  /// Where the view was when the frame on screen was drawn.
  ({double x, double y, double cellsPerPixel})? shown;

  ({double x, double y, double cellsPerPixel}) get here => (x: centreX, y: centreY, cellsPerPixel: cellsPerPixel);

  /// Moves and scales the frame on screen to where the view is now, so a drag
  /// or zoom answers at once and the fresh frame, drawn in the background,
  /// just sharpens it. Returns the canvas transform: scale about the middle,
  /// then shift.
  ({double scale, double dx, double dy}) shift(Size size) {
    final s = shown;
    if (s == null) return (scale: 1, dx: 0, dy: 0);
    final now = cellsPerPixel;
    return (scale: s.cellsPerPixel / now, dx: (s.x - centreX) / now, dy: (s.y - centreY) / now);
  }

  /// The part of the plane to draw: at 1:1 or closer, one image pixel per
  /// cell (the shader scales it up); further out, one per screen pixel, each
  /// summing 2^k x 2^k cells.
  GiantView get view {
    final k = zoom >= 0 ? 0 : -zoom;
    final scale = zoom >= 0 ? pow(2, -zoom).toDouble() : 1.0; // image pixels per screen pixel
    final w = max(1, min(2048, (canvas.width * scale).ceil()));
    final h = max(1, min(2048, (canvas.height * scale).ceil()));
    final cellW = w * (1 << k), cellH = h * (1 << k);
    return (left: (centreX - cellW / 2).floor(), top: (centreY - cellH / 2).floor(), k: k, width: w, height: h);
  }

  /// Centres the pattern, at the closest zoom that shows all of it.
  void fit() {
    autoFit = true;
    final b = bounds;
    if (b == null) return;
    centreX = b.x + b.width / 2;
    centreY = b.y + b.height / 2;
    final fits = min(canvas.width / b.width, canvas.height / b.height);
    zoom = (log(fits) / ln2).floor().clamp(minZoom, maxZoom);
  }

  /// Moves the view by a drag of [dx], [dy] screen pixels.
  void pan(double dx, double dy) {
    autoFit = false;
    centreX -= dx * cellsPerPixel;
    centreY -= dy * cellsPerPixel;
  }

  /// Zooms in (positive [steps]) or out, keeping the cell under [focal] (a
  /// point in the board area) where it is.
  void zoomBy(int steps, Offset focal) {
    autoFit = false;
    final next = (zoom + steps).clamp(minZoom, maxZoom);
    if (next == zoom) return;
    final fx = focal.dx - canvas.width / 2, fy = focal.dy - canvas.height / 2;
    final before = cellsPerPixel;
    zoom = next;
    final after = cellsPerPixel;
    centreX += fx * (before - after);
    centreY += fy * (before - after);
  }

  /// "8 px a cell", "1:1" or "16 cells a pixel", for the zoom readout.
  String get zoomLabel => zoom == 0
      ? '1:1'
      : zoom > 0
      ? '${1 << zoom} px a cell'
      : '${_grouped(1 << -zoom)} cells a pixel';

  /// "8 px/cell", "1:1" or "16 cells/px", for the HUD.
  String get zoomShort => zoom == 0
      ? '1:1'
      : zoom > 0
      ? '${1 << zoom} px/cell'
      : '${_grouped(1 << -zoom)} cells/px';

  /// "1K" for the jump slider's tight label: 1 to 512, then K, then M.
  String get jumpShort {
    final n = 1 << effectiveJump;
    return n < 1024 ? '$n' : (n < 1 << 20 ? '${n >> 10}K' : '${n >> 20}M');
  }

  /// "Speed 15/s" or "Jump ×  1K": one width, for the bar's tight label.
  String get speedShort => rate != null ? 'Speed ${'$rate'.padLeft(2)}/s' : 'Jump ×${jumpShort.padLeft(4)}';

  /// "15 generations a second" or "×1,024 generations a step".
  String get speedLabel => rate != null ? '$rate generations a second' : '$jumpLabel generations a step';

  /// "×1,024" for the jump readout.
  String get jumpLabel => '×${_grouped(1 << effectiveJump)}';

  static String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}
