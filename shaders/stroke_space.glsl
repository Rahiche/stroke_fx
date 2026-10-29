// Stroke space: what a fragment of a stroke mesh knows about where it is on
// its stroke, and when the pen was there. Every stroke shader includes this;
// StrokeMesh.setUniforms (lib/src/space.dart) sets these first uniforms and
// the strokes' image. FlutterFragCoord() is the mesh's texture coordinate:
// a point in the stroke's cell (on Impeller, a texel of an image of the
// cells; on the web, the coordinate itself).
#include <flutter/runtime_effect.glsl>

// A cell's width and height (texels), cells down a column, texels to the px.
uniform vec4 uCell;
// The cells' gutter (texels), how far the round ends reach (px), the halo
// round the ink (px), the strokes.
uniform vec4 uSpace;
// The strokes' image's width and height, the writing's length (s), the
// broadest the ink gets (half-width, px).
uniform vec4 uData;
// Now (s), the stroke the pen is on (-1: none), how far along it (px), the
// x-height (px).
uniform vec4 uPen;
uniform sampler2D uStrokes;

struct Stroke {
  float index;      // in writing order
  float order;      // index / (strokes - 1)
  float character;  // the character it's part of, in its line (mod 256)
  float line;
  float flags;      // 1 a dot, 2 written late, 4 the pen landed for it, 8 joined
  float len;        // its length (px)
  float t0;         // when the pen started it (s)
  float t1;         // when the pen finished it (s)
  float s;          // px along it from its start (below 0 or past len: round ends)
  float v;          // across the mesh, -1 to 1
  float halfWidth;  // the ink's half-width here (px)
  float across;     // px from the centre line, signed
  float dist;       // px from the centre line, round its ends
  float t;          // when the pen passed here (s)
  float speed;      // how fast the pen went here (px/s)
  float at0;        // which of its sample points (and how far on to the next)
  float frac;
  float written;    // how much of it is written by now (px; -1: not begun)
  float wdist;      // px from the part written so far (1e4 if none)
};

vec4 strokeTexel(float x, float y) {
  return texture(uStrokes, (vec2(x, y) + 0.5) / uData.xy);
}

float unit16(vec4 c) {
  return (floor(c.r * 255.0 + 0.5) * 256.0 + floor(c.g * 255.0 + 0.5)) / 65535.0;
}

float byte(float c) {
  return floor(c * 255.0 + 0.5);
}

bool hasFlag(float flags, float bit) {
  return mod(floor(flags / bit), 2.0) > 0.5;
}

Stroke strokeAt(vec2 uv) {
  Stroke st;
  float col = floor(uv.x / uCell.x);
  float row = floor(uv.y / uCell.y);
  st.index = col * uCell.z + row;
  vec2 local = uv - vec2(col * uCell.x, row * uCell.y);
  st.s = (local.x - uSpace.x) / uCell.w - uSpace.y;
  st.v = clamp((local.y - uSpace.x) / (uCell.y - 2.0 * uSpace.x) * 2.0 - 1.0, -1.0, 1.0);
  vec4 m0 = strokeTexel(0.0, st.index);
  vec4 m1 = strokeTexel(1.0, st.index);
  vec4 m2 = strokeTexel(2.0, st.index);
  vec4 m3 = strokeTexel(3.0, st.index);
  st.len = unit16(m0) * 65535.0 / 8.0;
  st.flags = byte(m0.b);
  st.t0 = unit16(m1) * uData.z;
  st.character = byte(m1.b);
  st.t1 = unit16(m2) * uData.z;
  st.line = byte(m2.b);
  st.order = unit16(m3);
  // (Between the two samples either side.)
  float n = (uData.x - 4.0) / 2.0;
  float sc = clamp(st.s, 0.0, st.len);
  float j = st.len > 0.0 ? sc / st.len * (n - 1.0) : 0.0;
  float j0 = min(floor(j), n - 2.0);
  float f = j - j0;
  st.at0 = j0;
  st.frac = f;
  vec4 a = strokeTexel(4.0 + j0, st.index);
  vec4 b = strokeTexel(5.0 + j0, st.index);
  float ta = unit16(a) * uData.z;
  float tb = unit16(b) * uData.z;
  st.t = mix(ta, tb, f);
  st.halfWidth = mix(byte(a.b), byte(b.b), f) / 255.0 * uData.w;
  st.speed = st.len / (n - 1.0) / max(tb - ta, 1e-4);
  st.across = st.v * (st.halfWidth + uSpace.z);
  st.dist = length(vec2(st.s - sc, st.across));
  float now = uPen.x;
  if (now >= st.t1) {
    st.written = st.len;
  } else if (now >= st.t0) {
    st.written = abs(st.index - uPen.y) < 0.5 ? uPen.z
        : st.len * clamp((now - st.t0) / max(st.t1 - st.t0, 1e-4), 0.0, 1.0);
    // (A dot grows as it's made.)
    if (hasFlag(st.flags, 1.0)) st.halfWidth *= clamp((now - st.t0) / max(st.t1 - st.t0, 1e-4), 0.0, 1.0);
  } else {
    st.written = -1.0;
  }
  st.wdist = st.written < 0.0 ? 1e4 : length(vec2(st.s - clamp(st.s, 0.0, st.written), st.across));
  return st;
}

// Which way the stroke goes here, on screen (a unit vector; for a dot, x).
vec2 strokeDirection(Stroke st) {
  float n = (uData.x - 4.0) / 2.0;
  float a0 = unit16(strokeTexel(4.0 + n + st.at0, st.index)) * 6.2831853 - 3.1415927;
  float a1 = unit16(strokeTexel(5.0 + n + st.at0, st.index)) * 6.2831853 - 3.1415927;
  vec2 d = mix(vec2(cos(a0), sin(a0)), vec2(cos(a1), sin(a1)), st.frac);
  return d / max(length(d), 1e-4);
}

// How much of a pixel at [d] px from a line [r] px broad (half) it covers,
// smoothed over about a texel.
float cover(float d, float r) {
  float aa = 0.7 / uCell.w;
  return 1.0 - smoothstep(r - aa, r + aa, d);
}

// 1 well inside the mesh, 0 at its edge: so a glow never shows the strip's
// outline.
float meshFade(Stroke st) {
  return 1.0 - smoothstep(0.75, 1.0, abs(st.v));
}
