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
    // Standard-size buttons, coloured like the control bar's others, and spaced like them.
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        IconButton(
          tooltip: 'Zoom out (−)',
          onPressed: c.canZoomOut ? c.zoomOut : null,
          color: Neon.text,
          disabledColor: Neon.muted.withValues(alpha: 0.4),
          icon: const Icon(Icons.zoom_out_rounded),
        ),
        Tooltip(
          message: c.giant != null ? 'Fit the pattern to the view' : 'Show the whole board',
          child: TextButton(
            onPressed: c.canFit ? c.fitView : null,
            style: TextButton.styleFrom(foregroundColor: Neon.cyan, minimumSize: const Size(48, 48)),
            child: Text('Fit', style: Neon.mono.copyWith(fontSize: 12, color: c.canFit ? Neon.cyan : Neon.muted)),
          ),
        ),
        IconButton(
          tooltip: 'Zoom in (+)',
          onPressed: c.canZoomIn ? c.zoomIn : null,
          color: Neon.text,
          disabledColor: Neon.muted.withValues(alpha: 0.4),
          icon: const Icon(Icons.zoom_in_rounded),
        ),
      ],
    );
  }
}
