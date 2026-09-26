/// Tells the web page about an error the app caught, so the page can show its
/// friendly notice (and, in released builds, count it). Off the web it does nothing.
library;

export 'error_report_io.dart' if (dart.library.js_interop) 'error_report_web.dart';
