#version 460 core
// Ink bleed: wet ink spreads into the paper's fibres as it dries, most where
// the pen went slowly or came down, and gathers at the edge it dries to.
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uInk;    // its colour; how long it stays wet (s)
uniform vec4 uBleed;  // how far it bleeds (of the half-width), the fibres' size (px), the pen's usual speed (px/s), how much pools where it lands
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float now = uPen.x;
  float wet = exp(-max(now - st.t, 0.0) / uInk.a);
  float spread = 1.0 - wet;
  float lingering = clamp(uBleed.z / max(st.speed, 1.0), 0.4, 2.5);
  float pool = hasFlag(st.flags, 4.0) ? exp(-max(st.s, 0.0) / (st.halfWidth * 3.0 + 1.0)) : 0.0;
  float fibre = fbm(vec2(st.s * 0.7, st.across * 1.6) / uBleed.y + st.index * 3.1);
  fibre = fibre * fibre * 1.8;
  float reach = st.halfWidth * (1.0 + uBleed.x * spread * pow(lingering, 1.3) * (0.15 + fibre)
      + uBleed.w * pool * (0.4 + 0.6 * spread));
  reach = min(reach, st.halfWidth + uSpace.z * 0.9);
  float d = st.wdist;
  float body = cover(d, reach);
  if (body <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float core = cover(d, st.halfWidth);
  float edge = smoothstep(reach * 0.75, reach * 0.98, d) * spread;
  float grain = vnoise(vec2(st.s, st.across) * 0.8 + st.index * 13.0);
  float density = mix(0.1 + 0.16 * grain, 0.95, core) + 0.35 * edge * (1.0 - core);
  density *= mix(1.0, 0.85 + 0.2 * lingering, core);
  vec3 c = uInk.rgb * (1.0 - 0.3 * wet) + vec3(0.0, 0.03, 0.12) * (1.0 - core) * spread;
  float a = clamp(body * density, 0.0, 1.0);
  fragColor = vec4(c * a, a);
}
