import 'package:flutter/widgets.dart';

/// Drops text-spacing overrides no reader could have asked for.
///
/// Flutter web detects the browser's text-spacing settings by measuring a
/// hidden element whose spacing is set to a 9999px sentinel. Android's WebView
/// (the in-app browser of Facebook, Messenger, Instagram…) scales that
/// element's line height by the phone's font size, so at 115% Flutter reads a
/// line height of about 625 times the text and applies it everywhere: every
/// line of text grows off the screen, and the app looks blank. WCAG's own
/// text-spacing settings stop at 1.5x line height and fractions of an em, so
/// anything far past them is the sentinel, not a setting. The font size itself
/// (the text scaler) is real, and kept.
MediaQueryData saneTextSpacing(MediaQueryData d) {
  final lineHeight = d.lineHeightScaleFactorOverride;
  final saneLineHeight = lineHeight != null && lineHeight <= maxLineHeightScale ? lineHeight : null;
  double? sane(double? spacing) => spacing != null && spacing.abs() <= maxSpacing ? spacing : null;
  final letter = sane(d.letterSpacingOverride), word = sane(d.wordSpacingOverride), paragraph = sane(d.paragraphSpacingOverride);
  if (saneLineHeight == lineHeight &&
      letter == d.letterSpacingOverride &&
      word == d.wordSpacingOverride &&
      paragraph == d.paragraphSpacingOverride) {
    return d;
  }
  return MediaQueryData(
    size: d.size,
    devicePixelRatio: d.devicePixelRatio,
    textScaler: d.textScaler,
    platformBrightness: d.platformBrightness,
    padding: d.padding,
    viewInsets: d.viewInsets,
    systemGestureInsets: d.systemGestureInsets,
    viewPadding: d.viewPadding,
    alwaysUse24HourFormat: d.alwaysUse24HourFormat,
    accessibleNavigation: d.accessibleNavigation,
    invertColors: d.invertColors,
    highContrast: d.highContrast,
    onOffSwitchLabels: d.onOffSwitchLabels,
    disableAnimations: d.disableAnimations,
    boldText: d.boldText,
    supportsAnnounce: d.supportsAnnounce,
    navigationMode: d.navigationMode,
    gestureSettings: d.gestureSettings,
    displayFeatures: d.displayFeatures,
    supportsShowingSystemContextMenu: d.supportsShowingSystemContextMenu,
    lineHeightScaleFactorOverride: saneLineHeight,
    letterSpacingOverride: letter,
    wordSpacingOverride: word,
    paragraphSpacingOverride: paragraph,
  );
}

/// Well past WCAG's 1.5x, for anyone who sets more.
const maxLineHeightScale = 4.0;

/// Logical pixels: WCAG asks for fractions of an em; the sentinel is thousands.
const maxSpacing = 200.0;
