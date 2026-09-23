#version 460 core
#include <flutter/runtime_effect.glsl>

// Local population density at reduced resolution: the "hotspot" map. The
// state is sampled with LINEAR filtering at cell corners, so each of the 64
// taps averages a 2x2 block and the kernel covers 16x16 cells.

precision highp float;

uniform vec2 uOut;
uniform vec2 uGrid;
uniform sampler2D uState;

out vec4 fragColor;

void main() {
  vec2 c = FlutterFragCoord().xy / uOut * uGrid;
  float s = 0.0;
  for (int j = -4; j < 4; j++) {
    for (int i = -4; i < 4; i++) {
      vec2 p = c + vec2(float(i) * 2.0 + 1.0, float(j) * 2.0 + 1.0);
      s += texture(uState, fract(p / uGrid)).r;
    }
  }
  float d = s / 64.0;
  fragColor = vec4(vec3(d), 1.0);
}
