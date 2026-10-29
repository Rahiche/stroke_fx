// Joint space: what a fragment of a joint's square knows about its joint.
// Every joint shader includes this; JointMesh.setUniforms
// (lib/src/space.dart) sets these first uniforms and the joints' image.
#include <flutter/runtime_effect.glsl>

// A cell's size (texels), cells across, texels to the px, the square's
// half-size (px).
uniform vec4 uJCell;
// The joints' image's width, the joints, the writing's length (s), the
// x-height (px).
uniform vec4 uJData;
// Now (s), the broadest two inks together (px).
uniform vec4 uJPen;
uniform sampler2D uJoints;

struct Joint {
  float index;  // in the order they form
  vec2 p;       // px from the joint
  float r;      // the square's half-size (px)
  float t;      // when it forms (s)
  float kind;   // 0 a join, 1 a touch, 2 a crossing
  float angle;  // the angle its strokes meet at (radians, 0 to pi/2)
  float size;   // the two inks' half-widths together (px)
};

float jointUnit16(vec4 c) {
  return (floor(c.r * 255.0 + 0.5) * 256.0 + floor(c.g * 255.0 + 0.5)) / 65535.0;
}

Joint jointAt(vec2 uv) {
  Joint j;
  float col = floor(uv.x / uJCell.x);
  float row = floor(uv.y / uJCell.x);
  j.index = row * uJCell.y + col;
  vec2 local = uv - vec2(col, row) * uJCell.x - 2.0;
  j.r = uJCell.w;
  j.p = local / uJCell.z - j.r;
  vec4 a = texture(uJoints, (vec2(j.index, 0.0) + 0.5) / vec2(uJData.x, 2.0));
  vec4 b = texture(uJoints, (vec2(j.index, 1.0) + 0.5) / vec2(uJData.x, 2.0));
  j.t = jointUnit16(a) * uJData.z;
  j.kind = floor(a.b * 255.0 + 0.5);
  j.angle = jointUnit16(b) * 1.5707963;
  j.size = floor(b.b * 255.0 + 0.5) / 255.0 * uJPen.y;
  return j;
}

// 1 well inside the square, 0 before its edge: a round fade, so nothing
// drawn in it ever shows the square's corners or sides.
float squareFade(Joint j) {
  return 1.0 - smoothstep(0.7 * j.r, 0.98 * j.r, length(j.p));
}

float jointCover(float d, float r) {
  float aa = 0.7 / uJCell.z;
  return 1.0 - smoothstep(r - aa, r + aa, d);
}
