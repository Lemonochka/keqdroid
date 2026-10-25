#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uFrom;
uniform vec2 uTo;
uniform float uMid;
uniform vec3 uAlpha;
uniform vec3 uSlope;
uniform vec3 uColor;
uniform float uDpr;

out vec4 fragColor;

float hermite(float s, float h, float va, float vb, float ma, float mb) {
  float s2 = s * s;
  float s3 = s2 * s;
  return (2.0 * s3 - 3.0 * s2 + 1.0) * va + (s3 - 2.0 * s2 + s) * h * ma +
      (-2.0 * s3 + 3.0 * s2) * vb + (s3 - s2) * h * mb;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 d = uTo - uFrom;
  float t = clamp(dot(p - uFrom, d) / max(dot(d, d), 0.0001), 0.0, 1.0);

  float a;
  if (t < uMid) {
    a = hermite(t / uMid, uMid, uAlpha.x, uAlpha.y, uSlope.x, uSlope.y);
  } else {
    float h = max(1.0 - uMid, 0.0001);
    a = hermite((t - uMid) / h, h, uAlpha.y, uAlpha.z, uSlope.y, uSlope.z);
  }

  vec2 px = floor(p * uDpr);
  float n = fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
  a = clamp(a + (n - 0.5) / 40.0, 0.0, 1.0);
  fragColor = vec4(uColor * a, a);
}
