#version 460 core
// Ember: the pen leaves molten metal that runs along the stroke the way it
// was written, cools from white to red to cracked charcoal.
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uHeat;  // how long it stays hot (s), how fast it runs (px/s), its grain (px), the glow's reach (px)
out vec4 fragColor;

vec3 blackbody(float x) {
  x = clamp(x, 0.0, 1.0);
  vec3 c = vec3(smoothstep(0.0, 0.45, x), smoothstep(0.3, 0.8, x), smoothstep(0.65, 1.0, x));
  return c * (0.3 + 0.7 * smoothstep(0.0, 0.35, x));
}

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float now = uPen.x;
  float heat = exp(-max(now - st.t, 0.0) / uHeat.x);
  vec2 q = vec2((st.s - now * uHeat.y) / uHeat.z, st.across / (uHeat.z * 0.5) + st.index * 5.0);
  float flow = fbm(q);
  float r = st.halfWidth * (1.0 + 0.3 * heat) + 0.4;
  float ink = cover(st.wdist, r);
  float crack = 1.0 - smoothstep(0.0, 0.06,
      abs(vnoise(vec2(st.s / (uHeat.z * 1.4), st.across / uHeat.z + st.index * 7.0)) - 0.5));
  float smoulder = 0.55 + 0.3 * sin(now * 2.3 + st.s * 0.07 + st.index);
  float x = heat * (0.7 + 0.55 * flow) + crack * smoulder * 0.75 * (1.0 - heat);
  vec3 coal = vec3(0.22, 0.17, 0.15) * (0.75 + 0.6 * flow);
  vec3 c = mix(coal, blackbody(x), smoothstep(0.06, 0.3, x));
  float glow = exp(-max(st.wdist - r, 0.0) / uHeat.w) * (heat + 0.12) * meshFade(st);
  vec3 g = blackbody(0.25 + heat * 0.55) * glow;
  float a = max(ink, glow * 0.6);
  fragColor = vec4(min(c * ink + g * (1.0 - ink), vec3(1.0)), a);
}
