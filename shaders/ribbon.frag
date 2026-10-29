#version 460 core
// Ribbon: each stroke a ribbon that twists as it goes, its two faces in two
// colours (the mesh itself waves, moved in Dart: StrokeMesh.bent).
#include "stroke_space.glsl"

uniform vec4 uRibbon;  // its half-width (px), twists per px, how fast they travel, a phase per stroke
uniform vec4 uFront;   // one face's colour
uniform vec4 uBack;    // the other's
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float now = uPen.x;
  if (hasFlag(st.flags, 1.0)) {
    float a = cover(st.dist, uRibbon.x * 1.1);
    fragColor = vec4(uFront.rgb * a, a);
    return;
  }
  if (st.s < 0.0 || st.s > st.written) {
    fragColor = vec4(0.0);
    return;
  }
  float twist = st.s * uRibbon.y - now * uRibbon.z + st.index * uRibbon.w;
  float w = cos(twist);
  float r = uRibbon.x * max(abs(w), 0.3);
  float a = cover(abs(st.across), r);
  float x = clamp(st.across / r, -1.0, 1.0);
  vec3 face = w >= 0.0 ? uFront.rgb : uBack.rgb;
  float light = 0.6 + 0.4 * (0.5 + 0.5 * sin(twist) * x);
  float shine = pow(max(0.0, 1.0 - abs(x - 0.55 * sin(twist))), 12.0) * abs(w);
  vec3 c = face * light * (1.0 - 0.3 * smoothstep(0.7, 1.0, abs(x))) + vec3(1.0) * shine * 0.5;
  // (Its leading edge, where the pen is, a little brighter.)
  c += face * 0.25 * (1.0 - smoothstep(0.0, uPen.w * 0.3, st.written - st.s)) * step(st.written, st.len - 0.01);
  fragColor = vec4(min(c, vec3(1.0)) * a, a);
}
