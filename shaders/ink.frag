#version 460 core
// Plain ink, as fountain_pen draws it: darker at its edges, wet a moment
// behind the pen. The control: the same text, no effect.
#include "stroke_space.glsl"

uniform vec4 uInk;  // its colour; how much it glistens wet
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  float a = cover(st.wdist, st.halfWidth);
  if (a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float edge = smoothstep(0.2, 1.0, abs(st.across) / max(st.halfWidth, 0.5));
  vec3 c = mix(uInk.rgb * 1.7 + 0.04, uInk.rgb, 0.6 + 0.4 * edge);
  float wet = (1.0 - smoothstep(0.0, 0.4, uPen.x - st.t)) * uInk.a;
  c = mix(c, vec3(0.05, 0.16, 0.52), wet * 0.45);
  fragColor = vec4(c * a, a);
}
