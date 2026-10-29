#version 460 core
// Sakura's strokes: cherry branches, growing as the pen goes: dark bark,
// streaked along, with the cherry's little marks across it.
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uBark;  // how much thicker than the ink, how long it takes to grow (s)
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float grow = smoothstep(0.0, uBark.y, uPen.x - st.t);
  float r = st.halfWidth * uBark.x * (0.55 + 0.45 * grow) + 0.4;
  float a = cover(st.wdist, r);
  if (a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float x = clamp(st.across / r, -1.0, 1.0);
  float round = sqrt(max(1.0 - x * x, 0.0));
  float streak = vnoise(vec2(st.s * 0.08, st.across * 0.9 + st.index * 7.0));
  // (Cherry bark's marks: short lines across, here and there.)
  float mark = step(0.9, hash12(vec2(floor(st.s / 7.0), st.index))) *
      (1.0 - smoothstep(0.15, 0.3, abs(fract(st.s / 7.0) - 0.5) * 2.0)) * step(abs(x), 0.55);
  vec3 bark = mix(vec3(0.22, 0.15, 0.13), vec3(0.45, 0.34, 0.29), streak * 0.6 + round * 0.4);
  bark = mix(bark, vec3(0.62, 0.55, 0.5), mark * 0.35);
  bark *= 0.75 + 0.25 * round;
  fragColor = vec4(bark * a, a);
}
