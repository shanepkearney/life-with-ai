import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where the file landed, or null when this platform has no Downloads folder.
typedef SavedPng = ({String label, Uri? file});

Future<SavedPng?> savePng(Uint8List png, String fileName) async {
  // The sandboxed macOS app reaches ~/Downloads through its downloads entitlement.
  final dir = await getDownloadsDirectory();
  if (dir == null) return null;
  var file = File('${dir.path}/$fileName');
  // Never overwrite: two shots in the same second get "-2", "-3", ….
  for (var n = 2; file.existsSync(); n++) {
    file = File('${dir.path}/${fileName.replaceFirst('.png', '-$n.png')}');
  }
  await file.writeAsBytes(png, flush: true);
  return (label: 'Downloads', file: file.uri);
}
