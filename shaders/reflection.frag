#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec4 uButton;
uniform float uAxis;
uniform float uDepth;
uniform float uWobble;
uniform vec4 uColor;

out vec4 fragColor;

float roundBox(vec2 p, float h, float r) {
  vec2 q = abs(p) - h + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float below = p.y - uAxis;
  if (below < -8.0 || uColor.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float k = clamp(below / uDepth, 0.0, 1.0);
  float wob = uWobble * (0.3 + k);
  float dx = sin(below * 0.16 - uTime * 2.2) * wob
      + sin(below * 0.37 + uTime * 3.1 + p.x * 0.02) * wob * 0.35;
  vec2 src = vec2(p.x + dx, uAxis - below / 0.85);
  vec2 center = vec2(uButton.x, uButton.y + uButton.z);
  float d = roundBox(src - center, uButton.z, uButton.w);
  float soft = 0.8 + 7.0 * k;
  float inside = 1.0 - smoothstep(-soft, soft, d);
  float a = inside * pow(1.0 - k, 1.3) * uColor.a;
  fragColor = vec4(uColor.rgb * a, a);
}
