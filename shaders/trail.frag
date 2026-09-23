#version 460 core
#include <flutter/runtime_effect.glsl>

// Persistence buffer: live cells write 1.0, everything else fades by uDecay per
// update. Gives moving structures neon comet tails.

precision highp float;

uniform vec2 uGrid;
uniform float uDecay;
uniform sampler2D uState;
uniform sampler2D uTrail;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uGrid;
  float s = texture(uState, uv).r;
  float t = texture(uTrail, uv).r * uDecay;
  fragColor = vec4(vec3(max(s, t)), 1.0);
}
