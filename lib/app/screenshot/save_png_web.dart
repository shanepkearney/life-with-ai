import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

typedef SavedPng = ({String label, Uri? file});

Future<SavedPng?> savePng(Uint8List png, String fileName) async {
  final blob = web.Blob([png.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
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
