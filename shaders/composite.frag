#version 460 core
#include <flutter/runtime_effect.glsl>

// Final image: a heat-coloured glow cloud over dense regions, fading neon
// trails, and bright live cells tinted by how crowded their neighbourhood is.

precision highp float;

uniform vec2 uView;     // canvas size in logical pixels
uniform vec2 uGrid;     // board size in cells
uniform float uTime;    // seconds, for a slow shimmer
uniform float uGlow;    // 0..2 glow intensity
uniform sampler2D uState;   // nearest
uniform sampler2D uTrail;   // linear
uniform sampler2D uDensity; // linear

out vec4 fragColor;

// Deep violet -> electric cyan -> magenta -> amber -> white-hot.
vec3 palette(float t) {
  t = clamp(t, 0.0, 1.0);
  vec3 c0 = vec3(0.16, 0.06, 0.55);
  vec3 c1 = vec3(0.00, 0.85, 1.00);
  vec3 c2 = vec3(1.00, 0.12, 0.72);
  vec3 c3 = vec3(1.00, 0.62, 0.08);
  vec3 c4 = vec3(1.00, 0.98, 0.88);
  if (t < 0.25) return mix(c0, c1, t / 0.25);
  if (t < 0.50) return mix(c1, c2, (t - 0.25) / 0.25);
  if (t < 0.75) return mix(c2, c3, (t - 0.50) / 0.25);
  return mix(c3, c4, (t - 0.75) / 0.25);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uView;

  float alive = texture(uState, uv).r;
  float trail = texture(uTrail, uv).r;
  float d = texture(uDensity, uv).r;

  // Wide halo: ring of taps on the (already smooth) density map.
  vec2 r = 12.0 / uGrid;
  float halo = d * 0.4;
  halo += texture(uDensity, uv + vec2( r.x, 0.0)).r * 0.075;
  halo += texture(uDensity, uv + vec2(-r.x, 0.0)).r * 0.075;
  halo += texture(uDensity, uv + vec2(0.0,  r.y)).r * 0.075;
  halo += texture(uDensity, uv + vec2(0.0, -r.y)).r * 0.075;
  halo += texture(uDensity, uv + r * 0.7).r * 0.075;
  halo += texture(uDensity, uv - r * 0.7).r * 0.075;
  halo += texture(uDensity, uv + vec2(r.x, -r.y) * 0.7).r * 0.075;
  halo += texture(uDensity, uv + vec2(-r.x, r.y) * 0.7).r * 0.075;

  // Game of Life rarely exceeds ~40% density, so stretch that range to full heat.
  float heat = smoothstep(0.0, 0.32, halo);
  float shimmer = 0.9 + 0.1 * sin(uTime * 1.7 + heat * 6.0);

  // When cells are drawn larger than a few pixels, give them a soft rounded body.
  float cellPx = uView.x / uGrid.x;
  vec2 f = abs(fract(uv * uGrid) - 0.5);
  float body = cellPx > 3.0 ? 1.0 - smoothstep(0.32, 0.5, max(f.x, f.y)) : 1.0;

  vec3 col = vec3(0.008, 0.01, 0.03);
  col += palette(heat) * halo * 2.2 * uGlow * shimmer;
  col += palette(heat * 0.85 + 0.1) * trail * trail * 0.55 * uGlow;
  col += mix(palette(heat + 0.2), vec3(1.0), 0.3) * alive * body * 1.4;

  // Filmic-ish tonemap keeps hot cores from clipping to flat white.
  col = 1.0 - exp(-col * 1.35);

  // Vignette and faint scanlines for the display-panel feel.
  vec2 q = uv - 0.5;
  col *= 1.0 - dot(q, q) * 0.9;
  col *= 0.96 + 0.04 * sin(frag.y * 3.14159);

  fragColor = vec4(col, 1.0);
}
