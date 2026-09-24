import 'package:flutter/material.dart';

import 'theme.dart';

/// A bottom sheet that peeks at [peekHeight] and can be dragged (or tapped)
/// up to half or nearly full height, over the board. Used for the assistant
/// on phones, so the board stays visible while you chat.
class MobileSheet extends StatefulWidget {
  const MobileSheet({super.key, required this.builder, required this.peekHeight, this.startOpen = false});

  /// Start half open instead of resting, e.g. when there's something to see
  /// in the sheet straight away (a seed someone shared).
  final bool startOpen;

  /// Builds the sheet's content. [expanded] is false while it rests at
  /// [peekHeight], so the content can keep that state uncluttered; [open]
  /// lifts it, e.g. when a tab in the resting bar is tapped.
  final Widget Function(BuildContext context, bool expanded, VoidCallback open) builder;
  final double peekHeight;

  @override
  State<MobileSheet> createState() => _MobileSheetState();
}

enum _Snap { peek, half, full }

class _MobileSheetState extends State<MobileSheet> {
  static const _handle = 28.0;

  /// The open panel's fixed parts (tabs, the Assistant toolbar, the message
  /// box, dividers) need ~162px; below this the resting tabs are shown instead.
  static const _fullContentMinHeight = 190.0;
  double? _dragHeight; // non-null while the finger is down
  late _Snap _snap = widget.startOpen ? _Snap.half : _Snap.peek;

  double _heightFor(_Snap s, double available) => switch (s) {
    _Snap.peek => widget.peekHeight,
    _Snap.half => available * 0.5,
    _Snap.full => available * 0.92,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final available = box.maxHeight;
        final height = (_dragHeight ?? _heightFor(_snap, available)).clamp(widget.peekHeight, available * 0.92);
        void toggle() => setState(() => _snap = _snap == _Snap.peek ? _Snap.half : _Snap.peek);
        void open() {
          if (_snap == _Snap.peek) setState(() => _snap = _Snap.half);
        }

        void dragStart(DragStartDetails _) => setState(() => _dragHeight = height);
        void dragUpdate(DragUpdateDetails d) =>
            setState(() => _dragHeight = (_dragHeight! - d.delta.dy).clamp(widget.peekHeight, available * 0.92));
        void dragEnd(DragEndDetails d) => setState(() {
          _snap = _nearest(_dragHeight!, -(d.primaryVelocity ?? 0), available);
          _dragHeight = null;
        });
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: _dragHeight == null ? const Duration(milliseconds: 220) : Duration.zero,
                curve: Curves.easeOutCubic,
                height: height,
                decoration: BoxDecoration(
                  color: const Color(0xFA0B0E17),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  border: const Border(top: BorderSide(color: Neon.border)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24)],
                ),
                child: Column(
                  children: [
                    Semantics(
                      button: true,
                      label: _snap == _Snap.peek ? 'Expand the assistant' : 'Collapse the assistant',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: toggle,
                        onVerticalDragStart: dragStart,
                        onVerticalDragUpdate: dragUpdate,
                        onVerticalDragEnd: dragEnd,
                        child: SizedBox(
                          height: _handle,
                          width: double.infinity,
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(color: Neon.muted.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Decided from the space the content actually has this frame, not the
                    // height the sheet is animating towards: switching early would squeeze
                    // the full panel into a sheet still near its resting size.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, content) {
                          final expanded = content.maxHeight >= _fullContentMinHeight;
                          // The wrapper stays in the tree in both states, with its gestures
                          // switched off when open: removing it would rebuild the content
                          // from scratch and lose its state (the chosen tab, a half-typed message).
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            // At rest the whole bar drags; taps go to the content's tabs.
                            onVerticalDragStart: expanded ? null : dragStart,
                            onVerticalDragUpdate: expanded ? null : dragUpdate,
                            onVerticalDragEnd: expanded ? null : dragEnd,
                            child: widget.builder(context, expanded, open),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// A flick picks the next stop in its direction; otherwise the closest stop wins.
  _Snap _nearest(double h, double upVelocity, double available) {
    final closest = _Snap.values.reduce((a, b) => (h - _heightFor(a, available)).abs() < (h - _heightFor(b, available)).abs() ? a : b);
    if (upVelocity.abs() < 700) return closest;
    final i = (closest.index + (upVelocity > 0 ? 1 : -1)).clamp(0, _Snap.values.length - 1);
    return _Snap.values[i];
  }
}
