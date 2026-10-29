#version 460 core
// Snow: snow falls and settles on the writing, only where an edge faces up
// (which way is up from the stroke's direction on screen), deepening the
// longer it has lain there, lumpy, catching the light; dark ink beneath.
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uSnow;  // the deepest it gets (px), how long it takes to settle (s)
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float hw = st.halfWidth;
  float ink = cover(st.wdist, hw + 0.2);
  // Out from the line, on screen; how much that faces up.
  vec2 t = strokeDirection(st);
  vec2 g = st.wdist > 1e-3 ? vec2(st.s - clamp(st.s, 0.0, st.written), st.across) / st.wdist : vec2(0.0, -1.0);
  vec2 out2 = g.x * t + g.y * vec2(-t.y, t.x);
  float up = clamp(-out2.y, 0.0, 1.0);
  float settle = smoothstep(0.0, uSnow.y, uPen.x - st.t);
  float lumps = 0.65 + 0.55 * fbm(vec2(st.s / (uPen.w * 0.1), st.index * 3.0));
  float depth = uSnow.x * settle * lumps * pow(up, 0.7);
  float onTop = smoothstep(0.05, 0.35, up) * step(0.5, depth);
  float snow = cover(st.wdist, hw + depth) * onTop * smoothstep(hw * 0.2, hw * 0.55, st.wdist);
  float shade = 0.8 + 0.2 * smoothstep(hw, hw + depth, st.wdist);
  float glint = step(0.992, hash12(floor(vec2(st.s, st.across) * 0.7) + st.index)) * (0.6 + 0.4 * sin(uPen.x * 4.0 + st.s));
  vec3 snowC = vec3(0.95, 0.97, 1.0) * shade * (0.92 + 0.08 * lumps) + glint * 0.4;
  vec3 inkC = vec3(0.10, 0.11, 0.15);
  float a = max(ink, snow);
  vec3 c = mix(inkC * ink, min(snowC, vec3(1.0)), snow);
  fragColor = vec4(c * (a > 0.0 ? 1.0 : 0.0) * max(ink, snow) / max(a, 1e-4), a);
}
