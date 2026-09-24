import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The board's colors: five heat stops, from the faint glow of a lone cell
/// ([heat] first) to the white-hot core of a crowd ([heat] last), and the
/// background behind them. The composite shader blends along the stops.
@immutable
class BoardPalette {
  /// [heat] always has five colors.
  const BoardPalette({required this.id, required this.name, required this.heat, required this.background});

  /// A custom palette, from the colors editor or a share link.
  BoardPalette.custom(List<Color> heat, Color background) : this(id: null, name: 'Custom', heat: List.unmodifiable(heat), background: background);

  /// A preset's id (also its share-link form), or null for a custom palette.
  final String? id;
  final String name;
  final List<Color> heat;
  final Color background;

  bool get isPreset => id != null;

  /// The app's own theme, exactly as the shader always drew it.
  static final neon = BoardPalette(
    id: 'neon',
    name: 'Neon',
    heat: [
      Color.from(alpha: 1, red: 0.16, green: 0.06, blue: 0.55), // deep violet
      Color.from(alpha: 1, red: 0.00, green: 0.85, blue: 1.00), // electric cyan
      Color.from(alpha: 1, red: 1.00, green: 0.12, blue: 0.72), // magenta
      Color.from(alpha: 1, red: 1.00, green: 0.62, blue: 0.08), // amber
      Color.from(alpha: 1, red: 1.00, green: 0.98, blue: 0.88), // white-hot
    ],
    background: Color.from(alpha: 1, red: 0.008, green: 0.01, blue: 0.03),
  );

  static const ember = BoardPalette(
    id: 'ember',
    name: 'Ember',
    heat: [Color(0xFF4A0D06), Color(0xFFB8230F), Color(0xFFFF5A1F), Color(0xFFFFB627), Color(0xFFFFF4D6)],
    background: Color(0xFF060201),
  );

  static const ocean = BoardPalette(
    id: 'ocean',
    name: 'Ocean',
    heat: [Color(0xFF0B1F5C), Color(0xFF0A6BD6), Color(0xFF00C2C7), Color(0xFF7CF5D4), Color(0xFFF0FFFB)],
    background: Color(0xFF01040B),
  );

  static const forest = BoardPalette(
    id: 'forest',
    name: 'Forest',
    heat: [Color(0xFF123A18), Color(0xFF238A34), Color(0xFF86D23F), Color(0xFFEAD64E), Color(0xFFFBF7DC)],
    background: Color(0xFF020502),
  );

  static const aurora = BoardPalette(
    id: 'aurora',
    name: 'Aurora',
    heat: [Color(0xFF2A0F5C), Color(0xFF2E6BFF), Color(0xFF1FE0A0), Color(0xFFC8FF5A), Color(0xFFF5FFF0)],
    background: Color(0xFF02030A),
  );

  static const mono = BoardPalette(
    id: 'mono',
    name: 'Mono',
    heat: [Color(0xFF2A2A2A), Color(0xFF5E5E5E), Color(0xFF9C9C9C), Color(0xFFD4D4D4), Color(0xFFFFFFFF)],
    background: Color(0xFF000000),
  );

  static final presets = [neon, ember, ocean, forest, aurora, mono];

  /// This palette with one color changed: stop [index] 0-4, or 5 for the background.
  BoardPalette withColor(int index, Color color) =>
      BoardPalette.custom([for (var i = 0; i < 5; i++) i == index ? color : heat[i]], index == 5 ? color : background);

  /// The six colors in shader order: the five stops, then the background.
  List<Color> get all => [...heat, background];

  /// How it travels in a share link: a preset's id, or six hex colors joined
  /// by dots (URL-safe). Neon too, so a receiver who picked other colors
  /// still sees the seed the way a Neon sender did.
  String get linkForm => id ?? all.map(hex).join('.');

  /// How it's stored on the device: [linkForm], except Neon, the default,
  /// which is stored as nothing.
  String? get wire => id == 'neon' ? null : linkForm;

  /// Reads [linkForm] or [wire]. Share links are untrusted, so anything but a known preset
  /// or exactly six hex colors is null (and the link still opens, uncolored).
  static BoardPalette? fromWire(String? wire) {
    if (wire == null) return null;
    final w = wire.trim().toLowerCase();
    for (final p in presets) {
      if (p.id == w) return p;
    }
    final parts = w.split('.');
    if (parts.length != 6) return null;
    final colors = <Color>[];
    for (final part in parts) {
      final c = parseHex(part);
      if (c == null) return null;
      colors.add(c);
    }
    return BoardPalette.custom(colors.sublist(0, 5), colors[5]);
  }

  /// `rrggbb`, lowercase, no `#`.
  static String hex(Color c) => [c.r, c.g, c.b].map((v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0')).join();

  /// Reads `rrggbb` or `#rrggbb`; null otherwise.
  static Color? parseHex(String s) {
    final t = s.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return null;
    return Color(0xFF000000 | int.parse(t, radix: 16));
  }

  /// Presets are equal by id; custom palettes by their colors.
  @override
  bool operator ==(Object other) =>
      other is BoardPalette && (id != null || other.id != null ? id == other.id : listEquals(all.map(hex).toList(), other.all.map(hex).toList()));

  @override
  int get hashCode => id != null ? id.hashCode : Object.hashAll(all.map(hex));

  @override
  String toString() => 'BoardPalette(${id ?? all.map(hex).join('.')})';
}
