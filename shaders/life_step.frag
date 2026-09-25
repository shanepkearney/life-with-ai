#version 460 core
#include <flutter/runtime_effect.glsl>

// One Game of Life generation on the GPU. Each output pixel is one cell; the
// previous generation is sampled with nearest filtering. fract() wraps the
// edges so the board is a torus, matching the CPU engine exactly.

precision highp float;

uniform vec2 uGrid;
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
  // Born with exactly 3 neighbors; survives with 2 or 3. Sums of 0/1 floats are exact.
  float next = (abs(n - 3.0) < 0.5 || (abs(n - 2.0) < 0.5 && alive > 0.5)) ? 1.0 : 0.0;
  fragColor = vec4(next);
}
