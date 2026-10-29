#version 460 core
// Weld, on the joints: as the pen gets to one, a flash with rays, then a
// bead that glows and cools, temper colours round it (sparks fly from
// Dart: Weld in lib/src/effects.dart).
#include "joint_space.glsl"
#include "noise.glsl"

uniform vec4 uWeld;  // the flash's length (s), the bead's cooling (s), the rays' reach (of the square), the bead's size (of the inks')
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
  float bead = max(j.size * uWeld.w, 2.5);
  float hot = exp(-tau / uWeld.y);
  float flash = exp(-tau / uWeld.x);
  // The bead, rippled, glowing then grey.
  float rip = 0.85 + 0.15 * sin(d / bead * 9.0 - atan(j.p.y, j.p.x) * 2.0 + j.index);
  float inBead = jointCover(d, bead * rip);
  float bulge = sqrt(max(1.0 - d * d / (bead * bead), 0.0));
  vec3 grey = vec3(0.55, 0.57, 0.6) * (0.5 + 0.5 * bulge) + vec3(0.8) * pow(bulge, 10.0) * 0.4;
  vec3 hotc = vec3(1.0, 0.55 + 0.45 * hot, 0.15 + 0.85 * hot * hot);
  vec3 beadC = mix(grey, hotc, smoothstep(0.1, 0.5, hot));
  // Temper colours round it as it cools: straw, bronze, purple, blue.
  float ringR = (d - bead) / (bead * 2.2);
  vec3 temper = ringR < 0.33 ? vec3(0.75, 0.62, 0.32) : (ringR < 0.66 ? vec3(0.55, 0.32, 0.45) : vec3(0.28, 0.38, 0.7));
  float tint = (1.0 - smoothstep(0.0, 1.0, ringR)) * step(0.0, ringR) * smoothstep(0.0, 0.6, 1.0 - hot) * 0.45 * fade;
  // The flash: a white core and four rays.
  float ang = atan(j.p.y, j.p.x) + j.index * 0.7;
  float rays = pow(abs(cos(ang * 2.0)), 60.0) * exp(-d / (j.r * uWeld.z * (0.3 + 0.7 * flash)));
  float core = exp(-d / (bead * 1.6));
  float light = (core * 1.6 + rays * 1.2) * flash + core * hot * 0.5;
  vec3 c = beadC * inBead + temper * tint * (1.0 - inBead) + vec3(1.0, 0.9, 0.75) * light * fade;
  float a = clamp(max(inBead, max(tint, light * 0.8 * fade)), 0.0, 1.0);
  fragColor = vec4(min(c, vec3(1.0)), a);
}
