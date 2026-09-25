#version 460 core
#include <flutter/runtime_effect.glsl>

// One Game of Life generation on the GPU. Each output pixel is one cell; the
// previous generation is sampled with nearest filtering. fract() wraps the
// edges so the board is a torus, matching the CPU engine exactly.

precision highp float;

uniform vec2 uGrid;
uniform float uBirth;    // LifeRule.birth: bit n set means born with n neighbors
uniform float uSurvival; // LifeRule.survival: bit n set means survives with n
uniform sampler2D uState;

out vec4 fragColor;

float cell(vec2 p) {
  return step(0.5, texture(uState, fract(p / uGrid)).r);
}

void main() {
  vec2 p = floor(FlutterFragCoord().xy) + 0.5;
  float n = cell(p + vec2(-1.0, -1.0)) + cell(p + vec2(0.0, -1.0)) + cell(p + vec2(1.0, -1.0))
          + cell(p + vec2(-1.0,  0.0))                              + cell(p + vec2(1.0,  0.0))
          + cell(p + vec2(-1.0,  1.0)) + cell(p + vec2(0.0,  1.0)) + cell(p + vec2(1.0,  1.0));
  float alive = cell(p);
  float next;
  if (uBirth == 8.0 && uSurvival == 12.0) {
    // Conway's B3/S23, the common case, as before: born with exactly 3, survives with 2 or 3.
    // The branch is the same for every pixel, so it costs nothing.
    next = (abs(n - 3.0) < 0.5 || (abs(n - 2.0) < 0.5 && alive > 0.5)) ? 1.0 : 0.0;
  } else {
    // Any rule: bit n of its mask, for n live neighbors (floor(mask / 2^n) is odd).
    // Masks are at most 511 and n a whole number, so this float arithmetic is exact.
    float mask = alive > 0.5 ? uSurvival : uBirth;
    next = mod(floor(mask / exp2(floor(n + 0.5)) + 0.5 / 1024.0), 2.0) > 0.5 ? 1.0 : 0.0;
  }
  fragColor = vec4(next);
}
