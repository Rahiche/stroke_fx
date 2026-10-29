# How it works

stroke_fx puts effects **along the strokes** of handwritten text, and on the **joints** where strokes meet, instead of per letter. The text is written by [fountain_pen](https://pub.dev/packages/fountain_pen), in Latin, Japanese and Arabic.

## Prior art, and what's new

Not new:
- **Drawing strokes in order, with widths and writing order taken from any font, in many scripts.** [Tegaki](https://github.com/gkurt/tegaki) does this on the web, with Canvas 2D effect plugins (glow, taper, a gradient along each stroke) that see each point's progress.
- **Replaying recorded pen speed.** Blender Grease Pencil's Build modifier does it, for hand-drawn strokes.
- **Art along a path.** Illustrator's art and pattern brushes, Skeletal Strokes (Hsu and Lee, 1993), Lottie and Rive trim paths. On text, these work on glyph outlines, not centre lines.
- **`drawVertices` + texture coordinates + `FragmentShader`.** The [mesh](https://pub.dev/packages/mesh) package uses it for mesh gradients.

New:
- **A GPU fragment shader in stroke space on arbitrary text.** For every pixel it knows the stroke, how far along and across, and when the pen was there. That happens in Latin, Japanese (stroke order) and Arabic (joined, right to left). Every Flutter text effect found works per glyph or per widget.
- **Effects driven by pen time.** Ink cools, dries or freezes by when the pen passed each point. It bleeds where the pen was slow. Vines and branches grow behind the pen.
- **Physics and nature, by pen time and joints.**
  - Frost: ink freezes as it's written, and ice nucleates first at the joints.
  - Dew: silk sags between the joints it's pinned at, with a damped-spring bounce, and dew slides down to where each span hangs lowest.
  - Sakura: branches grow behind the pen; petals fall with drag and flutter in the wind.
  - Ivy: a vine twines round each stroke, its tendrils coiling as they age.
  - Jelly: the text lies on an elastic sheet, a grid of masses a third of an x-height apart, stepped at 240 Hz.
    - Springs to its neighbours carry the wobble; weaker springs to each mass's own place bring the sheet back; damping stills it.
    - The pen drags the sheet near its tip while writing. When it lifts at a stroke's end, the sheet springs back, wobbling.
    - Tuned to move at most 0.06–0.15 x-heights near the pen, and to settle within about a second of the writing ending.
  - Snow: snow settles only where an edge faces up. Which way is up comes from the stroke's direction on screen. It deepens the longer the ink has lain there.
  - Fireflies: they rise from the ink as the pen passes and blink as coupled oscillators (Kuramoto), out of step at first, then in step, as real fireflies do.
- **Writing as you type.** An append-stable layout mode: each character's wobble is its own, and each is written no sooner than it was typed. So letters are written live as they're typed, and earlier ones go on ageing (cooling, freezing, shedding petals) without moving.
- **Joints as effect targets.** Joins (the pen going on into the next letter), touches and crossings are found from the geometry, each with the moment it forms. Effects use them:
  - Weld sparks at each joint.
  - Constellation stars light up on them.
  - Frost crystals nucleate there.
  - Dew threads are pinned at them and pool there.
  - Sakura blossoms open on them.
  - Ivy gathers leaves at them.

  Nothing found treats joints as effect targets. Illustrator's corner tiles come closest, and only within a single path.

## The technical route

**Per-vertex data reaches the shader through texture coordinates.**
- When a `Canvas.drawVertices` mesh has `textureCoordinates` and its paint has a `FragmentShader`, `FlutterFragCoord()` is the interpolated texture coordinate.
- Checked on Flutter 3.47.5 with a curved strip: macOS Impeller (Metal), web CanvasKit and web skwasm.
- The backends differ in how:
  - **Impeller** renders the shader into an intermediate image covering the texture coordinates' bounds, one texel per unit, then maps that image onto the mesh. A sub-texel stripe pattern vanishes there and shows moiré on the web. Engine source: `impeller/display_list/canvas.cc`; flutter/flutter#162969.
  - **Skia (the web)** runs the shader per pixel at the texture coordinate.
- So:
  - Texture coordinates should be in device pixels (paint scale × device pixel ratio), or Impeller's image is blurry. UVs in 0–1 don't work (flutter/flutter#168969).
  - The coordinates' bounding box must be compact: Impeller shades every texel of it, every frame.
  - Each `drawVertices` call costs one offscreen pass on Impeller.
- Vertex colours with `BlendMode.modulate` tint the shader's output on all three renderers.

**Stroke space in two floats.**
- Each stroke gets a cell in a grid of cells. Across a cell runs the arc length along the stroke, with room for round ends. Down a cell runs the distance across the stroke.
- The shader works out the stroke from the cell, then looks the rest up in a small RGBA8 image, one row per stroke:
  - the stroke's length and flags (dot, late, pen landed, joined);
  - when the pen started and finished it;
  - its place in the writing order;
  - 60 samples along it of the time the pen got there and the ink's half-width;
  - 60 samples of its direction on screen, for effects lit from one side, or that need to know which way is up (Snow, Jelly).
- Values are 16-bit across two channels, with alpha kept at 255 so premultiplying can't change them. They're read at texel centres, so the result is exact with any filtering.
- `shaders/stroke_space.glsl` decodes it all into a `Stroke`: `s`, `v`, `across`, `dist`, `t`, `t0`, `t1`, `speed`, `written`, `wdist`, `order`, `flags` and `strokeDirection()`.

**The mesh: one strip per stroke, with a halo either side of the ink.**
- A strip can't turn a corner without folding, and a fold shows as rays: texture coordinates fanning out across it. Strokes are therefore:
  - split into runs at sharp corners, with a round fan filling each corner's outside;
  - limited on each side to the stroke's local middle line, the edge where the other side of a bend or corner is nearer. Each row's reach is measured by bisection against nearby centre-line points, and its `v` is the true distance, so `across` stays exact.
- Hand-written lines waver, so estimating curvature didn't work. Measuring did.
- `test/mesh_test.dart`: folded triangles are hairline slivers, 0.01–1.1% of the area, the most at a 20 px halo on cursive Latin.

**Joints.** Found in `lib/src/joints.dart` from the laid-out strokes and fountain_pen's flags.
- **Joins:** the pen didn't lift and went on into another letter.
- **Touches:** a stroke's end on another stroke, or on itself further along.
- **Crossings:** segment intersections, loops included.
- Each formed when the later stroke gets there.
- Duplicates are merged when they are close in both place and time.
- Joint shaders get a square per joint, cells in a grid, and a data image holding the time, kind, angle and size.

| Sample | Strokes | Joints |
|---|---|---|
| "Stroke by stroke" | 39 | 28 (mostly touches, some crossings) |
| 手書きの日本語 | 42 | 35 (25 touches, 10 crossings) |
| بالقلم والحبر | 18 | 12 (7 letter joins) |

**Particles and sprites** (sparks, ripples, dew, petals, leaves) are CPU-side, deterministic functions of time.
- Most are quads that all map to one shared shader cell, with size, rotation and tint from the mesh and its vertex colours.
- Weld's sparks are vertex-coloured streaks added on top. Constellation's ripples are soft rings of geometry, so they can grow past a joint's square without being clipped.
- On Impeller the shader then fills one small 128×128 image per frame.

## Costs and speed

| | |
|---|---|
| Building a text's stroke space (layout, joints, images) | 8–13 ms, once per text (JIT, `flutter test`) |
| Building a mesh | 0.5–3 ms, once per halo and scale |
| Vertices | 1.2–3k per text |
| Impeller's image a frame | 0.2–2.0 Mpx, by halo and stroke count |
| Draw calls per frame | 1–4 per effect |

Ribbon and Dew bend their mesh on the CPU every frame. Ivy's vines and the sprites are rebuilt every frame.

**macOS: Apple M3, Flutter 3.47.5, profile build, Impeller (MetalSDF), 1280×800 window at 2x (2560×1600 px).** Every effect × every sample holds 60 fps:

| | p50 | p90 |
|---|---|---|
| UI-thread build | 0.08–0.6 ms | ≤ 1.3 ms |
| Raster thread | 0.2–0.6 ms | ≤ 1.8 ms |

- There is one stall of 245 ms, the first time the Arabic sample is shown, while its mesh is built.
- There are occasional single-frame spikes of 20–43 ms as an effect is first switched to.
- The raster thread's time doesn't include the GPU's own. Sustained 60 fps shows the GPU keeps up.
- To rerun: `example/lib/main.dart` with `--dart-define=BENCH=true` (and `BENCH_ONLY=Name,...` for a subset).

| Effect | fps | Build p50 / p90 (ms) | Raster p50 / p90 (ms) |
|---|---|---|---|
| Plain ink, Neon, Ember, Ink bleed | 60 | 0.08–0.17 / ≤ 0.74 | 0.32–0.57 / ≤ 1.8 |
| Ribbon (mesh bent every frame) | 60 | 0.08–0.15 / ≤ 0.4 | 0.19–0.23 / ≤ 0.42 |
| Weld, Constellation (joints, sparks) | 60 | 0.09–0.14 / ≤ 0.5 | 0.23–0.45 / ≤ 1.76 |
| Frost | 60 | 0.20–0.21 / ≤ 0.56 | 0.80–0.83 / ≤ 1.63 |
| Dew (mesh bent, drops) | 59–60 | 0.84–1.85 / ≤ 2.77 | 0.63–0.84 / ≤ 1.34 |
| Sakura (blossoms, petals) | 60 | 0.20–0.31 / ≤ 0.56 | 0.59–0.84 / ≤ 1.13 |
| Ivy (vines rebuilt every frame) | 60 | 0.87–2.10 / ≤ 4.14 | 0.54–0.66 / ≤ 1.29 |
| Jelly (elastic sheet stepped at 240 Hz, mesh bent every frame) | 60 | 0.70–1.06 / ≤ 1.52 | 0.79–1.01 / ≤ 1.63 |
| Snow | 58.3–60 | 0.24–0.35 / ≤ 0.88 | 0.48–0.61 / ≤ 1.68 |
| Fireflies (coupled blinking, stepped at 120 Hz) | 60 | 0.30–0.41 / ≤ 0.82 | 0.79–1.36 / ≤ 1.69 |

- **Jelly's first shadow** was a blurred layer the size of the window. It dropped Jelly to 37 fps on the Japanese sample, the GPU's time not the CPU's. A soft edge drawn in its shader instead put it back to 60.
- **Neon's bloom layer** is now bounded by the text too.

**Web: Chrome 152 in the desktop app's browser pane, 1024×768 at 2x, requestAnimationFrame over 3 s, Japanese sample.**
- **CanvasKit:** every effect at 59.3–60 fps; p95 frame 17–19 ms, a 35 ms frame now and then on Ribbon. A first Ember measurement, taken while its shader compiled, gave 54 fps; measured again, 60.
- **skwasm:** every effect renders the same as on CanvasKit (checked by eye). Its frame rate wasn't measured: the browser pane was hidden by then, and a hidden page's frames are throttled to one a second.

## The API

```dart
// The drop-in widget: written, with an effect, looping.
StrokeFxText('手書きの日本語', hand: notoSansJapanese, effect: Frost());

// Or by hand: stroke space built once, painted with any effect at any
// moment.
final text = await StrokeText.of(WrittenText('Hello', fontSize: 96));
CustomPaint(painter: StrokeFxPainter(text: text, effect: Neon(), time: clock));

// Your own effect: a shader that #includes stroke_space.glsl.
class Chalk extends StrokeEffect {
  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final mesh = text.mesh(halo(text.writing.xHeight), scale);
    final sh = shader('chalk');
    mesh.setUniforms(sh, now); // then the effect's own floats
    draw(canvas, mesh.vertices, sh);
  }
}
```

```glsl
#include "stroke_space.glsl"
void main() {
  Stroke st = strokeAt(FlutterFragCoord().xy);
  float age = uPen.x - st.t;                  // since the pen passed here
  float ink = cover(st.wdist, st.halfWidth);  // the ink written so far
  ...
}
```

- **Joints:** `text.joints` (position, time, kind, strokes, angle), drawn with `text.jointMesh(radius, scale)` and a shader that includes `joint_space.glsl`.
- **Strokes:** `text.at(i, along)`, `timeAt`, `alongAt` and `jointsAlong` place things on them.
- **Shader includes:** impellerc only searches a shader's own folder and Flutter's shader library. An app's own shader can't `#include` a package's GLSL, so custom effects copy `stroke_space.glsl` (and `noise.glsl`) next to their shader, and add their program with `StrokeShaders.register`.

## Writing as it's typed

`WrittenText(..., typing: true, typedAt: [...])` lays text out so that typing more leaves what's written exactly as it was (`test/typing_test.dart`):
- Each character's wobble comes from its own place in the text.
- The pen starts at x = 0.
- A dot or bar is written straight after its letter.
- Each character is written no sooner than it was typed.

In Arabic, the last letter typed changes to its joined form when another follows, as it does in any Arabic text field.

The demo's text box uses this on a clock that runs on: letters are written as they're typed, and what's written goes on ageing. The effects seed their scattered details (blossoms, dew drops, vines, leaves) by stroke and by joint, not from one sequence, so typing a letter doesn't reshuffle what's already drawn.

## Proposed for fountain_pen

`lib/src/written.dart` (`WrittenText`) is a line-for-line port of `PenWriting`'s layout. `test/written_test.dart` checks that the pen is in the same place at every moment. It exists only because fountain_pen keeps each laid-out stroke private. The proposal:

```dart
/// One stroke of a PenWriting, as laid out and timed.
class PenStrokeLayout {
  List<Offset> get points;      // centre line (px, round the centre paint() uses)
  List<double> get halfWidths;  // the ink's half-width at each point (px)
  List<double> get times;       // when the pen gets to each point (s)
  int get index, line, character; // writing order; line; character in the line
  bool get dot, late;           // a dot; written once its word was done
  bool get lands;               // the pen came down for it (false: carried on)
  bool get joined;              // joined from the letter before (Arabic)
  Color get ink;
}

extension on PenWriting {
  List<PenStrokeLayout> get strokes; // in writing order
}
```

These are the `_Stroke` fields with absolute times, plus the `late`, `joined`, `line` and `character` that `_layout` already knows. With them, `written.dart` goes and `StrokeText.of` takes a `PenWriting`.

For writing as it's typed, fountain_pen would also want the typing layout (above) as an option: say `PenWriting(text, typing: true, typedAt: ...)`, and where each line's pen ends.

## Limits and next steps

- **Index limit:** one mesh holds at most 65k vertices (16-bit indices), about a paragraph. Longer text needs the mesh split.
- **Halo vs. grid:** a big halo widens every cell in the grid. Bloom is better done with a blur (as Neon does) than a wide halo.
- **Tests:** the joint finder is tuned by eye on three samples. It needs ground truth to be scored, like the paper's KanjiVG evaluation.
- **Web:** noise-heavy shaders (Ember) want a cheaper path. Lower octaves or a cached noise texture would do it.
- **Upstream Impeller:** flutter/flutter#153045 proposes dropping Impeller's render-to-texture for `drawVertices`. If it lands, texture coordinates mean the same thing, so this keeps working; only the cost changes.
