import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'full_screen.dart';

FullScreen platformFullScreen() => _BrowserFullScreen();

/// The browser's Fullscreen API on the whole page.
class _BrowserFullScreen extends FullScreen {
  _BrowserFullScreen() {
    web.document.addEventListener('fullscreenchange', _onChange);
  }

  late final JSFunction _onChange = ((web.Event _) => active.value = web.document.fullscreenElement != null).toJS;

  @override
  bool get supported => web.document.fullscreenEnabled;

  @override
  final ValueNotifier<bool> active = ValueNotifier(web.document.fullscreenElement != null);

  @override
  Future<void> set(bool on) async {
    try {
      if (on && web.document.fullscreenElement == null) {
        await web.document.documentElement!.requestFullscreen().toDart;
      } else if (!on && web.document.fullscreenElement != null) {
        await web.document.exitFullscreen().toDart;
      }
    } catch (_) {
      // Refused: not in response to a click or key press, or not allowed here.
    }
  }

  @override
  void dispose() => web.document.removeEventListener('fullscreenchange', _onChange);
}
