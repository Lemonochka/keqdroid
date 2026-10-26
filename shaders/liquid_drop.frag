#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uDpr;
uniform vec4 uBox;
uniform float uRadius;
// screen edge the drop flows out of: direction away from it and its offset
uniform vec3 uEdge;
uniform float uEdgeK;
uniform vec4 uColor;

out vec4 fragColor;

float box(vec2 p, vec4 r, float radius) {
  if (r.z - r.x < 0.5 || r.w - r.y < 0.5) {
    return 1e4;
  }
  vec2 c = (r.xy + r.zw) * 0.5;
  vec2 h = (r.zw - r.xy) * 0.5;
  float k = min(radius, min(h.x, h.y));
  vec2 q = abs(p - c) - h + k;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - k;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float a = box(p, uBox, uRadius);
  float b = dot(p, uEdge.xy) - uEdge.z;
  float d = min(a, b);
  if (uEdgeK > 0.0) {
    float h = clamp(0.5 + 0.5 * (b - a) / uEdgeK, 0.0, 1.0);
    d = mix(b, a, h) - uEdgeK * h * (1.0 - h);
  }
  float alpha = clamp(0.5 - d * uDpr, 0.0, 1.0) * uColor.a;
  fragColor = vec4(uColor.rgb * alpha, alpha);
}
