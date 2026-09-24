import 'package:web/web.dart' as web;

/// A browser on a Mac. iPads also say "Macintosh" (they ask for desktop
/// sites), but they're touch devices and can't run a macOS app.
bool get isMacBrowser {
  final nav = web.window.navigator;
  return nav.userAgent.contains('Macintosh') && nav.maxTouchPoints <= 1;
}
