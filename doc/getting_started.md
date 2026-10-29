# Getting started

## Install

```sh
flutter pub add stroke_fx fountain_pen
```

fountain_pen brings the hands: `homemadeApple` (Latin), `notoSansJapanese` and `notoNaskhArabic` (Arabic, Persian,
Urdu). stroke_fx brings the effects.

## The widget

```dart
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/stroke_fx.dart';

StrokeFxText('Stroke by stroke', effect: Neon());
StrokeFxText('手書きの日本語', hand: notoSansJapanese, effect: Frost());
StrokeFxText('بالقلم والحبر', hand: notoNaskhArabic, effect: Sakura(), duration: 4);
```

`StrokeFxText` writes the text with the effect, fitted to its box, and writes it again after `hold` seconds
(`repeat: false` to write it once).

## Painting it yourself

Build a text's stroke space once, then paint it at any moment with any effect:

```dart
await StrokeShaders.load();
final text = await StrokeText.of(WrittenText('Hello', fontSize: 96, duration: 3));

CustomPaint(
  painter: StrokeFxPainter(
    text: text,
    effect: Ember(),
    time: clock, // a ValueListenable<double>: seconds into the writing
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  ),
);
```

Or paint into a canvas you've placed yourself: `effect.paint(canvas, text, seconds, scale)`, where `scale` is the
canvas's scale times the device pixel ratio.

## Writing as it's typed

```dart
WrittenText(typed, hand: homemadeApple, typing: true, typedAt: whenEachCharacterWasTyped);
```

Typing more leaves what's already written exactly as it was, and each character is written no sooner than it was
typed. Keep a clock running and the earlier letters go on ageing (cooling, freezing, shedding petals) while the new ones
are written. The example's text box does this.

## The effects

| Effect | What happens |
|---|---|
| `PlainInk` | fountain_pen's ink, drawn through the same mesh: the control. |
| `Neon` | Each stroke a glass tube that lights as the pen reaches it; light runs the way it was written. |
| `Ember` | Molten metal that runs along the stroke and cools to cracked charcoal. |
| `InkBleed` | Ink bleeds into the paper as it dries, most where the pen went slowly or came down. |
| `Ribbon` | Each stroke a two-faced ribbon, twisting along it, the mesh waving. |
| `Weld` | Steel beads; every joint flashes and throws sparks as the pen reaches it. |
| `Constellation` | Threads of light; every joint a star that ripples as it lights. |
| `Frost` | The ink freezes as it's written; ice crystals grow first where strokes meet. |
| `Dew` | Spider silk pinned at its joints sags with a bounce and gathers dew. |
| `Sakura` | Branches grow; blossoms open at the joints and shed petals on the breeze. |
| `Ivy` | A vine climbs each stroke, twining round it; leaves open, tendrils coil. |
| `Jelly` | The pen drags the soft jelly it writes on; let go, it springs back. |
| `Snow` | Snow settles only where an edge faces up, deepening the longer it lies. |
| `Fireflies` | Fireflies rise from the ink and fall into step, blinking together. |

## Your own effect

Subclass `StrokeEffect` and paint the text's mesh with your own fragment shader:

```dart
class Chalk extends StrokeEffect {
  @override
  String get name => 'Chalk';

  @override
  Color get background => const Color(0xFF1E2A24);

  @override
  double halo(double xHeight) => xHeight * 0.1;

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final mesh = text.mesh(halo(text.writing.xHeight), scale);
    final sh = shader('chalk');
    final next = mesh.setUniforms(sh, now); // then your own floats from here
    sh.setFloat(next, 0.8);
    draw(canvas, mesh.vertices, sh);
  }
}

// Once, before painting:
StrokeShaders.register('chalk', await FragmentProgram.fromAsset('shaders/chalk.frag'));
```

Your shader includes a copy of the package's `shaders/stroke_space.glsl` (and `noise.glsl`, if it wants noise), put
next to it in your app, since a shader can't include files from another package. Then every pixel knows its place on
its stroke:

```glsl
#version 460 core
#include "stroke_space.glsl"
#include "noise.glsl"

uniform float uDust;
out vec4 fragColor;

void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  if (st.written < 0.0) { fragColor = vec4(0.0); return; }   // not begun
  float ink = cover(st.wdist, st.halfWidth);                  // what's written so far
  float grain = vnoise(vec2(st.s, st.across) * 0.7);          // along and across it
  float a = ink * mix(0.6, 1.0, grain) * uDust;
  fragColor = vec4(vec3(0.95) * a, a);
}
```

`Stroke` also has `t` (when the pen passed here), `t0` and `t1` (when it started and finished the stroke), `speed`,
`order`, `index`, `character`, `flags` and `strokeDirection(st)`. For joints, `text.joints` and `text.jointMesh`,
with `joint_space.glsl`. [How it works](how_it_works.md) has the details.
