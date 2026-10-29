import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'joints.dart';
import 'space.dart';

/// The fragment programs the effects use, loaded once ([load]) before any
/// effect paints.
class StrokeShaders {
  StrokeShaders._();

  static const all = [
    'ink', 'neon', 'ember', 'bleed', 'ribbon', 'metal', 'weld', 'thread', 'star', //
    'frost', 'snowflake', 'silk', 'bark', 'sprites', 'jelly', 'snow',
  ];
  static final _programs = <String, ui.FragmentProgram>{};

  /// Loads the programs (all of them, unless [names] says which).
  static Future<void> load([Iterable<String> names = all]) => Future.wait([
        for (final n in names)
          if (!_programs.containsKey(n))
            ui.FragmentProgram.fromAsset('packages/stroke_fx/shaders/$n.frag')
                // (Run from this package itself, its assets have no prefix.)
                .catchError((Object _) => ui.FragmentProgram.fromAsset('shaders/$n.frag'))
                .then((p) => _programs[n] = p),
      ]);

  static ui.FragmentProgram of(String name) =>
      _programs[name] ?? (throw StateError('StrokeShaders.load() hasn\'t loaded "$name"'));

  /// Adds your own [program] as [name], for your effects' [StrokeEffect.shader]
  /// (a shader that includes a copy of stroke_space.glsl).
  static void register(String name, ui.FragmentProgram program) => _programs[name] = program;
}

/// A look for written text, painted moment by moment: its strokes in stroke
/// space, and for some its joints.
abstract class StrokeEffect {
  StrokeEffect();

  /// Its name, for a picker.
  String get name;

  /// What it paints on to.
  Color get background;

  /// Room round the ink the strokes' mesh needs (px), for text whose
  /// x-height is [xHeight] px: as far as the effect reaches past the ink.
  double halo(double xHeight);

  /// Anything it wants behind the text (a night sky's stars), in [area].
  void paintBackdrop(Canvas canvas, Rect area) {}

  /// Paints [text] as it is [now] s into its writing, [scale] texels to the
  /// px (the scale it's painted at times the device's pixel ratio).
  void paint(Canvas canvas, StrokeText text, double now, double scale);

  final _shaders = <String, ui.FragmentShader>{};

  /// This effect's own shader from the program [name] (one per [slot], for
  /// drawing the same program twice a frame).
  ui.FragmentShader shader(String name, [int slot = 0]) =>
      _shaders['$name/$slot'] ??= StrokeShaders.of(name).fragmentShader();

  /// Draws [vertices] filled by [shader].
  void draw(Canvas canvas, ui.Vertices vertices, ui.FragmentShader shader, {BlendMode blendMode = BlendMode.srcOver}) {
    canvas.drawVertices(vertices, BlendMode.src, Paint()
      ..shader = shader
      ..blendMode = blendMode);
  }

  void dispose() {
    for (final s in _shaders.values) {
      s.dispose();
    }
    _shaders.clear();
  }
}

/// Sets floats [values] on [shader] from [at]; returns where it got to.
int _set(ui.FragmentShader shader, int at, List<double> values) {
  for (final v in values) {
    shader.setFloat(at++, v);
  }
  return at;
}

List<double> _rgb(Color c, [double w = 0]) => [c.r, c.g, c.b, w];

/// A seed for things grown from joint [j] that stays the same while more
/// text is typed (its strokes and place don't change).
int _seedOf(Joint j) =>
    j.a * 100003 + j.b * 1009 + j.kind.index * 7 + j.position.dx.round() * 31 + j.position.dy.round();

/// No effect: the ink as fountain_pen draws it, through the same mesh (the
/// control, to compare with).
class PlainInk extends StrokeEffect {
  PlainInk({this.color = const Color(0xFF16204A)});

  final Color color;

  @override
  String get name => 'Plain ink';

  @override
  Color get background => const Color(0xFFF7F3EA);

  @override
  double halo(double xHeight) => 1.5;

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final mesh = text.mesh(halo(text.writing.xHeight), scale);
    final sh = shader('ink');
    _set(sh, mesh.setUniforms(sh, now), _rgb(color, 1));
    draw(canvas, mesh.vertices, sh);
  }
}

/// Neon: each stroke a glass tube that lights as the pen reaches it,
/// flickering as it strikes, with light running along it the way it was
/// written.
class Neon extends StrokeEffect {
  Neon({this.colorA = const Color(0xFFFF3D8B), this.colorB = const Color(0xFF39D4FF)});

  /// The two colours, letter and letter about.
  final Color colorA, colorB;

  @override
  String get name => 'Neon';

  @override
  Color get background => const Color(0xFF0B0A12);

  @override
  double halo(double xHeight) => xHeight * 0.22;

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    List<double> uniforms(double bloom) => [
          ..._rgb(colorA, xh * 3.2),
          ..._rgb(colorB, xh * 1.7),
          xh * 0.05 + 0.8, xh * 0.06, bloom, 0,
        ];
    // A bloom: the lit tubes again, blurred, added on.
    final bloom = shader('neon', 1);
    _set(bloom, mesh.setUniforms(bloom, now), uniforms(1));
    canvas.saveLayer(text.writing.bounds.inflate(halo(xh) + xh * 0.5), Paint()
      ..imageFilter = ui.ImageFilter.blur(sigmaX: xh * 0.16, sigmaY: xh * 0.16, tileMode: TileMode.decal)
      ..blendMode = BlendMode.plus);
    draw(canvas, mesh.vertices, bloom);
    canvas.restore();
    final sh = shader('neon');
    _set(sh, mesh.setUniforms(sh, now), uniforms(0));
    draw(canvas, mesh.vertices, sh);
  }
}

/// Ember: the pen lays molten metal that runs along the stroke the way it
/// was written and cools, white to red to cracked charcoal.
class Ember extends StrokeEffect {
  Ember({this.cooling = 2.2});

  /// How long it stays hot (s).
  final double cooling;

  @override
  String get name => 'Ember';

  @override
  Color get background => const Color(0xFF0C0806);

  @override
  double halo(double xHeight) => xHeight * 0.24;

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final sh = shader('ember');
    _set(sh, mesh.setUniforms(sh, now), [cooling, xh * 1.3, xh * 0.16, xh * 0.07]);
    draw(canvas, mesh.vertices, sh);
  }
}

/// Ink bleed: wet ink spreads into the paper as it dries, furthest where the
/// pen went slowly or came down, gathering at the edge it dries to.
class InkBleed extends StrokeEffect {
  InkBleed({this.color = const Color(0xFF14204F), this.wet = 1.4});

  final Color color;

  /// How long it stays wet (s).
  final double wet;

  @override
  String get name => 'Ink bleed';

  @override
  Color get background => const Color(0xFFF3EDE0);

  @override
  double halo(double xHeight) => xHeight * 0.2;

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final sh = shader('bleed');
    _set(sh, mesh.setUniforms(sh, now), [..._rgb(color, wet), 1.1, xh * 0.06, text.meanSpeed, 0.55]);
    draw(canvas, mesh.vertices, sh);
  }
}

/// Ribbon: each stroke a ribbon twisting as it goes, two-faced, and waving
/// from where it starts (the mesh bent each frame).
class Ribbon extends StrokeEffect {
  Ribbon({this.front = const Color(0xFFFF6B6B), this.back = const Color(0xFFFFC94D)});

  final Color front, back;

  @override
  String get name => 'Ribbon';

  @override
  Color get background => const Color(0xFF181430);

  @override
  double halo(double xHeight) => xHeight * 0.12;

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final amp = xh * 0.07, k = 2 * math.pi / (xh * 2.2);
    final bent = mesh.bent((centre, along, stroke, normal) {
      final pinned = (along / (xh * 0.9)).clamp(0.0, 1.0);
      return normal * (amp * pinned * pinned * math.sin(along * k - now * 3.1 + stroke * 1.3));
    });
    final sh = shader('ribbon');
    _set(sh, mesh.setUniforms(sh, now), [
      xh * 0.085, 2 * math.pi / (xh * 3.4), 2.0, 1.3, //
      ..._rgb(front), ..._rgb(back),
    ]);
    draw(canvas, bent, sh);
    bent.dispose();
  }
}

/// Weld: each stroke a bead of steel laid white-hot and cooling; each joint,
/// as the pen gets to it, a flash and a shower of sparks, then a bead that
/// cools with temper colours round it.
class Weld extends StrokeEffect {
  @override
  String get name => 'Weld';

  @override
  Color get background => const Color(0xFF111316);

  @override
  double halo(double xHeight) => xHeight * 0.13;

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final metal = shader('metal');
    _set(metal, mesh.setUniforms(metal, now), [0.9, xh * 0.05, 0, 0]);
    draw(canvas, mesh.vertices, metal);
    final joints = text.jointMesh(xh * 0.6, scale);
    final weld = shader('weld');
    _set(weld, joints.setUniforms(weld, now), [0.22, 1.8, 0.9, 1.0]);
    draw(canvas, joints.vertices, weld);
    sparks(canvas, text, now, xh);
  }

  /// Sparks thrown from each joint as it forms, as streaks, added on.
  static void sparks(Canvas canvas, StrokeText text, double now, double xh) {
    final pos = <double>[], colours = <int>[];
    for (final (k, j) in text.joints.indexed) {
      final tau = now - j.time;
      if (tau < 0 || tau > 1.2) continue;
      final r = math.Random(k * 7919 + 17);
      final n = 16 + r.nextInt(12);
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + (r.nextDouble() * 2 - 1) * math.pi * 0.8;
        final speed = xh * (2.5 + r.nextDouble() * 7);
        final life = 0.25 + r.nextDouble() * 0.75, delay = r.nextDouble() * 0.06;
        final t = tau - delay;
        if (t <= 0 || t > life) continue;
        final v = Offset(math.cos(angle), math.sin(angle)) * speed;
        Offset at(double t) => j.position + v * t + Offset(0, 0.5 * xh * 26 * t * t);
        final head = at(t), tail = at(math.max(0, t - 0.04));
        final d = head - tail;
        if (d.distance < 1e-3) continue;
        final fade = 1 - t / life;
        final side = Offset(-d.dy, d.dx) / d.distance * (0.5 + xh * 0.012) * (0.6 + 0.4 * fade);
        final hot = Color.lerp(const Color(0xFFFF7A1A), const Color(0xFFFFF6D8), fade)!;
        final headC = hot.withValues(alpha: fade).toARGB32(), tailC = hot.withValues(alpha: 0).toARGB32();
        final q = [tail - side, tail + side, head - side, head + side];
        for (final v in [0, 1, 2, 1, 3, 2]) {
          pos.addAll([q[v].dx, q[v].dy]);
          colours.add(v < 2 ? tailC : headC);
        }
      }
    }
    if (pos.isEmpty) return;
    final sparks = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(pos),
        colors: Int32List.fromList(colours));
    canvas.drawVertices(sparks, BlendMode.dst, Paint()..blendMode = BlendMode.plus);
    sparks.dispose();
  }
}

/// Constellation: strokes drawn as fine threads of light; each joint a star
/// that lights as the pen gets to it (a ripple running out), then twinkles.
/// Joins gold, touches blue, crossings pink.
class Constellation extends StrokeEffect {
  @override
  String get name => 'Constellation';

  @override
  Color get background => const Color(0xFF060A18);

  @override
  double halo(double xHeight) => xHeight * 0.1;

  final _sky = <(Offset, double)>[];

  @override
  void paintBackdrop(Canvas canvas, Rect area) {
    if (_sky.isEmpty) {
      final r = math.Random(3);
      for (var i = 0; i < 140; i++) {
        _sky.add((Offset(r.nextDouble(), r.nextDouble()), r.nextDouble()));
      }
    }
    for (final (p, b) in _sky) {
      canvas.drawCircle(Offset(area.left + p.dx * area.width, area.top + p.dy * area.height), 0.5 + b * 0.9,
          Paint()..color = const Color(0xFFBFD4FF).withValues(alpha: 0.12 + 0.3 * b * b));
    }
  }

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final thread = shader('thread');
    _set(thread, mesh.setUniforms(thread, now), [0.45 + xh * 0.012, 0.5, 0, 0, ..._rgb(const Color(0xFF9DB8FF))]);
    draw(canvas, mesh.vertices, thread);
    final joints = text.jointMesh(xh * 0.7, scale);
    final star = shader('star');
    _set(star, joints.setUniforms(star, now), [
      xh * 1.4, 1.1, 1.25, 0.55, //
      ..._rgb(join), ..._rgb(touch), ..._rgb(cross),
    ]);
    draw(canvas, joints.vertices, star);
    // Each star's ripples, as it lights: two soft rings running out, fading.
    final rings = _Rings();
    for (final j in text.joints) {
      final colour = switch (j.kind) { JointKind.join => join, JointKind.touch => touch, JointKind.cross => cross };
      for (final (delay, strength) in const [(0.0, 0.85), (0.14, 0.45)]) {
        final tau = now - j.time - delay;
        if (tau <= 0 || tau >= 1.1) continue;
        final left = 1 - tau / 1.1;
        rings.add(j.position, xh * (0.05 + 1.4 * tau), xh * 0.03 * (0.6 + left), colour.withValues(alpha: strength * left * left));
      }
    }
    rings.draw(canvas);
  }

  static const join = Color(0xFFFFD27A), touch = Color(0xFF8FD8FF), cross = Color(0xFFFF8FCB);
}

/// Soft rings: a band each, brightest along its middle, fading to nothing
/// either side, added on (light).
class _Rings {
  final _pos = <double>[], _col = <int>[];

  void add(Offset c, double radius, double width, Color colour) {
    const n = 72;
    final clear = colour.withValues(alpha: 0).toARGB32(), lit = colour.toARGB32();
    Offset at(int k, double r) => c + Offset(math.cos(k * 2 * math.pi / n), math.sin(k * 2 * math.pi / n)) * r;
    for (var k = 0; k < n; k++) {
      for (final (r0, r1) in [(radius - width, radius), (radius + width, radius)]) {
        final a0 = at(k, math.max(r0, 0)), a1 = at(k + 1, math.max(r0, 0)), b0 = at(k, r1), b1 = at(k + 1, r1);
        for (final (q, colourOf) in [(a0, clear), (b0, lit), (a1, clear), (b0, lit), (b1, lit), (a1, clear)]) {
          _pos.addAll([q.dx, q.dy]);
          _col.add(colourOf);
        }
      }
    }
  }

  void draw(Canvas canvas) {
    if (_pos.isEmpty) return;
    final v = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(_pos), colors: Int32List.fromList(_col));
    canvas.drawVertices(v, BlendMode.dst, Paint()..blendMode = BlendMode.plus);
    v.dispose();
  }
}

/// Copies of one shared cell (sprites.frag draws one thing in a square of
/// [cell] texels), each placed, sized, turned and tinted, drawn at once: on
/// Impeller the shader fills just that one small square a frame.
class Sprites {
  static const cell = 128.0;
  final _pos = <double>[], _tex = <double>[], _col = <int>[];

  /// One more, centred on [c], [size] px from its middle to its edge (times
  /// [aspect] across), turned by [angle], tinted [tint].
  void add(Offset c, double size, double angle, Color tint, {double aspect = 1}) {
    final ca = math.cos(angle), sa = math.sin(angle);
    Offset corner(double x, double y) => c + Offset(x * ca - y * sa, x * sa + y * ca);
    final w = size * aspect;
    final q = [corner(-w, -size), corner(w, -size), corner(-w, size), corner(w, size)];
    const uv = [Offset.zero, Offset(cell, 0), Offset(0, cell), Offset(cell, cell)];
    final argb = tint.toARGB32();
    for (final i in const [0, 1, 2, 1, 3, 2]) {
      _pos.addAll([q[i].dx, q[i].dy]);
      _tex.addAll([uv[i].dx, uv[i].dy]);
      _col.add(argb);
    }
  }

  bool get isEmpty => _pos.isEmpty;

  /// Draws them all with [shader] (its colour times each one's tint), laid
  /// on by [blendMode] (plus: light added).
  void draw(Canvas canvas, ui.FragmentShader shader, {BlendMode blendMode = BlendMode.srcOver}) {
    if (_pos.isEmpty) return;
    final v = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(_pos),
        textureCoordinates: Float32List.fromList(_tex), colors: Int32List.fromList(_col));
    canvas.drawVertices(v, BlendMode.modulate, Paint()
      ..shader = shader
      ..blendMode = blendMode);
    v.dispose();
  }
}

/// [shader] set to draw sprites of [kind] (see sprites.frag).
ui.FragmentShader _sprites(ui.FragmentShader shader, double kind, [double open = 1]) {
  _set(shader, 0, [Sprites.cell, kind, open, 0]);
  return shader;
}

/// Ivy: as the pen writes, a vine climbs each stroke just behind it,
/// twining round it (now in front, now behind, as a helix seen from the
/// side), opening ivy leaves as it goes and putting out tendrils that reach
/// and then coil, tighter as they age. More leaves gather where strokes
/// meet.
class Ivy extends StrokeEffect {
  @override
  String get name => 'Ivy';

  @override
  Color get background => const Color(0xFFEFEDE3);

  @override
  double halo(double xHeight) => xHeight * 0.06 + 1.5;

  /// How long the vine trails the pen (s).
  static const lag = 0.25;

  final _vines = Expando<List<_Vine>>();

  List<_Vine> _grow(StrokeText text) => _vines[text] ??= () {
        final xh = text.writing.xHeight, out = <_Vine>[];
        for (var i = 0; i < text.strokes.length; i++) {
          final len = text.lengthOf(i), r = math.Random(i * 7919 + 29);
          if (text.strokes[i].dot || len < xh * 0.25) continue;
          // (Round the stroke and back once every so far: a twining vine.)
          final wave = xh * (0.42 + 0.14 * r.nextDouble()), phase = r.nextDouble() * 6.28, reach = xh * 0.075;
          final pts = <Offset>[], front = <bool>[];
          for (var s = 0.0; s < len + 2; s += 2) {
            final (p, dir) = text.at(i, math.min(s, len));
            final th = 2 * math.pi * s / wave + phase;
            pts.add(p + Offset(-dir.dy, dir.dx) * (reach * math.sin(th)));
            front.add(math.cos(th) > 0);
          }
          final leaves = <({double at, double side, double size, Color tint})>[];
          for (var s = xh * 0.2 * r.nextDouble(); s < len; s += xh * (0.2 + 0.14 * r.nextDouble())) {
            if (r.nextDouble() > 0.72) continue;
            final th = 2 * math.pi * s / wave + phase;
            final g = r.nextDouble();
            leaves.add((
              at: s,
              side: math.sin(th) >= 0 ? 1.0 : -1.0,
              size: xh * (0.1 + 0.07 * r.nextDouble()),
              tint: Color.fromARGB(255, (205 + 50 * g).round(), 255, (205 + 50 * (1 - g)).round()),
            ));
          }
          final tendrils = <({double at, double side, double length})>[];
          for (var s = xh * (0.3 + 0.5 * r.nextDouble()); s < len; s += xh * (0.6 + 0.5 * r.nextDouble())) {
            if (r.nextDouble() > 0.6) continue;
            tendrils.add((at: s, side: r.nextBool() ? 1.0 : -1.0, length: xh * (0.45 + 0.25 * r.nextDouble())));
          }
          out.add(_Vine(i, pts, front, leaves, tendrils));
        }
        return out;
      }();

  /// Leaves where strokes meet: (where, which way, how big, its tint).
  final _knots = Expando<List<({Offset at, double angle, double size, double born, Color tint})>>();

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    const edge = Color(0xFF2E4A1E), core = Color(0xFF5E8A3A);
    final behind = _Tubes(), before = _Tubes(), curls = _Tubes();
    final leaves = Sprites();
    for (final (n, vine) in _grow(text).indexed) {
      final grown = text.alongAt(vine.stroke, now - lag);
      if (grown <= 0) continue;
      final width = 0.6 + xh * 0.016;
      // The vine as far as it's grown, tapering at its tip; each stretch
      // behind the stroke or in front of it.
      final last = math.min(vine.points.length - 1, (grown / 2).floor() + 1);
      for (var k = 0; k < last; k++) {
        final tipWidth = width * math.min(1.0, (grown - k * 2) / (xh * 0.12) + 0.2);
        (vine.front[k] ? before : behind).segment(vine.points[k], vine.points[k + 1], tipWidth, tipWidth, edge, core);
      }
      for (final (k, leaf) in vine.leaves.indexed) {
        final tau = now - lag - text.timeAt(vine.stroke, leaf.at);
        if (tau <= 0) continue;
        final x = math.min(1.0, tau / 0.5);
        final open = 1 + 2.2 * math.pow(x - 1, 3) + 1.2 * math.pow(x - 1, 2);
        final (p, dir) = text.at(vine.stroke, leaf.at);
        final base = vine.points[math.min((leaf.at / 2).round(), vine.points.length - 1)];
        final out = Offset(-dir.dy, dir.dx) * leaf.side;
        final a = math.atan2(out.dy, out.dx) + leaf.side * -0.5 + 0.07 * math.sin(now * 1.5 + n + k);
        final tip = Offset(math.cos(a), math.sin(a)), size = leaf.size * open;
        leaves.add(base + tip * size * 0.92, size, math.atan2(tip.dx, -tip.dy), leaf.tint, aspect: 0.95);
      }
      // Tendrils: out and up, then coiling, tighter as they age.
      for (final t in vine.tendrils) {
        final tau = now - lag - 0.2 - text.timeAt(vine.stroke, t.at);
        if (tau <= 0) continue;
        final reach = math.min(1.0, tau / 0.6), coil = math.min(1.0, tau / 2.0);
        final (_, dir) = text.at(vine.stroke, t.at);
        var p = vine.points[math.min((t.at / 2).round(), vine.points.length - 1)];
        var a = math.atan2(dir.dy, dir.dx) + t.side * 1.0;
        const m = 36;
        final step = t.length * reach / m;
        for (var j = 0; j < m; j++) {
          final u = j / m;
          a += t.side * step * (0.6 + 45 * coil * _smooth(0.3, 1.0, u)) / xh;
          final q = p + Offset(math.cos(a), math.sin(a)) * step;
          curls.segment(p, q, 0.5 + xh * 0.007 * (1 - u), 0.5 + xh * 0.007 * (1 - u - 1 / m), edge, core);
          p = q;
        }
      }
    }
    // Where strokes meet, a few more leaves, as the pen gets there.
    final knots = _knots[text] ??= () {
      return [
        for (final j in text.joints)
          for (final r in [math.Random(_seedOf(j) + 41)])
          if (r.nextDouble() < 0.55)
            for (var k = 0; k < 1 + r.nextInt(2); k++)
              (
                at: j.position,
                angle: -math.pi / 2 + (r.nextDouble() - 0.5) * 2.4,
                size: xh * (0.11 + 0.06 * r.nextDouble()),
                born: j.time + lag + 0.15 * k,
                tint: Color.fromARGB(255, 225 + r.nextInt(30), 255, 215 + r.nextInt(40)),
              ),
      ];
    }();
    for (final (k, knot) in knots.indexed) {
      final tau = now - knot.born;
      if (tau <= 0) continue;
      final x = math.min(1.0, tau / 0.5);
      final open = 1 + 2.2 * math.pow(x - 1, 3) + 1.2 * math.pow(x - 1, 2);
      final a = knot.angle + 0.07 * math.sin(now * 1.4 + k);
      final tip = Offset(math.cos(a), math.sin(a)), size = knot.size * open;
      leaves.add(knot.at + tip * size * 0.92, size, math.atan2(tip.dx, -tip.dy), knot.tint, aspect: 0.95);
    }
    behind.draw(canvas);
    final mesh = text.mesh(halo(xh), scale);
    final bark = shader('bark');
    _set(bark, mesh.setUniforms(bark, now), [1.15, 0.4, 0, 0]);
    draw(canvas, mesh.vertices, bark);
    before.draw(canvas);
    curls.draw(canvas);
    leaves.draw(canvas, _sprites(shader('sprites'), 5));
  }
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

class _Vine {
  _Vine(this.stroke, this.points, this.front, this.leaves, this.tendrils);

  final int stroke;

  /// Its centre line, a point every 2 px along the stroke, and whether each
  /// stretch is in front of the stroke.
  final List<Offset> points;
  final List<bool> front;
  final List<({double at, double side, double size, Color tint})> leaves;
  final List<({double at, double side, double length})> tendrils;
}

/// Tubes: segments as strips three vertices across, darker at their edges
/// than down their middle, drawn at once.
class _Tubes {
  final _pos = <double>[], _col = <int>[];

  void segment(Offset a, Offset b, double wa, double wb, Color edge, Color core) {
    final d = b - a;
    if (d.distance < 1e-6) return;
    final n = Offset(-d.dy, d.dx) / d.distance;
    final e = edge.toARGB32(), c = core.toARGB32();
    final la = a - n * wa, ra = a + n * wa, lb = b - n * wb, rb = b + n * wb;
    for (final (q, colour) in [(la, e), (a, c), (lb, e), (a, c), (b, c), (lb, e), (a, c), (ra, e), (b, c), (ra, e), (rb, e), (b, c)]) {
      _pos.addAll([q.dx, q.dy]);
      _col.add(colour);
    }
  }

  void draw(Canvas canvas) {
    if (_pos.isEmpty) return;
    final v = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(_pos), colors: Int32List.fromList(_col));
    canvas.drawVertices(v, BlendMode.dst, Paint());
    v.dispose();
  }
}

/// Jelly: the writing is soft. It lies on an elastic sheet, a grid of
/// masses tied to their neighbours by springs (the jiggle runs through
/// them), to their own places by weaker ones (the sheet comes back) and
/// slowed by damping. The pen drags the sheet where it touches it as it
/// writes; when it lifts at a stroke's end the sheet is let go and springs
/// back, wobbling, the wobble running out through the text and dying away.
class Jelly extends StrokeEffect {
  @override
  String get name => 'Jelly';

  @override
  Color get background => const Color(0xFFF3EFF8);

  @override
  double halo(double xHeight) => xHeight * 0.12 + 2;

  final _sheets = Expando<_Sheet>();
  _Sheet? _last;

  /// The sheet under [text], brought on to [now] (taking over the last
  /// text's sheet, so typing on doesn't still it).
  _Sheet _sheet(StrokeText text, double now) {
    final sheet = _sheets[text] ??= _Sheet(text, from: _last);
    _last = sheet;
    return sheet..advance(now);
  }

  /// How far the jelly has moved anywhere under [text] [now] s in (px), for
  /// tuning.
  double furthest(StrokeText text, double now) {
    final s = _sheet(text, now);
    var most = 0.0;
    for (var k = 0; k < s.u.length; k += 2) {
      most = math.max(most, math.sqrt(s.u[k] * s.u[k] + s.u[k + 1] * s.u[k + 1]));
    }
    return most;
  }

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final s = _sheet(text, now);
    final bent = mesh.bent((centre, along, stroke, normal) => s.at(centre));
    // A soft shadow under it, then the jelly.
    final shadow = shader('jelly', 1);
    _set(shadow, mesh.setUniforms(shadow, now), [1.2, 0.92, 1, 0]);
    canvas
      ..save()
      ..translate(xh * 0.03, xh * 0.06);
    draw(canvas, bent, shadow);
    canvas.restore();
    final jelly = shader('jelly');
    _set(jelly, mesh.setUniforms(jelly, now), [1.2, 0.92, 0, 0]);
    draw(canvas, bent, jelly);
    bent.dispose();
  }
}

/// The elastic sheet under a text: masses on a grid a third of an x-height
/// apart, stepped 240 times a second.
class _Sheet {
  _Sheet(this.text, {_Sheet? from}) {
    final xh = text.writing.xHeight;
    spacing = xh * 0.3;
    final area = text.writing.bounds.inflate(xh * 0.8);
    origin = area.topLeft;
    columns = (area.width / spacing).ceil() + 1;
    rows = (area.height / spacing).ceil() + 1;
    u = Float64List(columns * rows * 2);
    v = Float64List(columns * rows * 2);
    // (Springs per unit mass: a wave runs through it at about four
    // x-heights a second; it comes back at under two wobbles a second.)
    neighbour = math.pow(xh * 4 / spacing, 2).toDouble();
    if (from != null) {
      for (var j = 0; j < rows; j++) {
        for (var i = 0; i < columns; i++) {
          final d = from.at(origin + Offset(i * spacing, j * spacing));
          u[(j * columns + i) * 2] = d.dx;
          u[(j * columns + i) * 2 + 1] = d.dy;
        }
      }
      time = from.time;
    }
  }

  final StrokeText text;
  late final double spacing, neighbour;
  late final Offset origin;
  late final int columns, rows;
  late final Float64List u, v;
  var time = double.nan;

  static const _dt = 1 / 240, _home = 128.0, _damping = 4.5, _drag = 2.6;

  /// On to [now]; started afresh if time went back or jumped on.
  void advance(double now) {
    if (time.isNaN || now < time - 0.01 || now - time > 1.0) {
      u.fillRange(0, u.length, 0);
      v.fillRange(0, v.length, 0);
      time = now;
      return;
    }
    while (time + _dt <= now) {
      _step(time);
      time += _dt;
    }
  }

  /// Where the pen is at [t] while it's writing (null when it's lifted).
  Offset? _pen(double t) {
    final tip = text.tip(t);
    return tip == null ? null : text.at(tip.$1, tip.$2).$1;
  }

  void _step(double t) {
    final xh = text.writing.xHeight;
    // The pen, and how fast it's going: it drags the sheet near it.
    final pen = _pen(t), before = _pen(t - 1 / 60);
    final penVelocity = pen != null && before != null ? (pen - before) * 60.0 : null;
    final sigma2 = 2 * math.pow(xh * 0.5, 2);
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < columns; i++) {
        final k = (j * columns + i) * 2;
        for (var c = 0; c < 2; c++) {
          final here = u[k + c];
          var pull = 0.0;
          if (i > 0) pull += u[k - 2 + c] - here;
          if (i < columns - 1) pull += u[k + 2 + c] - here;
          if (j > 0) pull += u[k - columns * 2 + c] - here;
          if (j < rows - 1) pull += u[k + columns * 2 + c] - here;
          var force = neighbour * pull - _home * here - _damping * v[k + c];
          if (penVelocity != null) {
            final p = origin + Offset(i * spacing, j * spacing) - pen!;
            final w = math.exp(-(p.dx * p.dx + p.dy * p.dy) / sigma2);
            if (w > 1e-3) force += _drag * w * ((c == 0 ? penVelocity.dx : penVelocity.dy) - v[k + c]);
          }
          v[k + c] += force * _dt;
        }
      }
    }
    for (var k = 0; k < u.length; k++) {
      u[k] += v[k] * _dt;
    }
  }

  /// How far the sheet has moved point [q] (between its four nearest masses).
  Offset at(Offset q) {
    final x = ((q.dx - origin.dx) / spacing).clamp(0.0, columns - 1.001);
    final y = ((q.dy - origin.dy) / spacing).clamp(0.0, rows - 1.001);
    final i = x.floor(), j = y.floor(), fx = x - i, fy = y - j;
    double get(int ii, int jj, int c) => u[(jj * columns + ii) * 2 + c];
    double mix(int c) =>
        (get(i, j, c) * (1 - fx) + get(i + 1, j, c) * fx) * (1 - fy) +
        (get(i, j + 1, c) * (1 - fx) + get(i + 1, j + 1, c) * fx) * fy;
    return Offset(mix(0), mix(1));
  }
}

/// Snow: snow falls on the writing and settles only where an edge faces up,
/// deepening the longer the ink has lain there; flakes drift down across it.
class Snow extends StrokeEffect {
  @override
  String get name => 'Snow';

  @override
  Color get background => const Color(0xFF8193A9);

  @override
  double halo(double xHeight) => xHeight * 0.16 + 2;

  @override
  void paintBackdrop(Canvas canvas, Rect area) {
    canvas.drawRect(area, Paint()
      ..shader = ui.Gradient.linear(area.topCenter, area.bottomCenter, const [Color(0xFF66788F), Color(0xFFC3CDD8)]));
  }

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final snow = shader('snow');
    _set(snow, mesh.setUniforms(snow, now), [xh * 0.12, 3.0, 0, 0]);
    draw(canvas, mesh.vertices, snow);
    // Flakes, drifting down through the whole view, swaying, some nearer.
    final view = canvas.getLocalClipBounds(), flakes = Sprites();
    final r = math.Random(23);
    for (var i = 0; i < 160; i++) {
      final x0 = r.nextDouble(), y0 = r.nextDouble(), near = r.nextDouble();
      final fall = (0.35 + 0.5 * near) * xh, sway = r.nextDouble() * 6.3;
      final y = (y0 * view.height + now * fall) % view.height;
      final x = (x0 * view.width + now * xh * 0.15 + math.sin(now * 0.9 + sway) * xh * 0.3) % view.width;
      flakes.add(view.topLeft + Offset(x, y), xh * (0.012 + 0.025 * near), 0,
          const Color(0xFFFFFFFF).withValues(alpha: 0.45 + 0.5 * near));
    }
    flakes.draw(canvas, _sprites(shader('sprites'), 6));
  }
}

/// Fireflies: the writing glows faintly, like moss in the dark, and
/// fireflies rise from the ink as the pen passes. Each blinks to its own
/// rhythm at first; nudged by the others (Kuramoto's coupled oscillators)
/// they fall into step, as real fireflies do, and blink together.
class Fireflies extends StrokeEffect {
  @override
  String get name => 'Fireflies';

  @override
  Color get background => const Color(0xFF040A08);

  @override
  double halo(double xHeight) => xHeight * 0.1 + 2;

  final _swarms = Expando<_Swarm>();

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final thread = shader('thread');
    _set(thread, mesh.setUniforms(thread, now), [0.5 + xh * 0.016, 0.42, 0, 0, ..._rgb(const Color(0xFF9EE37D))]);
    draw(canvas, mesh.vertices, thread);
    final swarm = (_swarms[text] ??= _Swarm(text))..advance(now);
    final halos = Sprites(), hearts = Sprites();
    for (final f in swarm.flies) {
      final tau = now - f.born;
      if (tau <= 0) continue;
      final rise = math.min(1.0, tau / 1.2);
      final t = now * f.pace;
      final at = f.home +
          Offset(math.sin(t * 1.3 + f.seed) * f.roam, -rise * xh * 0.6 + math.sin(t * 0.9 + f.seed * 2) * f.roam * 0.6);
      final flash = math.pow(math.max(0.0, math.cos(f.phase)), 10).toDouble();
      final glow = math.min(1.0, rise * 2) * (0.12 + 0.88 * flash);
      halos.add(at, xh * 0.45, 0, const Color(0xFFD7FF6B).withValues(alpha: 0.65 * glow));
      hearts.add(at, xh * 0.075, 0, const Color(0xFFF4FFB0).withValues(alpha: math.min(1.0, 0.3 + glow)));
    }
    halos.draw(canvas, _sprites(shader('sprites'), 6), blendMode: BlendMode.plus);
    hearts.draw(canvas, _sprites(shader('sprites', 1), 6), blendMode: BlendMode.plus);
  }
}

/// A swarm of fireflies over a text: where each lives, when it rises, and its
/// blinking phase, stepped (dphase/dt = its own pace plus the pull of the
/// others' phases, growing once the writing's done).
class _Swarm {
  _Swarm(this.text) {
    final xh = text.writing.xHeight, r = math.Random(71);
    for (var i = 0; i < text.strokes.length; i++) {
      if (text.strokes[i].dot) continue;
      for (var a = xh * 0.4 * r.nextDouble(); a < text.lengthOf(i); a += xh * 0.9) {
        if (r.nextDouble() > 0.7) continue;
        flies.add(_Fly(text.at(i, a).$1, text.timeAt(i, a), xh * (0.25 + 0.4 * r.nextDouble()), 0.6 + 0.6 * r.nextDouble(),
            r.nextDouble() * 6.3, 2 * math.pi * (0.75 + 0.3 * r.nextDouble())));
      }
    }
  }

  final StrokeText text;
  final flies = <_Fly>[];
  var time = double.nan;

  void advance(double now) {
    if (time.isNaN || now < time - 0.01 || now - time > 1.0) {
      for (final f in flies) {
        f.phase = f.seed * 7.3;
      }
      time = now;
      return;
    }
    const dt = 1 / 120;
    while (time + dt <= now) {
      // (The pull to keep in step grows once the writing's done.)
      final k = 0.4 + 2.2 * ((time - text.duration) / 4).clamp(0.0, 1.0);
      final alive = [for (final f in flies) if (time >= f.born) f];
      var sx = 0.0, sy = 0.0;
      for (final f in alive) {
        sx += math.cos(f.phase);
        sy += math.sin(f.phase);
      }
      for (final f in alive) {
        // (Kuramoto, with the mean field: K·R·sin(ψ − φ).)
        final pull = alive.isEmpty ? 0.0 : k * (sy * math.cos(f.phase) - sx * math.sin(f.phase)) / alive.length;
        f.phase += (f.rate + pull) * dt;
      }
      time += dt;
    }
  }
}

class _Fly {
  _Fly(this.home, this.born, this.roam, this.pace, this.seed, this.rate) : phase = seed * 7.3;

  final Offset home;
  final double born, roam, pace, seed, rate;
  double phase;
}

/// Frost: the ink freezes as it's written, water turning to ice, and frost
/// feathers grow from its edges once it has; where strokes meet, where ice
/// forms first, a six-armed crystal grows as the pen gets there.
class Frost extends StrokeEffect {
  @override
  String get name => 'Frost';

  @override
  Color get background => const Color(0xFF0A1322);

  @override
  double halo(double xHeight) => xHeight * 0.17;

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final frost = shader('frost');
    _set(frost, mesh.setUniforms(frost, now), [0.6, xh * 0.13, xh * 0.2, 1.3]);
    draw(canvas, mesh.vertices, frost);
    final joints = text.jointMesh(xh * 0.42, scale);
    final flake = shader('snowflake');
    _set(flake, joints.setUniforms(flake, now), [0.45, 0.7, 0.35 + xh * 0.005, 0.22]);
    draw(canvas, joints.vertices, flake);
  }
}

/// Dew: each stroke a thread of spider silk. Once written it sags between
/// its anchors (its ends and its joints, where it's pinned), settling with a
/// bounce, and sways in a breeze; dew gathers on it, drops sliding down
/// towards where it hangs lowest, the biggest at the joints.
class Dew extends StrokeEffect {
  @override
  String get name => 'Dew';

  @override
  Color get background => const Color(0xFF0E181B);

  @override
  double halo(double xHeight) => xHeight * 0.07 + 2;

  final _anchors = Expando<List<List<double>>>();
  final _drops = Expando<List<({int stroke, double along, double born, double size, bool joint})>>();

  /// Where stroke [i] is pinned: its ends and its joints (px along it).
  List<double> anchors(StrokeText text, int i) => (_anchors[text] ??= [
        for (var k = 0; k < text.strokes.length; k++)
          () {
            final len = text.lengthOf(k), out = <double>[0];
            for (final a in text.jointsAlong(k)) {
              if (a - out.last > text.writing.xHeight * 0.15 && len - a > text.writing.xHeight * 0.15) out.add(a);
            }
            return out..add(len);
          }(),
      ])[i];

  /// How far the point [along] px along stroke [i] has moved [now] s in:
  /// down by its sag (most mid-span, more on a level span), across by the
  /// breeze (more on an upright one).
  Offset shift(StrokeText text, int i, double along, double now) {
    final st = text.strokes[i];
    if (st.dot) return Offset.zero;
    final pins = anchors(text, i), a = along.clamp(0.0, pins.last);
    var k = 0;
    while (k < pins.length - 2 && pins[k + 1] < a) {
      k++;
    }
    final s0 = pins[k], s1 = pins[k + 1], span = s1 - s0;
    if (span <= 1e-6) return Offset.zero;
    final u = (a - s0) / span, bow = 4 * u * (1 - u);
    final chord = text.at(i, s1).$1 - text.at(i, s0).$1, length = math.max(chord.distance, 1e-6);
    final level = (chord.dx / length).abs(), upright = (chord.dy / length).abs();
    // (Let go once written: a spring that overshoots, then settles.)
    final tau = now - st.end;
    final release = tau <= 0 ? 0.0 : 1 - math.exp(-tau * 3.2) * math.cos(tau * 8.5);
    final xh = text.writing.xHeight;
    final sag = math.min(0.22 * span, 0.4 * xh) * bow * release * (0.3 + 0.7 * level);
    final sway = math.min(0.05 * span, 0.07 * xh) * bow * (0.4 + 0.6 * upright) *
        math.sin(now * 1.4 + i * 0.9 + s0 * 0.02) * release.clamp(0.0, 1.0);
    return Offset(sway, sag);
  }

  List<({int stroke, double along, double born, double size, bool joint})> drops(StrokeText text) =>
      _drops[text] ??= () {
        final xh = text.writing.xHeight;
        final out = <({int stroke, double along, double born, double size, bool joint})>[];
        for (var i = 0; i < text.strokes.length; i++) {
          if (text.strokes[i].dot) continue;
          final len = text.lengthOf(i), r = math.Random(i * 7919 + 11);
          for (var a = xh * 0.16 * r.nextDouble(); a < len; a += xh * 0.16 * (0.6 + 0.8 * r.nextDouble())) {
            final size = xh * (0.028 + 0.04 * math.pow(r.nextDouble(), 2));
            out.add((stroke: i, along: a, born: text.timeAt(i, a) + 0.5 + 1.4 * r.nextDouble(), size: size, joint: false));
          }
        }
        for (final j in text.joints) {
          final along = text.jointsAlong(j.a), r = math.Random(_seedOf(j) + 3);
          if (along.isEmpty) continue;
          final p = text.at(j.a, along.first).$1;
          var best = along.first;
          for (final a in along) {
            if ((text.at(j.a, a).$1 - j.position).distance < (p - j.position).distance) best = a;
          }
          out.add((stroke: j.a, along: best, born: j.time + 0.6, size: xh * (0.075 + 0.03 * r.nextDouble()), joint: true));
        }
        return out;
      }();

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final bent = mesh.bent((centre, along, stroke, normal) => shift(text, stroke, along, now));
    final silk = shader('silk');
    _set(silk, mesh.setUniforms(silk, now), [0.35 + xh * 0.008, 0.85, 0, 0]);
    draw(canvas, bent, silk);
    bent.dispose();
    final sprites = Sprites();
    for (final d in drops(text)) {
      final tau = now - d.born;
      if (tau < 0) continue;
      var along = d.along;
      if (!d.joint) {
        // (Sliding down to the middle of its span, where it hangs lowest:
        // the bigger, the sooner.)
        final pins = anchors(text, d.stroke);
        var k = 0;
        while (k < pins.length - 2 && pins[k + 1] < along) {
          k++;
        }
        final low = (pins[k] + pins[k + 1]) / 2;
        along += (low - along) * 0.6 * (1 - math.exp(-tau * d.size / xh * 1.6));
      }
      final grow = math.min(1.0, tau / 1.2);
      final size = d.size * (1 - (1 - grow) * (1 - grow));
      final p = text.at(d.stroke, along).$1 + shift(text, d.stroke, along, now) + Offset(0, size * 0.55);
      sprites.add(p, size, 0, const Color(0xFFFFFFFF));
    }
    sprites.draw(canvas, _sprites(shader('sprites'), 0));
  }
}

/// Sakura: each stroke a cherry branch, growing as the pen goes; blossoms
/// open where strokes meet and here and there along them, then shed petals
/// that fall, slowed by the air, fluttering in a breeze.
class Sakura extends StrokeEffect {
  @override
  String get name => 'Sakura';

  @override
  Color get background => const Color(0xFFF6EFEA);

  @override
  double halo(double xHeight) => xHeight * 0.08 + 1.5;

  final _blossoms = Expando<List<({Offset at, double born, double size, double angle, int seed})>>();

  List<({Offset at, double born, double size, double angle, int seed})> blossoms(StrokeText text) =>
      _blossoms[text] ??= () {
        final xh = text.writing.xHeight;
        final out = <({Offset at, double born, double size, double angle, int seed})>[
          for (final j in text.joints)
            () {
              final r = math.Random(_seedOf(j) + 5);
              return (
                at: j.position,
                born: j.time + 0.25 + 0.3 * r.nextDouble(),
                size: xh * (0.17 + 0.06 * r.nextDouble()),
                angle: r.nextDouble() * math.pi,
                seed: _seedOf(j),
              );
            }(),
        ];
        for (var i = 0; i < text.strokes.length; i++) {
          if (text.strokes[i].dot) continue;
          final len = text.lengthOf(i), r = math.Random(i * 7919 + 5);
          for (var a = xh * 0.3 * r.nextDouble(); a < len; a += xh * (0.4 + 0.3 * r.nextDouble())) {
            if (r.nextDouble() > 0.6) continue;
            final (p, dir) = text.at(i, a);
            final side = r.nextBool() ? 1.0 : -1.0;
            out.add((
              at: p + Offset(-dir.dy, dir.dx) * side * xh * 0.05,
              born: text.timeAt(i, a) + 0.4 + 0.6 * r.nextDouble(),
              size: xh * (0.1 + 0.05 * r.nextDouble()),
              angle: r.nextDouble() * math.pi,
              seed: i * 7919 + a.round(),
            ));
          }
        }
        return out;
      }();

  @override
  void paint(Canvas canvas, StrokeText text, double now, double scale) {
    final xh = text.writing.xHeight;
    final mesh = text.mesh(halo(xh), scale);
    final bark = shader('bark');
    _set(bark, mesh.setUniforms(bark, now), [1.35, 0.5, 0, 0]);
    draw(canvas, mesh.vertices, bark);
    final flowers = Sprites(), petals = Sprites();
    for (final (k, b) in blossoms(text).indexed) {
      final tau = now - b.born;
      if (tau < 0) continue;
      // Opening: past full, then settling.
      final x = math.min(1.0, tau / 0.7);
      final open = 1 + 2.2 * math.pow(x - 1, 3) + 1.2 * math.pow(x - 1, 2);
      flowers.add(b.at, b.size * open, b.angle + 0.06 * math.sin(now * 1.3 + k), const Color(0xFFFFFFFF));
      // Its petals: one every few seconds, falling as a petal does, its drag
      // keeping it slow, drifting and fluttering in the breeze.
      final r = math.Random(b.seed * 31 + 7), period = 2.0 + 2.5 * r.nextDouble(), first = 1.2 + 2.0 * r.nextDouble();
      for (var n = 0; n < 4; n++) {
        final t = tau - first - n * period;
        if (t < 0 || t > 4.5) continue;
        final phase = r.nextDouble() * 6.3, spin = (r.nextDouble() - 0.5) * 5;
        const drag = 0.45;
        final fall = xh * 0.85 * (t - drag * (1 - math.exp(-t / drag)));
        final drift = xh * 0.3 * t + xh * 0.18 * math.sin(t * 2.6 + phase);
        final fade = math.min(1.0, t / 0.2) * math.min(1.0, (4.5 - t) / 1.2);
        petals.add(b.at + Offset(drift, fall), xh * 0.07, spin * t + math.sin(t * 3 + phase),
            const Color(0xFFFFFFFF).withValues(alpha: fade), aspect: 0.75);
      }
    }
    flowers.draw(canvas, _sprites(shader('sprites'), 1));
    petals.draw(canvas, _sprites(shader('sprites', 1), 2));
  }
}
