import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import 'theme.dart';

/// The board, letterboxed to its aspect ratio, painted by the glow pipeline.
/// Dragging draws (or erases) cells, unless [drawable] is off (Board only,
/// where a tap brings the controls back instead).
class LifeCanvas extends StatelessWidget {
  const LifeCanvas({super.key, required this.controller, required this.clock, required this.erase, this.drawable = true});

  final LifeController controller;
  final ValueNotifier<double> clock;
  final bool erase;
  final bool drawable;

  @override
  Widget build(BuildContext context) {
    if (controller.giant != null) return _GiantCanvas(controller: controller, clock: clock);
    return _BoardCanvas(controller: controller, clock: clock, erase: erase, drawable: drawable);
  }
}

/// A board, letterboxed. One finger or the mouse draws; two fingers (a
/// trackpad's scroll, a pinch) pan and zoom, and so does a mouse wheel. The
/// view stops at the board's edges.
class _BoardCanvas extends StatefulWidget {
  const _BoardCanvas({required this.controller, required this.clock, required this.erase, required this.drawable});

  final LifeController controller;
  final ValueNotifier<double> clock;
  final bool erase;
  final bool drawable;

  @override
  State<_BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends State<_BoardCanvas> {
  /// A one-pointer drag is drawing; a second finger turns it into a pan.
  bool _drawing = false;

  /// The pinch's scale at the last update, so each update zooms by its change.
  double _lastScale = 1;

  LifeController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // The board area's size, so a giant pattern loaded from here is fitted to it at once.
        WidgetsBinding.instance.addPostFrameCallback((_) => c.setGiantCanvas(box.biggest));
        final aspect = c.width / c.height;
        var w = box.maxWidth, h = w / aspect;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * aspect;
        }
        final size = Size(w, h);
        final view = c.boardView;

        void draw(Offset p) {
          final f = view.toBoard(p, size);
          c.paintCell((f.dx * c.width).floor(), (f.dy * c.height).floor(), !widget.erase);
        }

        void stopDrawing() {
          if (!_drawing) return;
          _drawing = false;
          c.endEdit();
        }

        Widget board = RepaintBoundary(
          child: CustomPaint(size: size, painter: _GlowPainter(c, widget.clock)),
        );
        board = Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              // A trackpad's two-finger scroll pans; a mouse wheel zooms at the pointer.
              if (e.kind == PointerDeviceKind.trackpad) {
                c.panBoard(-e.scrollDelta, size);
              } else if (e.scrollDelta.dy != 0) {
                c.zoomBoard(e.scrollDelta.dy < 0 ? 1.25 : 0.8, e.localPosition, size);
              }
            } else if (e is PointerScaleEvent) {
              c.zoomBoard(e.scale, e.localPosition, size); // a pinch, in a browser
            }
          },
          child: GestureDetector(
            onScaleStart: (d) async {
              _lastScale = 1;
              if (d.pointerCount != 1 || !widget.drawable) return;
              _drawing = true;
              await c.beginEdit();
              if (_drawing) draw(d.localFocalPoint);
            },
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) {
                if (_drawing) draw(d.localFocalPoint);
                return;
              }
              stopDrawing();
              c.panBoard(d.focalPointDelta, size);
              final ratio = d.scale / _lastScale;
              _lastScale = d.scale;
              if (ratio != 1) c.zoomBoard(ratio, d.localFocalPoint, size);
            },
            onScaleEnd: (_) => stopDrawing(),
            onTapDown: widget.drawable
                ? (d) async {
                    await c.beginEdit();
                    draw(d.localPosition);
                    c.endEdit();
                  }
                : null,
            child: board,
          ),
        );
        if (widget.drawable) board = MouseRegion(cursor: SystemMouseCursors.precise, child: board);
        return Center(child: board);
      },
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.controller, this.clock) : super(repaint: Listenable.merge([controller, clock]));

  final LifeController controller;
  final ValueNotifier<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final g = controller.giant;
    if (g == null) {
      final view = controller.boardView;
      if (!view.zoomed) return controller.pipeline.paint(canvas, size, clock.value);
      // Zoomed: the whole board drawn [zoom] times larger, clipped to the canvas.
      final o = view.origin(size);
      canvas
        ..save()
        ..clipRect(Offset.zero & size)
        ..translate(o.dx, o.dy);
      controller.pipeline.paint(canvas, size * view.zoom, clock.value);
      canvas.restore();
      return;
    }
    // The last frame, moved to where the view is now, until the next arrives.
    final s = g.shift(size);
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(size.width / 2 + s.dx, size.height / 2 + s.dy)
      ..scale(s.scale)
      ..translate(-size.width / 2, -size.height / 2);
    controller.pipeline.paint(canvas, size, clock.value);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => false;
}

/// A giant pattern on HashLife's endless plane: the whole board area is the
/// view. Drag to pan, scroll or pinch to zoom, or use the bar's zoom menu.
class _GiantCanvas extends StatefulWidget {
  const _GiantCanvas({required this.controller, required this.clock});

  final LifeController controller;
  final ValueNotifier<double> clock;

  @override
  State<_GiantCanvas> createState() => _GiantCanvasState();
}

class _GiantCanvasState extends State<_GiantCanvas> {
  /// Pinch scale since the last whole zoom step.
  double _pinch = 1;

  LifeController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        // After layout: telling the controller mid-build would rebuild the tree being built.
        WidgetsBinding.instance.addPostFrameCallback((_) => c.setGiantCanvas(size));
        final g = c.giant!;
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent && e.scrollDelta.dy != 0) c.zoomGiant(e.scrollDelta.dy < 0 ? 1 : -1, e.localPosition);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: GestureDetector(
                      onScaleStart: (_) => _pinch = 1,
                      onScaleUpdate: (d) {
                        if (d.focalPointDelta != Offset.zero) c.panGiant(d.focalPointDelta);
                        if (d.pointerCount < 2) return;
                        // Whole doublings: the plane is drawn at power-of-two zooms.
                        final ratio = d.scale / _pinch;
                        if (ratio > 1.6 || ratio < 1 / 1.6) {
                          c.zoomGiant(ratio > 1 ? 1 : -1, d.localFocalPoint);
                          _pinch = d.scale;
                        }
                      },
                      onDoubleTapDown: (d) => c.zoomGiant(1, d.localPosition),
                      onDoubleTap: () {},
                      child: CustomPaint(size: size, painter: _GlowPainter(c, widget.clock)),
                    ),
                  ),
                ),
              ),
              // A long name gives way.
              Positioned(
                left: 10,
                right: 10,
                top: 10,
                child: Align(alignment: Alignment.centerLeft, child: _Chip('${g.name} · HashLife, endless plane · ${g.zoomLabel}')),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: Neon.panelDecoration(radius: 8),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Neon.mono.copyWith(fontSize: 11, color: Neon.muted)),
  );
}
