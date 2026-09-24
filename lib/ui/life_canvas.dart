import 'package:flutter/material.dart';

import '../app/life_controller.dart';

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
    return LayoutBuilder(
      builder: (context, box) {
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
  void paint(Canvas canvas, Size size) => controller.pipeline.paint(canvas, size, clock.value);

  @override
  bool shouldRepaint(_GlowPainter old) => false;
}
