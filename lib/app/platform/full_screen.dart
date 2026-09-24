/// Full screen: the browser's Fullscreen API on the web, the window's own
/// full screen in the macOS app. See [FullScreen].
library;

import 'package:flutter/foundation.dart';

import 'full_screen_io.dart' if (dart.library.js_interop) 'full_screen_web.dart' as impl;

/// Whether the app fills the screen, and a way to change it. [active] also
/// follows changes made outside the app: Esc in a browser, the green button
/// or ⌃⌘F on a Mac.
abstract class FullScreen {
  /// Whether this platform can go full screen at all (an iPhone's browser can't).
  bool get supported;

  ValueListenable<bool> get active;

  /// Asks to enter or leave full screen. A browser may refuse (it only allows
  /// it in response to a click or key press), so check [active] afterwards.
  Future<void> set(bool on);

  void dispose() {}

  /// The real thing for the platform the app is running on.
  static FullScreen platform() => impl.platformFullScreen();
}

/// Never full screen: for platforms without it, and a base for tests.
class NoFullScreen extends FullScreen {
  @override
  bool get supported => false;

  @override
  final ValueNotifier<bool> active = ValueNotifier(false);

  @override
  Future<void> set(bool on) async {}
}
