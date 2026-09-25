import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import 'screen_board.dart';
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

/// The top bar's magnifying glass: opens [ZoomControls] below itself, and keeps
/// them open while you press − and + so you can zoom a few steps in a row.
class ZoomMenu extends StatelessWidget {
  const ZoomMenu({super.key, required this.controller});

  final LifeController controller;

  @override
  Widget build(BuildContext context) => BarPopup(
    icon: Icons.zoom_in_rounded,
    tooltip: 'Zoom · ${controller.zoomLabel}',
    builder: (_) => ListenableBuilder(listenable: controller, builder: (_, _) => ZoomControls(controller: controller)),
  );
}

/// The board's size as an icon in the top bar: its choices open below it, the current one lit.
class SizeMenu extends StatelessWidget {
  const SizeMenu({super.key, required this.controller});

  final LifeController controller;

  @override
  Widget build(BuildContext context) {
    final sizes = boardSizeChoices(context, controller.boardSize, phone: false);
    return BarPopup(
    icon: Icons.aspect_ratio_rounded,
    tooltip: 'Board size · ${controller.boardSize.label}',
    builder: (close) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in sizes)
              TextButton(
                onPressed: () {
                  close();
                  if (s != controller.boardSize) controller.setBoardSize(s);
                },
                style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16)),
                child: Text(s.label, style: Neon.mono.copyWith(color: s == controller.boardSize ? Neon.cyan : Neon.text)),
              ),
          ],
        ),
      ),
    ),
  );
  }
}

/// An icon in the top bar, styled like its neighbours, that opens a panel
/// just below itself. The icon is lit while it's open; a click anywhere else,
/// or the icon again, closes it, and so can the panel ([builder]'s `close`).
class BarPopup extends StatefulWidget {
  const BarPopup({super.key, required this.icon, required this.tooltip, required this.builder});

  final IconData icon;
  final String tooltip;
  final Widget Function(VoidCallback close) builder;

  @override
  State<BarPopup> createState() => _BarPopupState();
}

class _BarPopupState extends State<BarPopup> {
  final _popup = OverlayPortalController();
  final _link = LayerLink();

  /// The icon and its panel are one region: a click in either isn't "outside".
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
            // Its top edge on the icon's bottom edge, centred on it.
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 2),
            child: TapRegion(
              groupId: _region,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A pointer up to the icon it came from.
                    const CustomPaint(size: Size(16, 7), painter: _Pointer()),
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
                      child: widget.builder(_close),
                    ),
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
            tooltip: widget.tooltip,
            onPressed: _toggle,
            // Compact, 18px and muted, like the top bar's other icons.
            visualDensity: VisualDensity.compact,
            icon: Icon(widget.icon, size: 18, shadows: _open.value ? const [Shadow(color: Neon.cyan, blurRadius: 12)] : null),
            color: _open.value ? Neon.cyan : Neon.muted,
          ),
        ),
      ),
    ),
  );
}

/// A small triangle pointing up, the popup's own fill with its edge.
class _Pointer extends CustomPainter {
  const _Pointer();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..translate(0, size.height)
      ..scale(1, -1);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas
      ..drawPath(path..close(), Paint()..color = _BarPopupState._fill)
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
