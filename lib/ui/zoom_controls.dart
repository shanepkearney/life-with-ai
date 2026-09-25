import 'package:flutter/material.dart';

import '../app/life_controller.dart';
import 'theme.dart';

/// − Fit +, for a board or the endless plane alike: in the control bar, and
/// in the phone's ⚙ sheet.
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
          icon: const Icon(Icons.zoom_out_rounded, size: 20),
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
          icon: const Icon(Icons.zoom_in_rounded, size: 20),
        ),
      ],
    );
  }
}
