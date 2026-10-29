import 'dart:math' as math;
import 'dart:ui';

import 'written.dart';

/// How two strokes meet.
enum JointKind {
  /// The pen goes on from one letter into the next without lifting (cursive
  /// Latin, Arabic).
  join,

  /// A stroke starts or ends on another (a kanji's corner, a T), or closes on
  /// itself (an o).
  touch,

  /// Two strokes cross, or one crosses itself (a loop).
  cross,
}

/// Where strokes meet, and when the pen makes them meet.
class Joint {
  const Joint(this.position, this.time, this.kind, this.a, this.b, this.angle, this.size);

  /// Where (px, in the strokes' coordinates).
  final Offset position;

  /// When it forms: the moment the second of its strokes gets there (s).
  final double time;

  final JointKind kind;

  /// The strokes that meet (the same for a loop), in writing order.
  final int a, b;

  /// The angle between the two strokes there (radians, 0 to pi/2).
  final double angle;

  /// The two inks' half-widths there, together (px).
  final double size;

  @override
  String toString() => 'Joint(${kind.name} ${position.dx.toStringAsFixed(1)},${position.dy.toStringAsFixed(1)} '
      't=${time.toStringAsFixed(2)} $a/$b)';
}

/// A stroke's centre line, a point every couple of px: where, how far along,
/// when, how broad.
class _Line {
  _Line(this.stroke) {
    final p = stroke.points;
    var run = 0.0;
    for (var i = 0; i < p.length; i++) {
      if (i > 0) run += (p[i] - p[i - 1]).distance;
      if (i == 0 || i == p.length - 1 || run - s.last >= 2) {
        pts.add(p[i]);
        s.add(run);
        t.add(stroke.times[i]);
        h.add(stroke.halfWidths[i]);
      }
    }
  }

  final WrittenStroke stroke;
  final pts = <Offset>[], s = <double>[], t = <double>[], h = <double>[];
}

/// Every joint in [strokes] (written at x-height [xHeight] px), in the order
/// they form.
List<Joint> findJoints(List<WrittenStroke> strokes, double xHeight) {
  final lines = [for (final s in strokes) _Line(s)];
  final found = <Joint>[];
  // (Segments in a grid of cells, to find the ones near a point quickly.)
  const cell = 8.0;
  final grid = <int, List<(int, int)>>{};
  int key(int x, int y) => (x + 4096) * 8192 + (y + 4096);
  for (final (li, l) in lines.indexed) {
    if (l.stroke.dot) continue;
    for (var i = 0; i + 1 < l.pts.length; i++) {
      final r = Rect.fromPoints(l.pts[i], l.pts[i + 1]);
      for (var x = (r.left / cell).floor(); x <= (r.right / cell).floor(); x++) {
        for (var y = (r.top / cell).floor(); y <= (r.bottom / cell).floor(); y++) {
          (grid[key(x, y)] ??= []).add((li, i));
        }
      }
    }
  }
  Iterable<(int, int)> near(Rect r) sync* {
    final seen = <(int, int)>{};
    for (var x = (r.left / cell).floor(); x <= (r.right / cell).floor(); x++) {
      for (var y = (r.top / cell).floor(); y <= (r.bottom / cell).floor(); y++) {
        for (final seg in grid[key(x, y)] ?? const <(int, int)>[]) {
          if (seen.add(seg)) yield seg;
        }
      }
    }
  }

  double angleBetween(Offset d1, Offset d2) {
    final c = (d1.dx * d2.dx + d1.dy * d2.dy).abs() / math.max(d1.distance * d2.distance, 1e-9);
    return math.acos(c.clamp(0.0, 1.0));
  }

  Offset dirAt(_Line l, int i) => l.pts[math.min(i + 1, l.pts.length - 1)] - l.pts[math.max(i - 1, 0)];

  // Joins: on from the stroke before, the pen not lifted, into another letter.
  for (var k = 1; k < strokes.length; k++) {
    final s = strokes[k], prev = strokes[k - 1];
    if (s.lands || s.dot || prev.dot) continue;
    if (s.character == prev.character && s.line == prev.line && !s.joined) continue;
    final la = lines[k - 1], lb = lines[k];
    found.add(Joint(s.points.first, s.start, JointKind.join, k - 1, k,
        angleBetween(dirAt(la, la.pts.length - 1), dirAt(lb, 0)), la.h.last + lb.h.first));
  }

  // Touches: a stroke's end on another stroke (or on itself, further along).
  for (final (li, l) in lines.indexed) {
    if (l.stroke.dot || l.pts.length < 2) continue;
    for (final atStart in [true, false]) {
      final e = atStart ? l.pts.first : l.pts.last;
      final he = atStart ? l.h.first : l.h.last;
      final te = atStart ? l.t.first : l.t.last;
      final se = atStart ? 0.0 : l.s.last;
      // (Not where the pen simply went on into the next stroke, or came on
      // from the last: those are joins, or one stroke traced in pieces.)
      final k = l.stroke.index;
      final skip = atStart ? (l.stroke.lands ? -1 : k - 1) : (k + 1 < strokes.length && !strokes[k + 1].lands ? k + 1 : -1);
      var best = double.infinity;
      (int, int, double)? hit;
      Offset? at;
      for (final (lj, j) in near(Rect.fromCircle(center: e, radius: he + 12))) {
        if (lj == skip) continue;
        final o = lines[lj];
        final a = o.pts[j], b = o.pts[j + 1];
        final ab = b - a;
        final f = ((e - a).dx * ab.dx + (e - a).dy * ab.dy) / math.max(ab.distanceSquared, 1e-9);
        final q = a + ab * f.clamp(0.0, 1.0);
        final d = (e - q).distance;
        final reach = he + o.h[j] + 1.0;
        if (d > reach || d >= best) continue;
        if (lj == li) {
          // (Itself: only well along, where it comes back round.)
          final sq = o.s[j] + (o.s[j + 1] - o.s[j]) * f.clamp(0.0, 1.0);
          if ((sq - se).abs() < 4 * (he + o.h[j]) + 0.15 * xHeight) continue;
        } else {
          // (Another stroke's end meeting this one's end is found from both:
          // kept once, from the later stroke.)
          final otherEnd = (j == 0 && f <= 0) || (j + 1 == o.pts.length - 1 && f >= 1);
          if (otherEnd && lj > li) continue;
        }
        best = d;
        hit = (lj, j, f.clamp(0.0, 1.0));
        at = q;
      }
      if (hit == null) continue;
      final (lj, j, f) = hit;
      final o = lines[lj];
      final to = o.t[j] + (o.t[j + 1] - o.t[j]) * f;
      final ia = math.min(li, lj), ib = math.max(li, lj);
      found.add(Joint(Offset.lerp(e, at!, 0.5)!, math.max(te, to), JointKind.touch, ia, ib,
          angleBetween(dirAt(l, atStart ? 0 : l.pts.length - 1), o.pts[j + 1] - o.pts[j]), he + o.h[j]));
    }
  }

  // Crossings: segments of two strokes (or of one, well apart) that cross.
  for (final (li, l) in lines.indexed) {
    if (l.stroke.dot) continue;
    for (var i = 0; i + 1 < l.pts.length; i++) {
      final a = l.pts[i], b = l.pts[i + 1];
      for (final (lj, j) in near(Rect.fromPoints(a, b))) {
        if (lj < li || (lj == li && j <= i + 1)) continue;
        final o = lines[lj];
        final c = o.pts[j], d = o.pts[j + 1];
        final x = _cross(a, b, c, d);
        if (x == null) continue;
        final (fa, fc) = x;
        final sa = l.s[i] + (l.s[i + 1] - l.s[i]) * fa, sc = o.s[j] + (o.s[j + 1] - o.s[j]) * fc;
        final ha = l.h[i], hc = o.h[j];
        if (lj == li) {
          if ((sc - sa).abs() < 4 * (ha + hc) + 0.15 * xHeight) continue;
        } else {
          // (Not at the very ends: those are touches or joins.)
          final margin = ha + hc + 2;
          if (sa < margin || sa > l.s.last - margin || sc < margin || sc > o.s.last - margin) continue;
        }
        final ta = l.t[i] + (l.t[i + 1] - l.t[i]) * fa, tc = o.t[j] + (o.t[j + 1] - o.t[j]) * fc;
        found.add(Joint(Offset.lerp(a, b, fa)!, math.max(ta, tc), JointKind.cross, li, lj,
            angleBetween(b - a, d - c), ha + hc));
      }
    }
  }

  // The same meeting found twice (from each stroke, or as a touch and a
  // crossing), close in place and time: kept once, the earliest.
  found.sort((p, q) => p.time.compareTo(q.time));
  final kept = <Joint>[];
  for (final j in found) {
    final r = math.max(1.5 * j.size, 0.12 * xHeight);
    final same = kept.any((k) => (k.position - j.position).distance < r && (j.time - k.time).abs() < 0.2);
    if (!same) kept.add(j);
  }
  return kept;
}

/// Where segments ab and cd cross, as fractions along each, if they do.
(double, double)? _cross(Offset a, Offset b, Offset c, Offset d) {
  final r = b - a, s = d - c;
  final den = r.dx * s.dy - r.dy * s.dx;
  if (den.abs() < 1e-9) return null;
  final ac = c - a;
  final t = (ac.dx * s.dy - ac.dy * s.dx) / den, u = (ac.dx * r.dy - ac.dy * r.dx) / den;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return (t, u);
}
