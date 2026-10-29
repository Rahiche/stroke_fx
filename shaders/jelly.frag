#version 460 core
// Jelly's strokes: thick, glossy, a little translucent, lit as a soft tube
// from the top left (the mesh itself wobbles, moved in Dart: Jelly).
#include "stroke_space.glsl"
#include "noise.glsl"

uniform vec4 uJelly;  // how much thicker than the ink, opacity, 1: draw just its shadow
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float r = st.halfWidth * uJelly.x + 0.7;
  if (uJelly.z > 0.5) {
    // (Its shadow: soft-edged here, so it needs no blur.)
    float soft = 1.0 - smoothstep(r * 0.6, r + uPen.w * 0.09, st.wdist);
    fragColor = vec4(0.0, 0.0, 0.0, soft * 0.22);
    return;
  }
  float a = cover(st.wdist, r);
  if (a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  // A tube's normal: round across it, its side turned by which way the
  // stroke goes on screen.
  vec2 t = strokeDirection(st);
  vec2 g = st.wdist > 1e-3 ? vec2(st.s - clamp(st.s, 0.0, st.written), st.across) / st.wdist : vec2(0.0, 1.0);
  vec2 out2 = g.x * t + g.y * vec2(-t.y, t.x);
  float x = clamp(st.wdist / r, 0.0, 1.0);
  vec3 n = normalize(vec3(out2 * x, sqrt(max(1.0 - x * x, 0.0))));
  vec3 light = normalize(vec3(-0.5, -0.7, 0.6));
  float diffuse = max(dot(n, light), 0.0);
  float spec = pow(max(dot(reflect(-light, n), vec3(0.0, 0.0, 1.0)), 0.0), 28.0);
  vec3 base = hsv(fract(st.character * 0.13 + st.line * 0.37 + 0.92), 0.62, 0.96);
  // (Light through it: brighter where it's thickest.)
  vec3 c = base * (0.42 + 0.5 * diffuse) + base * 0.28 * n.z + vec3(1.0) * spec * 0.85;
  // (A darker rim, so strokes lying over each other stay apart.)
  c *= mix(1.0, 0.68, smoothstep(0.72, 1.0, x));
  float alpha = a * uJelly.y;
  fragColor = vec4(min(c, vec3(1.0)) * alpha, alpha);
}
