#version 460 core
// Small things drawn from one shared cell, all alike (placed, sized, turned
// and tinted by the mesh and its colours): a dew drop, a cherry blossom, a
// fallen petal, a honey drop.
#include <flutter/runtime_effect.glsl>

uniform vec4 uSprite;  // the cell's size (texels), which (0 dew, 1 blossom, 2 petal, 3 honey, 4 leaf, 5 ivy leaf, 6 glow), how open (blossom)
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy / uSprite.x * 2.0 - 1.0;
  float r = length(p);
  float aa = 2.5 / uSprite.x;
  float kind = uSprite.y;
  if (kind < 0.5) {
    // A dew drop: a lens. Dark round its rim, the light through it gathered
    // low, a highlight high.
    float body = 1.0 - smoothstep(0.92 - aa, 0.92 + aa, r);
    float rim = smoothstep(0.55, 0.92, r);
    vec2 h = p - vec2(-0.32, -0.38);
    float highlight = exp(-dot(h, h) * 34.0);
    vec2 g = p - vec2(0.12, 0.42);
    float caustic = exp(-dot(g, g) * 9.0) * 0.55;
    vec3 c = vec3(0.70, 0.84, 0.92) * (0.18 + 0.55 * rim) + vec3(0.9, 1.0, 1.0) * caustic + vec3(1.0) * highlight;
    float a = body * (0.32 + 0.5 * rim) + highlight + caustic * 0.5;
    fragColor = vec4(min(c * body, vec3(1.0)), clamp(a, 0.0, 1.0) * body);
  } else if (kind < 1.5) {
    // A cherry blossom: five petals, each notched at its tip, opening.
    float open = clamp(uSprite.z, 0.0, 1.0);
    float angle = atan(p.y, p.x);
    float k = mod(angle + 0.314159, 1.256637) - 0.628318;
    float edge = 0.95 - 0.55 * pow(abs(k) / 0.628318, 1.6);
    edge -= 0.16 * (1.0 - smoothstep(0.0, 0.14, abs(k)));
    float petal = 1.0 - smoothstep(edge - aa, edge + aa, r);
    vec3 pink = mix(vec3(0.98, 0.62, 0.74), vec3(1.0, 0.93, 0.95), smoothstep(0.1, 0.8, r));
    float vein = (1.0 - smoothstep(0.0, 0.05, abs(k))) * (1.0 - smoothstep(0.2, 0.8, r)) * 0.25;
    float stamens = (1.0 - smoothstep(0.0, 0.06, abs(r - 0.3))) * step(0.5, fract(angle * 3.0)) ;
    vec3 c = pink * (1.0 - vein) + vec3(0.98, 0.78, 0.25) * stamens * 0.8;
    float centre = 1.0 - smoothstep(0.12, 0.18, r);
    c = mix(c, vec3(0.85, 0.35, 0.45), centre);
    fragColor = vec4(c * petal, petal) * open;
  } else if (kind < 2.5) {
    // A fallen petal: an oval, notched at its tip.
    vec2 q = vec2(p.x / 0.6, p.y);
    float d = length(q);
    float notch = (1.0 - smoothstep(0.0, 0.2, abs(p.x))) * smoothstep(0.55, 0.95, -p.y) * 0.35;
    float petal = 1.0 - smoothstep(0.92 - notch - aa, 0.92 - notch + aa, d);
    vec3 c = mix(vec3(1.0, 0.9, 0.93), vec3(0.97, 0.6, 0.72), smoothstep(-0.2, 1.0, p.y));
    fragColor = vec4(c * petal, petal);
  } else if (kind > 5.5) {
    // A glow: soft all the way out, bright at its heart (a snowflake far
    // off, a firefly).
    float glow = pow(max(1.0 - r, 0.0), 2.2);
    float heart = 1.0 - smoothstep(0.0, 0.22, r);
    float a = clamp(glow * 0.75 + heart, 0.0, 1.0);
    fragColor = vec4(vec3(a), a);
  } else if (kind > 4.5) {
    // An ivy leaf, its tip up (y = -1), its stalk down: five pointed lobes,
    // a heart at its base, pale veins out from where the stalk joins.
    vec2 c = p - vec2(0.0, 0.2);
    float th = atan(c.x, -c.y);
    float lobes = 0.0;
    lobes = max(lobes, 1.00 * pow(max(cos((th) * 1.7), 0.0), 7.0));
    lobes = max(lobes, 0.80 * pow(max(cos((th - 1.15) * 1.9), 0.0), 7.0));
    lobes = max(lobes, 0.80 * pow(max(cos((th + 1.15) * 1.9), 0.0), 7.0));
    lobes = max(lobes, 0.50 * pow(max(cos((th - 2.2) * 2.2), 0.0), 6.0));
    lobes = max(lobes, 0.50 * pow(max(cos((th + 2.2) * 2.2), 0.0), 6.0));
    float edge = 0.42 + 0.66 * lobes - 0.25 * pow(max(-cos(th), 0.0), 8.0);
    float d = length(c);
    float leaf = 1.0 - smoothstep(edge - aa, edge + aa, d);
    float stalk = (1.0 - smoothstep(0.035, 0.06, abs(p.x))) * step(0.55, p.y);
    vec2 v = p - vec2(0.0, 0.45);
    float ang = atan(v.x, -v.y);
    float vein = 0.0;
    for (int i = -2; i <= 2; i++) {
      vein = max(vein, 1.0 - smoothstep(0.0, 0.045, abs(ang - float(i) * 0.95) * length(v)));
    }
    vec3 green = mix(vec3(0.10, 0.28, 0.10), vec3(0.22, 0.45, 0.16), smoothstep(0.9, 0.1, d));
    vec3 col = mix(green, vec3(0.55, 0.7, 0.4), vein * 0.55 * leaf);
    col += vec3(0.25) * exp(-dot(c - vec2(-0.2, -0.25), c - vec2(-0.2, -0.25)) * 6.0) * leaf;
    vec3 stem = vec3(0.32, 0.42, 0.18);
    float a = max(leaf, stalk);
    fragColor = vec4(mix(stem, col, leaf) * a, a);
  } else if (kind > 3.5) {
    // A leaf, its tip up (y = -1), its stalk down: pointed, its midrib and
    // veins a little lighter.
    float t = (1.0 - p.y) / 2.0;
    float halfWidth = 0.46 * pow(sin(3.14159 * clamp(t, 0.0, 1.0)), 0.75) * (1.0 - 0.3 * t);
    float leaf = (1.0 - smoothstep(halfWidth - aa, halfWidth + aa, abs(p.x))) * step(0.0, t) * step(t, 1.0);
    float stalk = (1.0 - smoothstep(0.03, 0.05, abs(p.x))) * step(0.92, p.y);
    float rib = 1.0 - smoothstep(0.0, 0.035, abs(p.x));
    float vein = (1.0 - smoothstep(0.0, 0.06, abs(fract((p.y + abs(p.x) * 1.3) * 3.5) - 0.5))) * 0.35;
    vec3 green = mix(vec3(0.22, 0.48, 0.18), vec3(0.45, 0.68, 0.25), smoothstep(-0.5, 0.5, p.x) * 0.6 + 0.2);
    vec3 c = green + vec3(0.25, 0.3, 0.15) * max(rib * 0.8, vein * leaf);
    float a = max(leaf, stalk);
    fragColor = vec4(c * a, a);
  } else {
    // A honey drop: amber, lit from within, a highlight high.
    float body = 1.0 - smoothstep(0.92 - aa, 0.92 + aa, r);
    vec2 h = p - vec2(-0.3, -0.35);
    float highlight = exp(-dot(h, h) * 30.0);
    vec3 amber = mix(vec3(0.95, 0.62, 0.12), vec3(0.6, 0.25, 0.02), smoothstep(0.2, 0.92, r));
    vec2 g = p - vec2(0.1, 0.35);
    amber += vec3(1.0, 0.8, 0.3) * exp(-dot(g, g) * 7.0) * 0.5;
    fragColor = vec4(min(amber + highlight, vec3(1.0)) * body, body);
  }
}
