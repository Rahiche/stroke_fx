#version 460 core
// Dew's strokes: spider silk, fine and silvery, thin-film colours shifting
// along it (the strip sags and sways, bent in Dart: Dew).
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uSilk;  // its half-width (px), how bright it is
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float line = cover(st.wdist, uSilk.x);
  float halo = exp(-st.wdist / (uSilk.x * 3.0)) * 0.28 * meshFade(st);
  float film = st.s * 0.03 + uPen.x * 0.2 + st.index * 0.37;
  vec3 iris = 0.5 + 0.5 * cos(6.28318 * (film + vec3(0.0, 0.33, 0.67)));
  vec3 c = mix(vec3(0.9, 0.93, 0.97), iris, 0.22);
  float fresh = 1.0 - smoothstep(0.0, 0.6, uPen.x - st.t);
  float a = clamp((line + halo) * uSilk.y * (1.0 + 0.6 * fresh), 0.0, 1.0);
  fragColor = vec4(c * a, a);
}
