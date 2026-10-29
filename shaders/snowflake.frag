#version 460 core
// Frost's joints: ice forms first where strokes meet, so a six-armed
// crystal grows from each joint as the pen gets there.
#include "joint_space.glsl"
#include "noise.glsl"

uniform vec4 uFlake;  // its reach (of the square), how fast it grows (s), the arms' half-width (px), the branches' spacing (of the reach)
out vec4 fragColor;

float segment(vec2 p, vec2 a, vec2 d, float l) {
  vec2 q = p - a;
  return length(q - d * clamp(dot(q, d), 0.0, l));
}

void main() {
  Joint j = jointAt(FlutterFragCoord().xy);
  float tau = uJPen.x - j.t;
  if (tau < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  // (Smaller where a stroke only touches another: the commonest kind, a
  // kanji's every corner.)
  float kind = j.kind > 0.5 && j.kind < 1.5 ? 0.55 : 1.0;
  float reach = j.r * uFlake.x * kind * (0.65 + 0.35 * hash11(j.index + 3.0)) * (1.0 - exp(-tau / uFlake.y));
  // Folded into a wedge: six arms, each mirrored.
  float angle = atan(j.p.y, j.p.x) + hash11(j.index) * 1.0472;
  float a = abs(mod(angle + 0.5236, 1.0472) - 0.5236);
  float r = length(j.p);
  vec2 w = vec2(r * cos(a), r * sin(a));
  float d = segment(w, vec2(0.0), vec2(1.0, 0.0), reach);
  vec2 branch = vec2(0.5, 0.8660254);
  for (int k = 1; k <= 4; k++) {
    float x = reach * uFlake.w * float(k);
    if (x < reach) d = min(d, segment(w, vec2(x, 0.0), branch, (reach - x) * 0.55));
  }
  // A small plate at its heart.
  float hex = max(abs(w.y), dot(w, vec2(0.8660254, 0.5)));
  d = min(d, max(hex - reach * 0.16, 0.0));
  float crystal = jointCover(d, uFlake.z * (1.0 - 0.45 * clamp(r / max(reach, 1e-3), 0.0, 1.0)));
  float flash = exp(-tau / 0.25) * exp(-r / (j.size * 1.5 + 2.0));
  float glint = pow(max(0.0, cos(angle * 3.0 - uJPen.x * 1.7)), 30.0) * crystal;
  float fade = squareFade(j);
  vec3 c = vec3(0.82, 0.92, 1.0) * crystal + vec3(1.0) * (flash + glint * 0.6);
  float alpha = clamp(crystal * 0.75 * (0.6 + 0.4 * kind) + flash, 0.0, 1.0) * fade;
  fragColor = vec4(min(c * fade, vec3(1.0)), alpha);
}
