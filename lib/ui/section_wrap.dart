import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays sections out left to right, each whole, starting a new line when the
/// next one doesn't fit, with a divider between two sections on the same line
/// and none at a line's end. (A [Wrap] with dividers as children can't know
/// where its lines break, so one was always left dangling there.)
class SectionWrap extends MultiChildRenderObjectWidget {
  const SectionWrap({super.key, required super.children, required this.dividerColor, this.gap = 21, this.runSpacing = 6, this.dividerHeight = 24});

  /// Between two sections on a line; the divider is drawn in its middle.
  final double gap;
  final double runSpacing;
  final double dividerHeight;
  final Color dividerColor;

  @override
  RenderSectionWrap createRenderObject(BuildContext context) =>
      RenderSectionWrap(gap: gap, runSpacing: runSpacing, dividerHeight: dividerHeight, dividerColor: dividerColor);

  @override
  void updateRenderObject(BuildContext context, RenderSectionWrap renderObject) => renderObject
    ..gap = gap
    ..runSpacing = runSpacing
    ..dividerHeight = dividerHeight
    ..dividerColor = dividerColor;
}

class _SectionData extends ContainerBoxParentData<RenderBox> {}

class RenderSectionWrap extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _SectionData>, RenderBoxContainerDefaultsMixin<RenderBox, _SectionData> {
  RenderSectionWrap({required double gap, required double runSpacing, required double dividerHeight, required Color dividerColor})
    : _gap = gap,
      _runSpacing = runSpacing,
      _dividerHeight = dividerHeight,
      _dividerColor = dividerColor;

  double _gap, _runSpacing, _dividerHeight;
  Color _dividerColor;

  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  set runSpacing(double v) {
    if (v == _runSpacing) return;
    _runSpacing = v;
    markNeedsLayout();
  }

  set dividerHeight(double v) {
    if (v == _dividerHeight) return;
    _dividerHeight = v;
    markNeedsPaint();
  }

  set dividerColor(Color v) {
    if (v == _dividerColor) return;
    _dividerColor = v;
    markNeedsPaint();
  }

  /// Where each divider's centre goes, found in layout.
  final _dividers = <Offset>[];

  /// How many lines the sections took.
  int get lineCount => _lines;

  /// How many dividers were drawn: one fewer than the sections on each line.
  @visibleForTesting
  int get dividerCount => _dividers.length;
  int _lines = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SectionData) child.parentData = _SectionData();
  }

  List<RenderBox> get _children {
    final list = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      list.add(child);
      child = childAfter(child);
    }
    return list;
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    final children = _children;
    for (final c in children) {
      c.layout(BoxConstraints(maxWidth: maxWidth), parentUsesSize: true);
    }
    // Break into lines: a section goes on the current line if it fits there whole.
    final lines = <List<RenderBox>>[];
    var width = 0.0;
    for (final c in children) {
      final w = c.size.width;
      if (lines.isEmpty || width + _gap + w > maxWidth) {
        lines.add([c]);
        width = w;
      } else {
        lines.last.add(c);
        width += _gap + w;
      }
    }
    _dividers.clear();
    var y = 0.0, widest = 0.0;
    for (final line in lines) {
      final height = line.map((c) => c.size.height).reduce(max);
      var x = 0.0;
      for (final (i, c) in line.indexed) {
        if (i > 0) {
          _dividers.add(Offset(x + _gap / 2, y + height / 2));
          x += _gap;
        }
        (c.parentData! as _SectionData).offset = Offset(x, y + (height - c.size.height) / 2);
        x += c.size.width;
      }
      widest = max(widest, x);
      y += height + _runSpacing;
    }
    _lines = lines.length;
    size = constraints.constrain(Size(widest, lines.isEmpty ? 0 : y - _runSpacing));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()..color = _dividerColor;
    for (final d in _dividers) {
      context.canvas.drawRect(Rect.fromCenter(center: offset + d, width: 1, height: _dividerHeight), paint);
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  // All on one line at most; never narrower than the widest section.
  @override
  double computeMaxIntrinsicWidth(double height) {
    final children = _children;
    if (children.isEmpty) return 0;
    return children.map((c) => c.getMaxIntrinsicWidth(height)).reduce((a, b) => a + b) + _gap * (children.length - 1);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold(0.0, (w, c) => max(w, c.getMinIntrinsicWidth(height)));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    // The same line breaking as layout, measured without placing anything.
    final maxWidth = constraints.maxWidth;
    var lineWidth = 0.0, lineHeight = 0.0, widest = 0.0, height = 0.0;
    var first = true;
    for (final c in _children) {
      final s = c.getDryLayout(BoxConstraints(maxWidth: maxWidth));
      if (first || lineWidth + _gap + s.width > maxWidth) {
        if (!first) height += lineHeight + _runSpacing;
        lineWidth = s.width;
        lineHeight = s.height;
        first = false;
      } else {
        lineWidth += _gap + s.width;
        lineHeight = max(lineHeight, s.height);
      }
      widest = max(widest, lineWidth);
    }
    return constraints.constrain(Size(widest, first ? 0 : height + lineHeight));
  }
}
