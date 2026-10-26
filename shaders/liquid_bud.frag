#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uDpr;
uniform vec4 uSrc;
uniform float uSrcR;
uniform vec4 uBud;
uniform float uBudR;
uniform float uK;
uniform vec4 uSrcColor;
uniform vec4 uBudColor;

out vec4 fragColor;

float box(vec2 p, vec4 r, float rad) {
  if (r.z - r.x < 0.5 || r.w - r.y < 0.5) {
    return 1e4;
  }
  vec2 c = (r.xy + r.zw) * 0.5;
  vec2 h = (r.zw - r.xy) * 0.5;
  float k = min(rad, min(h.x, h.y));
  vec2 q = abs(p - c) - h + k;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - k;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float a = box(p, uSrc, uSrcR);
  float b = box(p, uBud, uBudR);
  float d;
  float w;
  if (uK <= 0.0) {
    d = min(a, b);
    w = a < b ? 1.0 : 0.0;
  } else {
    w = clamp(0.5 + 0.5 * (b - a) / uK, 0.0, 1.0);
    d = mix(b, a, w) - uK * w * (1.0 - w);
  }
  // the source is a real widget underneath: only the bridge and the drop are drawn
  float alpha = clamp(0.5 - d * uDpr, 0.0, 1.0) * clamp(0.5 + a * uDpr, 0.0, 1.0);
  vec4 c = mix(uBudColor, uSrcColor, w);
  fragColor = vec4(c.rgb * c.a * alpha, c.a * alpha);
}
