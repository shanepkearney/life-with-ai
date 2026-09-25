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
    return LayoutBuilder(
      builder: (context, box) {
        // The board area's size, so a giant pattern loaded from here is fitted to it at once.
        WidgetsBinding.instance.addPostFrameCallback((_) => controller.setGiantCanvas(box.biggest));
        final aspect = controller.width / controller.height;
        var w = box.maxWidth, h = w / aspect;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * aspect;
        }
        final size = Size(w, h);

        void draw(Offset p) => controller.paintCell((p.dx / w * controller.width).floor(), (p.dy / h * controller.height).floor(), !erase);

        final board = RepaintBoundary(
          child: CustomPaint(size: size, painter: _GlowPainter(controller, clock)),
        );
        if (!drawable) return Center(child: board);
        return Center(
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            child: GestureDetector(
              onPanStart: (d) async {
                await controller.beginEdit();
                draw(d.localPosition);
              },
              onPanUpdate: (d) => draw(d.localPosition),
              onPanEnd: (_) => controller.endEdit(),
              onTapDown: (d) async {
                await controller.beginEdit();
                draw(d.localPosition);
                controller.endEdit();
              },
              child: board,
            ),
          ),
        );
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
    if (g == null) return controller.pipeline.paint(canvas, size, clock.value);
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
/// view. Drag to pan, scroll or pinch to zoom, or use the − Fit + buttons.
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
              // Leaves room for the zoom buttons on the right; a long name gives way.
              Positioned(
                left: 10,
                right: 150,
                top: 10,
                child: Align(alignment: Alignment.centerLeft, child: _Chip('${g.name} · HashLife, endless plane · ${g.zoomLabel}')),
              ),
              // Top right: messages appear along the bottom of the board, and would cover them there.
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  decoration: Neon.panelDecoration(radius: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zoom out (−)',
                        visualDensity: VisualDensity.compact,
                        onPressed: g.zoom > -14 ? () => c.zoomGiant(-1, size.center(Offset.zero)) : null,
                        icon: const Icon(Icons.remove_rounded, size: 18),
                      ),
                      TextButton(
                        onPressed: c.fitGiant,
                        style: TextButton.styleFrom(foregroundColor: Neon.cyan, visualDensity: VisualDensity.compact),
                        child: Text('Fit', style: Neon.mono.copyWith(fontSize: 12, color: Neon.cyan)),
                      ),
                      IconButton(
                        tooltip: 'Zoom in (+)',
                        visualDensity: VisualDensity.compact,
                        onPressed: g.zoom < 5 ? () => c.zoomGiant(1, size.center(Offset.zero)) : null,
                        icon: const Icon(Icons.add_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
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
