/// Saves a PNG where the platform keeps downloads: a browser download on the
/// web, the Downloads folder on desktop. Returns where it went, for the toast.
library;

export 'save_png_io.dart' if (dart.library.js_interop) 'save_png_web.dart';
