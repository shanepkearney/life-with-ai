import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import 'theme.dart';

/// − Fit +, for a board or the endless plane alike: in the bar's zoom menu,
/// and in the phone's ⚙ sheet.
class ZoomControls extends StatelessWidget {
  const ZoomControls({super.key, required this.controller});

  final LifeController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Zoom out (−)',
          visualDensity: VisualDensity.compact,
          onPressed: c.canZoomOut ? c.zoomOut : null,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        Tooltip(
          message: c.giant != null ? 'Fit the pattern to the view' : 'Show the whole board',
          child: TextButton(
            onPressed: c.canFit ? c.fitView : null,
            style: TextButton.styleFrom(foregroundColor: Neon.cyan, visualDensity: VisualDensity.compact),
            child: Text('Fit', style: Neon.mono.copyWith(fontSize: 12, color: c.canFit ? Neon.cyan : Neon.muted)),
          ),
        ),
        IconButton(
          tooltip: 'Zoom in (+)',
          visualDensity: VisualDensity.compact,
          onPressed: c.canZoomIn ? c.zoomIn : null,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    );
  }
}

/// The bar's magnifying glass: opens [ZoomControls] just above itself (the bar
/// sits along the bottom), and keeps them open while you press − and + so you
/// can zoom a few steps in a row. A click anywhere else, or the glass again,
/// closes them.
class ZoomMenu extends StatefulWidget {
  const ZoomMenu({super.key, required this.controller});

  final LifeController controller;

  @override
  State<ZoomMenu> createState() => _ZoomMenuState();
}

class _ZoomMenuState extends State<ZoomMenu> {
  final _popup = OverlayPortalController();
  final _link = LayerLink();

  /// The glass and its popup are one region: a click in either isn't "outside".
  final _region = Object();

  final _open = ValueNotifier(false);

  static const _fill = Color(0xFF0B0E17);

  void _toggle() {
    if (_open.value) return _close();
    _popup.show();
    _open.value = true;
  }

  void _close() {
    _popup.hide();
    _open.value = false;
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TapRegion(
    groupId: _region,
    onTapOutside: (_) => _close(),
    child: CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _popup,
        overlayChildBuilder: (_) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            // Its bottom edge on the glass's top edge, centred on it.
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -2),
            child: TapRegion(
              groupId: _region,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Solid, with a bright edge and a shadow: over a busy board a see-through panel disappears.
                    Container(
                      decoration: BoxDecoration(
                        color: _fill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Neon.cyan.withValues(alpha: 0.6)),
                        boxShadow: [
                          const BoxShadow(color: Colors.black, blurRadius: 18, spreadRadius: 2),
                          BoxShadow(color: Neon.cyan.withValues(alpha: 0.25), blurRadius: 12),
                        ],
                      ),
                      child: ListenableBuilder(listenable: widget.controller, builder: (_, _) => ZoomControls(controller: widget.controller)),
                    ),
                    // A pointer down to the glass it came from.
                    const CustomPaint(size: Size(16, 7), painter: _Pointer()),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Lit while open, like the play button while playing.
        child: ListenableBuilder(
          listenable: _open,
          builder: (_, _) => IconButton(
            tooltip: 'Zoom · ${widget.controller.zoomLabel}',
            onPressed: _toggle,
            icon: Icon(Icons.zoom_in_rounded, shadows: _open.value ? const [Shadow(color: Neon.cyan, blurRadius: 12)] : null),
            color: _open.value ? Neon.cyan : Neon.text,
          ),
        ),
      ),
    ),
  );
}

/// A small triangle pointing down, the popup's own fill with its edge.
class _Pointer extends CustomPainter {
  const _Pointer();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas
      ..drawPath(path..close(), Paint()..color = _ZoomMenuState._fill)
      ..drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(size.width, 0),
        Paint()
          ..color = Neon.cyan.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke,
      );
  }

  @override
  bool shouldRepaint(_Pointer old) => false;
}
