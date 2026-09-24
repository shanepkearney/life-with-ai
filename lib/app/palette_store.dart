import 'package:shared_preferences/shared_preferences.dart';

import '../render/board_palette.dart';

/// Keeps the user's board colors on this device, in the same form a share
/// link uses ([BoardPalette.wire]). Neon, the default, is stored as nothing.
abstract final class PaletteStore {
  static const _key = 'board_palette';

  static Future<BoardPalette> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return BoardPalette.fromWire(prefs.getString(_key)) ?? BoardPalette.neon;
    } catch (_) {
      return BoardPalette.neon; // storage unavailable (private browsing): the default
    }
  }

  static Future<void> save(BoardPalette palette) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wire = palette.wire;
      wire == null ? await prefs.remove(_key) : await prefs.setString(_key, wire);
    } catch (_) {}
  }
}
