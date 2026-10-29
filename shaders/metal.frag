#version 460 core
// Metal: each stroke a bead of steel laid down white-hot, cooling to
// brushed grey (the base for the weld effect, whose joints spark).
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uMetal;  // how long it stays hot (s), the brushing's grain (px)
out vec4 fragColor;

vec3 glow(float x) {
  x = clamp(x, 0.0, 1.0);
  return vec3(smoothstep(0.0, 0.4, x), smoothstep(0.25, 0.8, x), smoothstep(0.6, 1.0, x));
}

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float hot = exp(-max(uPen.x - st.t, 0.0) / uMetal.x);
  float r = st.halfWidth * 1.2 + 0.7;
  float a = cover(st.wdist, r);
  if (a <= 0.0) {
    float g = exp(-max(st.wdist - r, 0.0) / (uPen.w * 0.06)) * hot * meshFade(st);
    fragColor = vec4(glow(0.3 + 0.4 * hot) * g, g * 0.5);
    return;
  }
  float x = clamp(st.across / r, -1.0, 1.0);
  float bulge = sqrt(max(1.0 - x * x, 0.0));
  float brushed = vnoise(vec2(st.s / uMetal.y, st.across * 2.0 + st.index * 9.0));
  vec3 steel = vec3(0.50, 0.53, 0.58) * (0.45 + 0.55 * bulge) * (0.85 + 0.3 * brushed);
  steel += vec3(0.9) * pow(bulge, 14.0) * 0.35;
  // (Temper colours as it cools: straw, then bronze, then blue.)
  float temper = smoothstep(0.02, 0.25, hot) * (1.0 - smoothstep(0.25, 0.5, hot));
  steel = mix(steel, mix(vec3(0.62, 0.48, 0.25), vec3(0.32, 0.36, 0.62), smoothstep(0.08, 0.2, hot)) * (0.6 + 0.4 * bulge), temper * 0.6);
  vec3 c = mix(steel, glow(hot * (0.8 + 0.3 * bulge)), smoothstep(0.25, 0.6, hot));
  fragColor = vec4(c * a, a);
}
