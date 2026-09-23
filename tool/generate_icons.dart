// Generates every app icon from one design: a neon glider.
//
//   dart run tool/generate_icons.dart
//
// Each pixel is computed analytically (rounded-square distance fields with an
// exponential glow) rather than drawn large and scaled down, so the 16px
// favicon stays crisp. Colours follow the renderer's heat ramp, cooling from
// the glider's tail (cyan) to its leading edge (amber), the way it travels.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:life_with_ai/core/patterns.dart';

typedef Rgb = (double, double, double);

/// Same stops as `palette()` in shaders/composite.frag.
Rgb heat(double t) {
  const stops = <Rgb>[
    (0.16, 0.06, 0.55),
    (0.00, 0.85, 1.00),
    (1.00, 0.12, 0.72),
    (1.00, 0.62, 0.08),
    (1.00, 0.98, 0.88),
  ];
  t = t.clamp(0.0, 1.0) * (stops.length - 1);
  final i = t.floor().clamp(0, stops.length - 2);
  final f = t - i;
  final a = stops[i], b = stops[i + 1];
  return (a.$1 + (b.$1 - a.$1) * f, a.$2 + (b.$2 - a.$2) * f, a.$3 + (b.$3 - a.$3) * f);
}

/// Signed distance from p to a rounded box centred at c (half-size h, corner r).
double roundedBox(double px, double py, double cx, double cy, double h, double r) {
  final qx = (px - cx).abs() - h + r, qy = (py - cy).abs() - h + r;
  final ox = max(qx, 0.0), oy = max(qy, 0.0);
  return sqrt(ox * ox + oy * oy) + min(max(qx, qy), 0.0) - r;
}

double smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

class IconStyle {
  const IconStyle({required this.inset, required this.gliderSpan, required this.fullBleed, this.glow = 1.0, this.gap = 0.2});

  /// Margin around the rounded tile, as a fraction of the canvas (macOS icons keep ~10%).
  final double inset;

  /// How much of the tile the 3x3 glider spans.
  final double gliderSpan;

  /// Maskable icons must fill the whole square; the OS applies its own mask.
  final bool fullBleed;
  final double glow;

  /// Space between cells as a fraction of a cell; tiny icons need more to stay legible.
  final double gap;
}

img.Image render(int size, IconStyle style) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  final glider = patternLibrary['glider']!.cells; // (1,0) (2,1) (0,2) (1,2) (2,2)
  final samples = size <= 64 ? 4 : (size <= 256 ? 2 : 1);

  final tileHalf = 0.5 - style.inset;
  final cell = style.gliderSpan * tileHalf * 2 / 3;
  final cellHalf = cell * (1 - style.gap) / 2;
  final glowRadius = cell * 0.32 * style.glow;

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          // Normalised coordinates in [0,1].
          final px = (x + (sx + 0.5) / samples) / size;
          final py = (y + (sy + 0.5) / samples) / size;

          // Tile: rounded square with a deep-space radial gradient.
          final tileD = style.fullBleed ? -1.0 : roundedBox(px, py, 0.5, 0.5, tileHalf, tileHalf * 0.44);
          final coverage = style.fullBleed ? 1.0 : 1 - smoothstep(-0.6 / size, 0.6 / size, tileD);
          if (coverage <= 0) continue;
          final vignette = sqrt(pow(px - 0.5, 2) + pow(py - 0.42, 2));
          var cr = 0.045 - vignette * 0.05, cg = 0.05 - vignette * 0.05, cb = 0.11 - vignette * 0.1;

          for (final (gx, gy) in glider) {
            final cx = 0.5 + (gx - 1) * cell, cy = 0.5 + (gy - 1) * cell;
            final d = roundedBox(px, py, cx, cy, cellHalf, cellHalf * 0.35);
            // Tail (top) is coolest, the leading corner (bottom-right) hottest:
            // cyan -> magenta -> amber across the glider's cells.
            final (hr, hg, hb) = heat(0.25 + (gx + gy - 1) / 3 * 0.48);
            final body = 1 - smoothstep(-0.8 / size, 0.8 / size, d);
            // A hot rim inside each cell, like the live cells' bloom on screen.
            final rim = body * smoothstep(-cellHalf * 0.55, 0, d) * 0.35;
            final bloom = exp(-max(d, 0.0) / glowRadius) * 0.55;
            cr += hr * (bloom + body * 1.05 + rim) + body * 0.12;
            cg += hg * (bloom + body * 1.05 + rim) + body * 0.12;
            cb += hb * (bloom + body * 1.05 + rim) + body * 0.12;
          }

          // Same filmic curve as the composite shader.
          r += (1 - exp(-max(cr, 0.0) * 1.35)) * coverage;
          g += (1 - exp(-max(cg, 0.0) * 1.35)) * coverage;
          b += (1 - exp(-max(cb, 0.0) * 1.35)) * coverage;
          a += coverage;
        }
      }
      final n = samples * samples;
      // Colour was accumulated premultiplied by coverage; un-premultiply for PNG.
      final alpha = a / n;
      int ch(double v) => alpha == 0 ? 0 : (v / n / alpha * 255).round().clamp(0, 255);
      image.setPixelRgba(x, y, ch(r), ch(g), ch(b), (alpha * 255).round());
    }
  }
  return image;
}

void write(String path, int size, IconStyle style) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(render(size, style)));
  stdout.writeln('  $path (${size}px)');
}

void main() {
  const web = IconStyle(inset: 0.02, gliderSpan: 0.66, fullBleed: false);
  // Tiny sizes: fill more of the tile and tame the bloom so the shape still reads.
  const favicon = IconStyle(inset: 0.0, gliderSpan: 0.84, fullBleed: false, glow: 0.35, gap: 0.3);
  // Maskable: keep the glider inside the central ~60% safe zone.
  const maskable = IconStyle(inset: 0.0, gliderSpan: 0.5, fullBleed: true);
  // macOS: Apple's grid leaves ~10% transparent margin around the tile.
  const macos = IconStyle(inset: 0.098, gliderSpan: 0.66, fullBleed: false);

  stdout.writeln('Generating icons:');
  write('web/favicon.png', 32, favicon);
  write('web/icons/Icon-192.png', 192, web);
  write('web/icons/Icon-512.png', 512, web);
  write('web/icons/Icon-maskable-192.png', 192, maskable);
  write('web/icons/Icon-maskable-512.png', 512, maskable);
  for (final s in [16, 32, 64, 128, 256, 512, 1024]) {
    write('macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png', s, s <= 32 ? favicon : macos);
  }
}
