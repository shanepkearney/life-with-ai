import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where the file landed, or null when this platform has no Downloads folder.
typedef SavedPng = ({String label, Uri? file});

Future<SavedPng?> savePng(Uint8List png, String fileName) => saveDownload(png, fileName, 'image/png');

/// Any file, into Downloads.
Future<SavedPng?> saveDownload(Uint8List bytes, String fileName, String mimeType) async {
  // The sandboxed macOS app reaches ~/Downloads through its downloads entitlement.
  final dir = await getDownloadsDirectory();
  if (dir == null) return null;
  var file = File('${dir.path}/$fileName');
  // Never overwrite: a second copy gets "-2", "-3", … before its extension.
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName, ext = dot > 0 ? fileName.substring(dot) : '';
  for (var n = 2; file.existsSync(); n++) {
    file = File('${dir.path}/$stem-$n$ext');
  }
  await file.writeAsBytes(bytes, flush: true);
  return (label: 'Downloads', file: file.uri);
}
