#version 460 core

#include <flutter/runtime_effect.glsl>

uniform float uTop;
uniform float uBottom;
uniform float uBottomHidden;
uniform float uSide;
uniform vec2 uSize;
uniform float uDpr;
uniform float uShapeInset;
uniform float uShapeRadius;
uniform float uShapeGap;

out vec4 fragColor;

float smoother(float t) {
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float edge(float distance, float length) {
  return length > 0.0 ? smoother(clamp(distance / length, 0.0, 1.0)) : 1.0;
}

float topDistance(vec2 p) {
  if (uShapeRadius <= 0.0) {
    return p.y;
  }
  float left = uShapeInset + uShapeRadius;
  float right = max(left, uSize.x - uShapeInset - uShapeRadius);
  vec2 corner = vec2(clamp(p.x, left, right), -uShapeGap - uShapeRadius);
  return length(p - corner) - uShapeRadius - uShapeGap;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float a = edge(topDistance(p), uTop) *
      edge(uSize.y - p.y - uBottomHidden, uBottom) *
      edge(p.x, uSide) *
      edge(uSize.x - p.x, uSide);

  vec2 px = floor(p * uDpr);
  float n = fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
  if (a > 0.0 && a < 1.0) {
    a = clamp(a + (n - 0.5) / 40.0, 0.0, 1.0);
  }
  fragColor = vec4(a, a, a, a);
}
