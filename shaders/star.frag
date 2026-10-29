#version 460 core
// Constellation's joints: each a star that lights as the pen gets to it,
// then twinkles. (Its ripple, which outgrows the square, is a ring drawn in
// Dart: Constellation.)
#include "joint_space.glsl"
#include "noise.glsl"

uniform vec4 uStar;   // the ripple's speed (px/s) and length (s), the star's size (of the inks'), the spikes' reach (of the square)
uniform vec4 uJoin;   // a join's colour
uniform vec4 uTouch;  // a touch's
uniform vec4 uCross;  // a crossing's
out vec4 fragColor;

void main() {
  Joint j = jointAt(FlutterFragCoord().xy);
  float tau = uJPen.x - j.t;
  if (tau < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float d = length(j.p);
  float fade = squareFade(j);
  vec3 col = j.kind < 0.5 ? uJoin.rgb : (j.kind < 1.5 ? uTouch.rgb : uCross.rgb);
  // Lit with a pop (a little past full, then settling); twinkling after.
  float k = clamp(tau / 0.35, 0.0, 1.0);
  float pop = 1.0 + 0.6 * sin(k * 3.14159) * (1.0 - k) + 0.25 * exp(-tau * 6.0);
  float twinkle = 0.8 + 0.2 * sin(uJPen.x * (2.0 + hash11(j.index) * 2.0) + j.index * 1.9);
  float kindScale = j.kind > 0.5 && j.kind < 1.5 ? 0.65 : 1.0;
  float settle = 0.7 + 0.3 * exp(-tau * 1.5);
  float size = max(j.size * uStar.z, 2.0) * kindScale * pop * settle * twinkle * smoothstep(0.0, 0.08, tau);
  float core = exp(-d * d / (size * size) * 1.5);
  float ang = atan(j.p.y, j.p.x) + uJPen.x * 0.15 + j.index;
  float spikes = (pow(abs(cos(ang * 2.0)), 140.0) + 0.4 * pow(abs(sin(ang * 2.0)), 200.0))
      * exp(-d / (j.r * uStar.w * kindScale * pop * settle * twinkle)) * (0.5 + 0.5 * exp(-tau * 2.0));
  float light = (core * 1.3 + spikes * 0.9) * fade;
  vec3 c = mix(col, vec3(1.0), core * 0.7) * light;
  fragColor = vec4(min(c, vec3(1.0)), clamp(light * 0.85, 0.0, 1.0));
}
