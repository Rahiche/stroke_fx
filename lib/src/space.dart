import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'joints.dart';
import 'written.dart';

/// Written text in stroke space: its strokes and joints, and the images that
/// tell a shader about them. Build once with [StrokeText.of]; ask it for a
/// [mesh] at the size it's painted.
///
/// How a shader learns where it is: every stroke mesh vertex's texture
/// coordinates point into a grid of cells, a cell per stroke ([StrokeMesh]):
/// across a cell is along the stroke (px from its start, its round ends
/// either side), down it is across the stroke. The shader works out the
/// stroke from the cell and looks the rest up in [strokeData]: the stroke's
/// length, when the pen started and finished it and, at 60 points along it,
/// when the pen got there and how broad the ink is.
class StrokeText {
  StrokeText._(this.writing, this.joints, this.strokeData, this.jointData, this.halfMax, this.lengthMax);

  /// Lays out [writing]'s strokes, finds its joints and makes their images.
  static Future<StrokeText> of(WrittenText writing) async {
    final strokes = writing.strokes;
    final joints = findJoints(strokes, writing.xHeight);
    var halfMax = 0.0, lengthMax = 0.0;
    final lengths = <double>[];
    for (final s in strokes) {
      halfMax = math.max(halfMax, s.halfWidths.reduce(math.max));
      // (A dot is a disc where it starts, as fountain_pen draws it.)
      lengths.add(s.dot ? 0 : _length(s.points));
      lengthMax = math.max(lengthMax, lengths.last);
    }
    final duration = math.max(writing.duration, 1e-3);
    // The strokes' image: a row each.
    final w = _meta + 2 * _samples, h = math.max(strokes.length, 1);
    final px = Uint8List(w * h * 4);
    void put(int x, int y, double unit16, int b) {
      final v = (unit16.clamp(0.0, 1.0) * 65535).round(), at = (y * w + x) * 4;
      px[at] = v >> 8;
      px[at + 1] = v & 0xff;
      px[at + 2] = b.clamp(0, 255);
      px[at + 3] = 255;
    }

    for (final (i, s) in strokes.indexed) {
      final flags = (s.dot ? 1 : 0) | (s.late ? 2 : 0) | (s.lands ? 4 : 0) | (s.joined ? 8 : 0);
      put(0, i, lengths[i] * 8 / 65535, flags);
      put(1, i, s.start / duration, s.character);
      put(2, i, s.end / duration, s.line);
      put(3, i, strokes.length > 1 ? i / (strokes.length - 1) : 0, 0);
      // (When the pen got to, and how broad the ink is at, evenly spaced
      // points along it.)
      final run = _run(s.points);
      for (var j = 0, k = 0; j < _samples; j++) {
        final at = lengths[i] * j / (_samples - 1);
        while (k < run.length - 2 && run[k + 1] < at) {
          k++;
        }
        final seg = k + 1 < run.length ? run[k + 1] - run[k] : 0.0;
        final f = seg > 0 ? ((at - run[k]) / seg).clamp(0.0, 1.0) : 0.0;
        final k1 = math.min(k + 1, run.length - 1);
        final t = s.times[k] + (s.times[k1] - s.times[k]) * f;
        final half = s.halfWidths[k] + (s.halfWidths[k1] - s.halfWidths[k]) * f;
        put(_meta + j, i, t / duration, (half / math.max(halfMax, 1e-6) * 255).round());
        // (Which way it goes there, for effects lit from one side: a dot's
        // square lies along x.)
        final d = s.points[math.min(k1 + 1, s.points.length - 1)] - s.points[math.max(k - 1, 0)];
        final angle = s.dot || s.points.length < 2 ? 0.0 : math.atan2(d.dy, d.dx);
        put(_meta + _samples + j, i, (angle + math.pi) / (2 * math.pi), 0);
      }
    }
    // The joints' image: a texel each, in a row: when it forms, its kind,
    // and the angle its strokes meet at.
    final jw = math.max(joints.length, 1);
    final jpx = Uint8List(jw * 2 * 4);
    for (final (i, j) in joints.indexed) {
      final v = (j.time / duration).clamp(0.0, 1.0) * 65535;
      jpx[i * 4] = v.round() >> 8;
      jpx[i * 4 + 1] = v.round() & 0xff;
      jpx[i * 4 + 2] = j.kind.index;
      jpx[i * 4 + 3] = 255;
      final a = (jw + i) * 4;
      final angle = (j.angle / (math.pi / 2)).clamp(0.0, 1.0) * 65535;
      jpx[a] = angle.round() >> 8;
      jpx[a + 1] = angle.round() & 0xff;
      jpx[a + 2] = (j.size / math.max(halfMax * 2, 1e-6) * 255).round().clamp(0, 255);
      jpx[a + 3] = 255;
    }
    final images = await Future.wait([_image(px, w, h), _image(jpx, jw, 2)]);
    return StrokeText._(writing, joints, images[0], images[1], halfMax, lengthMax);
  }

  /// Points along each stroke's row of [strokeData] (when the pen got there
  /// and how broad, then which way it went), and the texels before them.
  static const _samples = 60, _meta = 4;

  final WrittenText writing;
  final List<Joint> joints;

  /// The strokes' image (a row each) and the joints' (a column each).
  final ui.Image strokeData, jointData;

  /// The broadest the ink gets, and the longest stroke (px).
  final double halfMax, lengthMax;

  List<WrittenStroke> get strokes => writing.strokes;
  double get duration => writing.duration;

  /// How fast the pen goes along its strokes, on average (px/s).
  late final double meanSpeed = () {
    var length = 0.0, time = 0.0;
    for (final s in strokes) {
      if (s.dot) continue;
      length += _length(s.points);
      time += s.end - s.start;
    }
    return time > 0 ? length / time : 1.0;
  }();

  final _meshes = <(double, double), StrokeMesh>{};

  /// The strokes as a mesh with [halo] px round the ink, its cells [scale]
  /// texels to the px (the scale it's painted at, times the device's pixel
  /// ratio: Impeller shades the cells as an image of that size).
  StrokeMesh mesh(double halo, double scale) {
    final key = (halo, (scale * 4).roundToDouble() / 4);
    return _meshes[key] ??= StrokeMesh._(this, halo, key.$2);
  }

  final _jointMeshes = <(double, double), JointMesh>{};

  /// The joints as squares [radius] px round each, [scale] texels to the px.
  JointMesh jointMesh(double radius, double scale) {
    final key = (radius, (scale * 4).roundToDouble() / 4);
    return _jointMeshes[key] ??= JointMesh._(this, radius, key.$2);
  }

  /// The point [along] px along stroke [i]'s centre line, and which way it
  /// goes there.
  (ui.Offset, ui.Offset) at(int i, double along) {
    final p = strokes[i].points;
    if (p.length < 2) return (p.first, const ui.Offset(1, 0));
    final run = _run(p), s = along.clamp(0.0, run.last);
    var lo = 0, hi = run.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (run[mid] <= s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = run[hi] - run[lo], d = p[hi] - p[lo];
    return (ui.Offset.lerp(p[lo], p[hi], seg > 0 ? (s - run[lo]) / seg : 0)!, d / math.max(d.distance, 1e-9));
  }

  /// When the pen passes [along] px along stroke [i] (s).
  double timeAt(int i, double along) {
    final st = strokes[i], run = _run(st.points);
    if (run.length < 2) return st.start;
    final s = along.clamp(0.0, run.last);
    var k = 0;
    while (k < run.length - 2 && run[k + 1] < s) {
      k++;
    }
    final seg = run[k + 1] - run[k];
    return st.times[k] + (st.times[k + 1] - st.times[k]) * (seg > 0 ? (s - run[k]) / seg : 0);
  }

  /// How far along stroke [i] the pen had got by [t] (px; 0 before it
  /// starts, its length once it's done).
  double alongAt(int i, double t) {
    final st = strokes[i], run = _run(st.points), times = st.times;
    if (run.length < 2 || t <= times.first) return 0;
    if (t >= times.last) return run.last;
    var lo = 0, hi = times.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = times[hi] - times[lo];
    return run[lo] + (run[hi] - run[lo]) * (span > 0 ? (t - times[lo]) / span : 0);
  }

  /// The length of stroke [i]'s centre line (px).
  double lengthOf(int i) => _run(strokes[i].points).last;

  /// How far along stroke [i] each joint on it is (px), in order.
  List<double> jointsAlong(int i) => _along[i] ??= () {
        final p = strokes[i].points, run = _run(p);
        final out = <double>[];
        for (final j in joints) {
          if (j.a != i && j.b != i) continue;
          var best = double.infinity, at = 0.0;
          for (var k = 0; k + 1 < p.length; k++) {
            final ab = p[k + 1] - p[k];
            final f = (((j.position - p[k]).dx * ab.dx + (j.position - p[k]).dy * ab.dy) /
                    math.max(ab.distanceSquared, 1e-9))
                .clamp(0.0, 1.0);
            final d = (p[k] + ab * f - j.position).distanceSquared;
            if (d < best) {
              best = d;
              at = run[k] + (run[k + 1] - run[k]) * f;
            }
          }
          out.add(at);
        }
        return out..sort();
      }();

  final _along = <int, List<double>>{};

  /// The stroke the pen is on at [t] (null between strokes) and how far
  /// along it the pen has got (px).
  (int, double)? tip(double t) {
    final strokes = this.strokes;
    var lo = 0, hi = strokes.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final s = strokes[mid];
      if (t < s.start) {
        hi = mid - 1;
      } else if (t >= s.end) {
        lo = mid + 1;
      } else {
        final times = s.times, run = _run(s.points);
        var k = 1;
        while (k < times.length && times[k] <= t) {
          k++;
        }
        if (k >= times.length) return (mid, run.last);
        final f = ((t - times[k - 1]) / math.max(times[k] - times[k - 1], 1e-9)).clamp(0.0, 1.0);
        return (mid, run[k - 1] + (run[k] - run[k - 1]) * f);
      }
    }
    return null;
  }

  void dispose() {
    strokeData.dispose();
    jointData.dispose();
  }
}

double _length(List<ui.Offset> p) {
  var l = 0.0;
  for (var i = 1; i < p.length; i++) {
    l += (p[i] - p[i - 1]).distance;
  }
  return l;
}

final _runs = Expando<List<double>>();

List<double> _run(List<ui.Offset> p) => _runs[p] ??= () {
      final run = [0.0];
      for (var i = 1; i < p.length; i++) {
        run.add(run.last + (p[i] - p[i - 1]).distance);
      }
      return run;
    }();

Future<ui.Image> _image(Uint8List px, int w, int h) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// The strokes as one mesh: a strip along each (a point every couple of px,
/// [halo] px either side of the ink, round ends), its texture coordinates in
/// a grid of cells, a cell per stroke (see [StrokeText]).
///
/// A strip can't turn a sharp corner without folding over itself, and a fold
/// shows: the shader's coordinates fan out across it in rays. So a stroke is
/// split into runs at its sharp corners, each with normals of its own, and a
/// round fan fills each corner's outside: there every point is at the corner
/// (the same distance along), only further out, which is what a round join
/// is. Round a tight bend the strip's inner edge would fold back on itself;
/// it's held where it would.
class StrokeMesh {
  StrokeMesh._(this.text, this.halo, this.scale) {
    final strokes = text.strokes;
    cap = text.halfMax + halo;
    cellWidth = ((text.lengthMax + 2 * cap) * scale + 2 * pad).ceilToDouble();
    cellHeight = (2 * cap * scale + 2 * pad).ceilToDouble();
    // (Rows of cells down, as many as fit in 4096 texels; then another column.)
    rows = math.max(1, math.min(strokes.length, (4096 / cellHeight).floor()));
    final pos = <double>[], tex = <double>[], centre = <double>[], bend = <double>[], strokeOf = <int>[];
    final idx = <int>[];
    final innerH = cellHeight - 2 * pad;
    for (final (i, s) in strokes.indexed) {
      final x0 = (i ~/ rows) * cellWidth + pad + cap * scale, y0 = (i % rows) * cellHeight + pad;
      // A vertex: on the centre line at [c] ([at] px along, its row bending
      // along [n]), moved out by [out]; [v] across the strip, -1 to 1.
      int vertex(ui.Offset c, ui.Offset out, ui.Offset n, double at, double v) {
        pos.addAll([c.dx + out.dx, c.dy + out.dy]);
        tex.addAll([x0 + at * scale, y0 + (v + 1) / 2 * innerH]);
        centre.addAll([c.dx, c.dy, at, out.dx, out.dy]);
        bend.addAll([n.dx, n.dy]);
        strokeOf.add(i);
        return pos.length ~/ 2 - 1;
      }

      if (s.dot || s.points.length < 2) {
        final p = s.points.first, m = s.halfWidths.first + halo;
        final q = [
          for (final (a, v) in [(-m, -1.0), (-m, 1.0), (m, -1.0), (m, 1.0)])
            vertex(p, ui.Offset(a, m * v), const ui.Offset(0, 1), a, v),
        ];
        idx.addAll([q[0], q[1], q[2], q[1], q[3], q[2]]);
        continue;
      }
      // A point every 2 px (and the last).
      final run = _run(s.points), keep = <int>[];
      for (var j = 0; j < s.points.length; j++) {
        if (j == 0 || j == s.points.length - 1 || run[j] - run[keep.last] >= 2) keep.add(j);
      }
      final pts = [for (final j in keep) s.points[j]];
      final at = [for (final j in keep) run[j]];
      final m = [for (final j in keep) s.halfWidths[j] + halo];
      final n = pts.length;
      ui.Offset unit(ui.Offset d) => d / math.max(d.distance, 1e-9);
      // (Each row bends along the normal of the line smoothed over a few px,
      // so a corner's runs and fan move together.)
      final w = math.max(1, (text.writing.xHeight * 0.15 / 2).round());
      final bends = [
        for (var j = 0; j < n; j++)
          () {
            final t = unit(pts[math.min(j + w, n - 1)] - pts[math.max(j - w, 0)]);
            return ui.Offset(-t.dy, t.dx);
          }(),
      ];
      // Sharp corners: where it turns more than 50 degrees over 2 points
      // either side, at the sharpest point.
      double turn(int j) {
        if (j < 2 || j > n - 3) return 0;
        final a = unit(pts[j] - pts[j - 2]), b = unit(pts[j + 2] - pts[j]);
        return math.acos((a.dx * b.dx + a.dy * b.dy).clamp(-1.0, 1.0));
      }

      final corners = <int>[];
      for (var j = 2; j < n - 2; j++) {
        final tj = turn(j);
        if (tj > 50 * math.pi / 180 && tj >= turn(j - 1) && tj > turn(j + 1)) {
          if (corners.isEmpty || j - corners.last >= 3) corners.add(j);
        }
      }
      // How far the strip may reach from point [j] towards [dir] (a unit
      // normal): as far as the points out there are still nearest to [j]
      // than to the rest of the line near it (within twice the reach along
      // it): inside a bend or a corner the strip stops at the line's middle,
      // where the other side takes over, so it never folds.
      double reach(int j, ui.Offset dir) {
        final c = pts[j], mm = m[j];
        var k0 = j, k1 = j;
        while (k0 > 0 && at[j] - at[k0 - 1] <= 2 * mm) {
          k0--;
        }
        while (k1 < n - 1 && at[k1 + 1] - at[j] <= 2 * mm) {
          k1++;
        }
        bool clear(double r) {
          final q = c + dir * r, limit = r * r * 0.97;
          for (var k = k0; k <= k1; k++) {
            if (k != j && (q - pts[k]).distanceSquared < limit) return false;
          }
          return true;
        }

        if (clear(mm)) return mm;
        var lo = 0.0, hi = mm;
        for (var it = 0; it < 8; it++) {
          final mid = (lo + hi) / 2;
          if (clear(mid)) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        return lo;
      }

      // At each corner: the way in and out, which side is outside (its v),
      // and how far in the inside reaches at a distance d from the corner
      // (d / tan(turn / 2): out to the line halving the corner).
      final cornerAt = <int, (ui.Offset, ui.Offset, double, double)>{};
      for (final c in corners) {
        final tIn = unit(pts[c] - pts[c - 1]), tOut = unit(pts[c + 1] - pts[c]);
        final nIn = ui.Offset(-tIn.dy, tIn.dx);
        final side = tOut.dx * nIn.dx + tOut.dy * nIn.dy > 0 ? -1.0 : 1.0;
        final turned = math.acos((tIn.dx * tOut.dx + tIn.dy * tOut.dy).clamp(-1.0, 1.0));
        cornerAt[c] = (tIn, tOut, side, 1 / math.tan(math.max(turned / 2, 1e-3)));
      }
      // Each run, from a corner (or the start) to the next (or the end).
      var from = 0;
      for (final to in [...corners, n - 1]) {
        final first = from == 0, last = to == n - 1;
        final rowIdx = <(int, int)>[];
        // A row: its centre, tangent, the strip's reach, how far along, its
        // bend normal, and how far each side reaches (v is the true distance
        // over the strip's reach, so the shader's "across" stays exact).
        void row(ui.Offset c, ui.Offset t, double mm, double a, ui.Offset b, double minus, double plus) {
          final nrm = ui.Offset(-t.dy, t.dx);
          rowIdx.add((vertex(c, nrm * -minus, b, a, -minus / mm), vertex(c, nrm * plus, b, a, plus / mm)));
        }

        final tangents = [
          for (var j = from; j <= to; j++) unit(pts[math.min(j + 1, to)] - pts[math.max(j - 1, from)]),
        ];
        if (first) {
          final t = tangents.first;
          row(pts[from] - t * m[from], t, m[from], at[from] - m[from], bends[from], m[from], m[from]);
        }
        for (var j = from; j <= to; j++) {
          final t = tangents[j - from];
          final nrm = ui.Offset(-t.dy, t.dx);
          row(pts[j], t, m[j], at[j], bends[j], reach(j, nrm * -1.0), reach(j, nrm));
        }
        if (last) {
          final t = tangents.last;
          row(pts[to] + t * m[to], t, m[to], at[to] + m[to], bends[to], m[to], m[to]);
        }
        for (var j = 0; j + 1 < rowIdx.length; j++) {
          final (l0, r0) = rowIdx[j];
          final (l1, r1) = rowIdx[j + 1];
          idx.addAll([l0, r0, l1, r0, r1, l1]);
        }
        if (!last) {
          // The corner's outside, filled with a fan round it: every point at
          // the corner, only further out (a round join).
          final (tIn, tOut, side, _) = cornerAt[to]!;
          final oA = ui.Offset(-tIn.dy, tIn.dx) * side, oB = ui.Offset(-tOut.dy, tOut.dx) * side;
          final aA = math.atan2(oA.dy, oA.dx);
          var delta = math.atan2(oB.dy, oB.dx) - aA;
          while (delta > math.pi) {
            delta -= 2 * math.pi;
          }
          while (delta <= -math.pi) {
            delta += 2 * math.pi;
          }
          // (Round the outside: past the corner, the way it was going.)
          final mid = aA + delta / 2;
          if (math.cos(mid) * tIn.dx + math.sin(mid) * tIn.dy < 0) delta -= 2 * math.pi * delta.sign;
          final steps = math.max(2, (delta.abs() / (math.pi / 12)).ceil());
          final c = pts[to], mm = m[to];
          final hub = vertex(c, ui.Offset.zero, bends[to], at[to], 0);
          var prev = -1;
          for (var k = 0; k <= steps; k++) {
            final a = aA + delta * k / steps;
            final e = vertex(c, ui.Offset(math.cos(a), math.sin(a)) * mm, bends[to], at[to], side);
            if (prev >= 0) idx.addAll([hub, prev, e]);
            prev = e;
          }
        }
        from = to;
      }
    }
    assert(pos.length ~/ 2 < 65536, 'Too many vertices for one mesh');
    positions = Float32List.fromList(pos);
    textureCoordinates = Float32List.fromList(tex);
    indices = Uint16List.fromList(idx);
    _centres = Float32List.fromList(centre);
    _bends = Float32List.fromList(bend);
    _strokeOf = Int32List.fromList(strokeOf);
    vertices = ui.Vertices.raw(ui.VertexMode.triangles, positions,
        textureCoordinates: textureCoordinates, indices: indices);
  }

  final StrokeText text;

  /// Room round the ink (px), and texels to the px.
  final double halo, scale;

  /// Texels of gutter round each cell, so neighbours don't bleed in.
  static const pad = 2.0;

  /// How far the round ends reach past a stroke's first and last points (px).
  late final double cap;

  /// Each cell's size (texels), and how many go down a column.
  late final double cellWidth, cellHeight;
  late final int rows;

  late final Float32List positions, textureCoordinates;
  late final Uint16List indices;
  late final ui.Vertices vertices;

  // Each vertex's point on the centre line, how far along, and how far out
  // from it; the normal its row bends along; its stroke.
  late final Float32List _centres, _bends;
  late final Int32List _strokeOf;

  /// The mesh moved by [shift]: given a point on a stroke's centre line, how
  /// far along it is (px), the stroke, and the line's normal there, how far
  /// to move it (each row of the strip moving as one).
  ui.Vertices bent(ui.Offset Function(ui.Offset centre, double along, int stroke, ui.Offset normal) shift) {
    final n = positions.length ~/ 2;
    final moved = Float32List(n * 2);
    for (var i = 0; i < n; i++) {
      final c = ui.Offset(_centres[i * 5], _centres[i * 5 + 1]);
      final d = shift(c, _centres[i * 5 + 2], _strokeOf[i], ui.Offset(_bends[i * 2], _bends[i * 2 + 1]));
      moved[i * 2] = c.dx + d.dx + _centres[i * 5 + 3];
      moved[i * 2 + 1] = c.dy + d.dy + _centres[i * 5 + 4];
    }
    return ui.Vertices.raw(ui.VertexMode.triangles, moved, textureCoordinates: textureCoordinates, indices: indices);
  }

  /// Sets the uniforms every stroke shader starts with (see
  /// shaders/stroke_space.glsl) for the moment [now], and the strokes'
  /// image; returns the index of the next float.
  int setUniforms(ui.FragmentShader shader, double now) {
    final tip = text.tip(now);
    final values = <double>[
      cellWidth, cellHeight, rows.toDouble(), scale, //
      pad, cap, halo, text.strokes.length.toDouble(),
      (StrokeText._meta + 2 * StrokeText._samples).toDouble(), math.max(text.strokes.length, 1).toDouble(),
      math.max(text.duration, 1e-3), text.halfMax,
      now, tip?.$1.toDouble() ?? -1, tip?.$2 ?? 0, text.writing.xHeight,
    ];
    for (final (i, v) in values.indexed) {
      shader.setFloat(i, v);
    }
    shader.setImageSampler(0, text.strokeData);
    return values.length;
  }
}

/// The joints as squares [radius] px round each, their texture coordinates in
/// a grid of cells, a cell each; a joint shader works out the joint from the
/// cell and looks up when it forms in [StrokeText.jointData].
class JointMesh {
  JointMesh._(this.text, this.radius, this.scale) {
    final joints = text.joints;
    cell = (2 * radius * scale + 2 * StrokeMesh.pad).ceilToDouble();
    columns = math.max(1, math.sqrt(joints.length).ceil());
    final pos = <double>[], tex = <double>[];
    final idx = <int>[];
    for (final (i, j) in joints.indexed) {
      final x0 = (i % columns) * cell + StrokeMesh.pad, y0 = (i ~/ columns) * cell + StrokeMesh.pad;
      final first = pos.length ~/ 2;
      for (final (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)]) {
        pos.addAll([j.position.dx + dx * radius, j.position.dy + dy * radius]);
        tex.addAll([x0 + (dx + 1) * radius * scale, y0 + (dy + 1) * radius * scale]);
      }
      idx.addAll([first, first + 1, first + 2, first + 1, first + 3, first + 2]);
    }
    vertices = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(pos),
        textureCoordinates: Float32List.fromList(tex), indices: Uint16List.fromList(idx));
  }

  final StrokeText text;
  final double radius, scale;
  late final double cell;
  late final int columns;
  late final ui.Vertices vertices;

  /// Sets the uniforms every joint shader starts with (see
  /// shaders/joint_space.glsl); returns the index of the next float.
  int setUniforms(ui.FragmentShader shader, double now) {
    final values = <double>[
      cell, columns.toDouble(), scale, radius, //
      math.max(text.joints.length, 1).toDouble(), text.joints.length.toDouble(), math.max(text.duration, 1e-3),
      text.writing.xHeight,
      now, 2 * text.halfMax, 0, 0,
    ];
    for (final (i, v) in values.indexed) {
      shader.setFloat(i, v);
    }
    shader.setImageSampler(0, text.jointData);
    return values.length;
  }
}
