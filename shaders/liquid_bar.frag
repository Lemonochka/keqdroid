#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uDpr;
uniform vec4 uJump;
uniform vec2 uJumpR;
uniform vec4 uA;
uniform vec2 uAR;
uniform vec4 uB;
uniform vec2 uBR;
uniform vec4 uC;
uniform vec2 uCR;
uniform vec4 uBud;
uniform vec2 uBudR;
uniform vec4 uL;
uniform vec2 uLR;
uniform vec4 uR;
uniform vec2 uRR;
uniform float uBudK;
uniform float uJumpK;
uniform float uSideK;
uniform float uPoolY;
uniform float uPoolK;
uniform vec4 uBaseColor;
uniform vec4 uBudColor;
uniform vec4 uJumpColor;
uniform vec4 uSideColor;
uniform vec4 uFinger;
uniform vec2 uFingerR;
uniform float uFingerK;
uniform float uVertical;

out vec4 fragColor;

// rad: corner radius on the left and on the right side, on the side rail on the top and bottom
float box(vec2 p, vec4 r, vec2 rad) {
  if (r.z - r.x < 0.5 || r.w - r.y < 0.5) {
    return 1e4;
  }
  vec2 c = (r.xy + r.zw) * 0.5;
  vec2 h = (r.zw - r.xy) * 0.5;
  bool first = uVertical > 0.5 ? p.y < c.y : p.x < c.x;
  float k = min(first ? rad.x : rad.y, min(h.x, h.y));
  vec2 q = abs(p - c) - h + k;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - k;
}

// smooth union, y is the weight of a for colour
vec2 blend(float a, float b, float k) {
  if (k <= 0.0) {
    return vec2(min(a, b), a < b ? 1.0 : 0.0);
  }
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return vec2(mix(b, a, h) - k * h * (1.0 - h), h);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  // tabs join without smoothing so the seams between them stay
  float base = min(min(box(p, uA, uAR), box(p, uB, uBR)), box(p, uC, uCR));
  // a held finger pulls a bump out of the strip
  base = blend(base, box(p, uFinger, uFingerR), uFingerK).x;
  vec2 u = blend(base, box(p, uBud, uBudR), uBudK);
  vec2 w = blend(u.x, box(p, uJump, uJumpR), uJumpK);
  // tiles beside the strip bud out of its ends on the settings tab
  float left = box(p, uL, uLR);
  float right = box(p, uR, uRR);
  float sides = min(left, right);
  float all = blend(w.x, sides, uSideK).x;
  vec2 v = blend(all, uPoolY - p.y, uPoolK);
  vec4 c = mix(uBudColor, uBaseColor, u.y);
  c = mix(uJumpColor, c, w.y);
  // the version tile shows the update state by its colour
  c = sides < w.x ? (left < right ? uSideColor : uBaseColor) : c;
  c = mix(uBaseColor, c, v.y);
  float alpha = clamp(0.5 - v.x * uDpr, 0.0, 1.0) * c.a;
  fragColor = vec4(c.rgb * alpha, alpha);
}
