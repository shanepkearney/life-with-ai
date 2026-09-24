import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'save_png.dart';

export 'save_png.dart';

/// Stores a finished PNG; [savePng] unless a test swaps it out.
typedef ScreenshotSaver = Future<SavedPng?> Function(Uint8List png, String fileName);

/// Renders the widget under [boundary] to PNG bytes, at least 2× so a shot
/// taken on a standard-density screen is still crisp enough for marketing.
Future<Uint8List> capturePng(GlobalKey boundary, {double minPixelRatio = 2}) async {
  final context = boundary.currentContext!;
  final render = context.findRenderObject()! as RenderRepaintBoundary;
  final ratio = math.max(View.of(context).devicePixelRatio, minPixelRatio);
  final image = await render.toImage(pixelRatio: ratio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// `life-with-ai-2026-09-24-153012.png`: sortable, and safe on every filesystem.
String screenshotFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'life-with-ai-${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.png';
}
