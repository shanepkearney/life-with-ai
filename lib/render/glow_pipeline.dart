import 'dart:ui' as ui;

import 'shaders.dart';

/// Turns a one-pixel-per-cell board image into the glowing picture on screen.
///
/// [update] runs once per simulated frame and maintains two derived textures:
///  * trail — a fading persistence buffer (neon comet tails),
///  * density — a quarter-resolution map of how crowded each region is (hotspots).
/// [paint] then composites board + trail + density at display resolution.
class GlowPipeline {
  GlowPipeline(this._shaders);

  final Shaders _shaders;
  ui.Image? _state, _trail, _density;
  int _w = 0, _h = 0;

  double trailDecay = 0.90;
  double glow = 1.0;

  bool get ready => _state != null;

  /// Forgets the comet tails, so a newly loaded board doesn't glow with the
  /// ghost of the one it replaced.
  void clearTrail() {
    _trail?.dispose();
    _trail = null;
  }

  void update(ui.Image state) {
    if (_trail == null || state.width != _w || state.height != _h) {
      _w = state.width;
      _h = state.height;
      _trail?.dispose();
      _trail = blackImage(_w, _h);
    }
    _state?.dispose();
    _state = state.clone();

    final trail = _shaders.trail.fragmentShader()
      ..setFloat(0, _w.toDouble())
      ..setFloat(1, _h.toDouble())
      ..setFloat(2, trailDecay)
      ..setImageSampler(0, _state!)
      ..setImageSampler(1, _trail!);
    final nextTrail = renderPass(trail, _w, _h);
    _trail!.dispose();
    _trail = nextTrail;

    final dw = (_w / 4).ceil(), dh = (_h / 4).ceil();
    final density = _shaders.density.fragmentShader()
      ..setFloat(0, dw.toDouble())
      ..setFloat(1, dh.toDouble())
      ..setFloat(2, _w.toDouble())
      ..setFloat(3, _h.toDouble())
      ..setImageSampler(0, _state!, filterQuality: ui.FilterQuality.low);
    _density?.dispose();
    _density = renderPass(density, dw, dh);
  }

  void paint(ui.Canvas canvas, ui.Size size, double seconds) {
    if (!ready) return;
    final shader = _shaders.composite.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, _w.toDouble())
      ..setFloat(3, _h.toDouble())
      ..setFloat(4, seconds)
      ..setFloat(5, glow)
      ..setImageSampler(0, _state!)
      ..setImageSampler(1, _trail!, filterQuality: ui.FilterQuality.low)
      ..setImageSampler(2, _density!, filterQuality: ui.FilterQuality.low);
    canvas.drawRect(ui.Offset.zero & size, ui.Paint()..shader = shader);
  }

  void dispose() {
    _state?.dispose();
    _trail?.dispose();
    _density?.dispose();
  }
}
