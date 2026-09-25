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

/// The bar's magnifying glass: opens [ZoomControls], and stays open while
/// you press − and + so you can zoom a few steps in a row.
class ZoomMenu extends StatelessWidget {
  const ZoomMenu({super.key, required this.controller});

  final LifeController controller;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    style: const MenuStyle(backgroundColor: WidgetStatePropertyAll(Color(0xFF0B0E17))),
    menuChildren: [
      ListenableBuilder(listenable: controller, builder: (_, _) => ZoomControls(controller: controller)),
    ],
    builder: (context, menu, _) => IconButton(
      tooltip: 'Zoom · ${controller.zoomLabel}',
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      icon: const Icon(Icons.zoom_in_rounded),
      color: Neon.text,
    ),
  );
}
