#version 460 core
// Frost: the ink freezes as it's written, water to ice, and frost feathers
// grow out from its edges once it has, branching at sixty degrees as ice
// does. (Its joints, where ice forms first: snowflake.frag.)
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uFrost;  // how long ink takes to freeze (s), the feathers' reach (px), their spacing (px), how long they take to grow (s)
out vec4 fragColor;

// How far p is from the segment from a, along unit d for l.
float segment(vec2 p, vec2 a, vec2 d, float l) {
  vec2 q = p - a;
  return length(q - d * clamp(dot(q, d), 0.0, l));
}

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float now = uPen.x;
  float freeze = smoothstep(0.0, uFrost.x, max(now - st.t, 0.0));
  float hw = st.halfWidth;
  float body = cover(st.wdist, hw + 0.3);
  // Ice: pale, cracked, brighter at its rim; still water before.
  vec2 q = vec2(st.s, st.across) / max(uPen.w * 0.06, 1.0);
  float crack = 1.0 - smoothstep(0.0, 0.07, abs(vnoise(q * 1.2 + st.index * 3.0) - 0.5));
  float rim = smoothstep(0.35, 1.0, abs(st.across) / max(hw, 0.5));
  vec3 water = vec3(0.12, 0.26, 0.48);
  vec3 ice = mix(vec3(0.42, 0.64, 0.9), vec3(0.9, 0.96, 1.0), clamp(rim * 0.75 + crack * 0.35, 0.0, 1.0));
  vec3 ink = mix(water, ice, freeze);
  // Feathers: needles out from each edge, with branches.
  float side = st.across >= 0.0 ? 1.0 : -1.0;
  vec2 p = vec2(st.s, abs(st.across) - hw);
  float spacing = uFrost.z;
  float j0 = floor(st.s / spacing);
  float fd = 1e4;
  float tip = 1.0;
  for (int k = -1; k <= 1; k++) {
    float j = j0 + float(k);
    float h = hash12(vec2(j, st.index * 2.0 + side));
    float h2 = hash12(vec2(j + 31.0, st.index * 2.0 + side));
    float sj = (j + 0.2 + 0.6 * h) * spacing;
    if (sj < 0.0 || sj > st.written) continue;
    // (When the pen passed there; it grows once that's frozen.)
    float tj = st.t + (sj - clamp(st.s, 0.0, st.len)) / max(st.speed, 1.0);
    float grow = clamp((now - tj - uFrost.x * 0.5) / uFrost.w, 0.0, 1.0);
    grow = 1.0 - (1.0 - grow) * (1.0 - grow);
    if (grow <= 0.0) continue;
    float angle = mix(0.85, 2.3, h2);
    vec2 dir = vec2(cos(angle), sin(angle));
    float len = uFrost.y * (0.35 + 0.65 * h) * grow;
    vec2 a = vec2(sj, 0.0);
    float dn = segment(p, a, dir, len);
    if (dn < fd) {
      fd = dn;
      tip = clamp(dot(p - a, dir) / max(len, 1e-3), 0.0, 1.0);
    }
    vec2 d1 = vec2(cos(angle + 1.047), sin(angle + 1.047));
    vec2 d2 = vec2(cos(angle - 1.047), sin(angle - 1.047));
    for (int b = 1; b <= 2; b++) {
      float at = len * float(b) * 0.3;
      vec2 o = a + dir * at;
      float bl = (len - at) * 0.5;
      fd = min(fd, min(segment(p, o, d1, bl), segment(p, o, d2, bl)));
    }
  }
  float feather = cover(fd, 0.42 * (1.0 - 0.5 * tip)) * smoothstep(-0.5, 0.5, p.y) * meshFade(st) * 0.7;
  // A cold haze round it, and glints.
  float haze = exp(-max(st.wdist - hw, 0.0) / (uFrost.y * 0.4)) * 0.07 * freeze * meshFade(st);
  float glint = step(0.985, hash12(floor(vec2(st.s, st.across) * 0.5) + st.index)) *
      (0.5 + 0.5 * sin(now * 5.0 + st.s)) * max(body, feather);
  vec3 frost = vec3(0.86, 0.94, 1.0);
  float a = clamp(max(body, max(feather * 0.95, haze)), 0.0, 1.0);
  vec3 c = ink * body + frost * feather * (1.0 - body) + vec3(0.7, 0.85, 1.0) * haze * (1.0 - body) + glint;
  fragColor = vec4(min(c, vec3(1.0)), a);
}
