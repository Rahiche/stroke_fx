#version 460 core
// Neon: each stroke a glass tube that lights as the pen reaches it, with
// light running along it the way it was written.
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uTubeA;  // one colour; how fast the light runs (px/s)
uniform vec4 uTubeB;  // the other colour; the pulses' spacing (px)
uniform vec4 uGlass;  // the tube's half-width, the glow's reach (px); 1: just the lit tubes, to blur for a bloom
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  float now = uPen.x;
  float r = uGlass.x;
  // Unlit glass, where the pen hasn't been yet.
  float glass = cover(st.dist, r) * 0.2;
  vec3 dull = vec3(0.42, 0.45, 0.52);
  if (st.written < 0.0) {
    fragColor = vec4(dull * glass, glass);
    return;
  }
  float d = st.wdist;
  vec3 col = mix(uTubeA.rgb, uTubeB.rgb, mod(st.character + st.line, 2.0));
  // Struck: it flickers a moment as the gas lights.
  float age = now - st.t;
  float strike = 1.0;
  if (age < 0.6) {
    float f = hash12(vec2(floor(now * 20.0), st.index));
    strike = mix(0.2 + 0.8 * step(0.4, f), 1.0, smoothstep(0.1, 0.6, age));
  }
  float phase = (st.s - now * uTubeA.w) / uTubeB.w;
  float pulse = pow(0.5 + 0.5 * cos(6.28318 * phase), 8.0);
  float tube = cover(d, r);
  if (uGlass.z > 0.5) {
    float lit = cover(d, r * 1.6) * strike * (0.75 + 0.5 * pulse);
    fragColor = vec4(col * lit, lit);
    return;
  }
  float core = cover(d, r * 0.4);
  float glow = exp(-max(d - r, 0.0) / uGlass.y) * meshFade(st);
  vec3 c = col * (tube * (0.8 + 0.7 * pulse) + glow * (0.5 + 0.35 * pulse))
      + vec3(1.0) * core * (0.5 + 0.5 * pulse);
  float a = clamp(max(tube, glow * 0.55), 0.0, 1.0);
  c *= strike;
  a *= strike;
  // (The unlit glass still shows past the pen.)
  float rest = glass * (1.0 - tube);
  fragColor = vec4(min(c + dull * rest, vec3(1.0)), max(a, rest));
}
