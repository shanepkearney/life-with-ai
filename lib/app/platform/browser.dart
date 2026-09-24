/// What the web page can tell about the visitor's machine. Off the web
/// (the macOS app itself, tests) nothing applies.
library;

export 'browser_io.dart' if (dart.library.js_interop) 'browser_web.dart';
