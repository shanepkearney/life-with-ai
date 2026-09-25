import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

typedef SavedPng = ({String label, Uri? file});

Future<SavedPng?> savePng(Uint8List png, String fileName) => saveDownload(png, fileName, 'image/png');

/// Any file, as a browser download.
Future<SavedPng?> saveDownload(Uint8List bytes, String fileName, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Revoke after the browser has started the download, not before.
  Future<void>.delayed(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
  return (label: 'your downloads', file: null);
}
