import 'package:flutter/material.dart';

/// Neon-on-black palette, matched to the composite shader's heat ramp.
abstract final class Neon {
  static const background = Color(0xFF05060A);
  static const panel = Color(0xCC0B0E17);
  static const border = Color(0x3300E5FF);
  static const cyan = Color(0xFF00E5FF);
  static const magenta = Color(0xFFFF2BD6);
  static const amber = Color(0xFFFFA114);
  static const text = Color(0xFFE6F1FF);
  static const muted = Color(0xFF7D8BA6);

  static ThemeData theme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(primary: cyan, secondary: magenta, surface: Color(0xFF0B0E17)),
      useMaterial3: true,
    );
    return base.copyWith(
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: cyan,
        thumbColor: cyan,
        inactiveTrackColor: cyan.withValues(alpha: 0.15),
        overlayColor: cyan.withValues(alpha: 0.12),
        trackHeight: 2,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: mono.copyWith(fontSize: 11),
        decoration: BoxDecoration(
          color: const Color(0xF20B0E17),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
      ),
      // Only used where there's no Toasts ancestor (a widget tested on its own).
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 520,
        backgroundColor: const Color(0xF20B0E17),
        contentTextStyle: mono,
        actionTextColor: magenta,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: magenta.withValues(alpha: 0.55)),
        ),
      ),
    );
  }

  static BoxDecoration panelDecoration({double radius = 14}) => BoxDecoration(
    color: panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border),
    boxShadow: [BoxShadow(color: cyan.withValues(alpha: 0.06), blurRadius: 24)],
  );

  static const mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: ['monospace'], fontSize: 12, color: text);
}
