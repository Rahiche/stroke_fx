#version 460 core
// Constellation's strokes: fine threads of light drawn as the pen goes,
// a glint running along each now and then.
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uThread;  // its half-width (px), its brightness, the glints' speed (px/s)
uniform vec4 uColor;   // its colour
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float now = uPen.x;
  float line = cover(st.wdist, uThread.x);
  float sigma = uThread.x * 2.5;
  float halo = exp(-st.wdist * st.wdist / (2.0 * sigma * sigma)) * 0.35 * meshFade(st);
  // A glint running along it, each stroke its own time.
  float period = 2.5 + hash11(st.index) * 2.0;
  float at = fract(now / period + hash11(st.index + 7.0)) * (st.len + 200.0) - 100.0;
  float glint = exp(-abs(st.s - at) / 14.0) * exp(-st.wdist / (uThread.x * 3.0));
  float fresh = 1.0 - smoothstep(0.0, 0.8, now - st.t);
  float b = uThread.y * (line + halo) * (1.0 + fresh) + glint * 0.9;
  vec3 c = uColor.rgb * b + vec3(1.0) * glint * 0.5;
  fragColor = vec4(min(c, vec3(1.0)), clamp(max(line, halo) * uThread.y + glint * 0.6, 0.0, 1.0));
}
