// A stand-in for an API fountain_pen doesn't expose yet: each stroke of a
// PenWriting as laid out and timed (its points, half-widths and the time the
// pen reaches each one). The layout below is fountain_pen 0.2.1's own
// (lib/src/writing.dart), ported line for line so the same text and seed
// give the very same strokes; test/written_test.dart checks it against
// PenWriting.tip. Once fountain_pen has `PenWriting.strokes` (proposed in
// doc/findings.md), this file goes.
import 'dart:math' as math;
import 'dart:ui';

import 'package:fountain_pen/fountain_pen.dart';

/// One stroke of written text: where the pen went, how broad a line it drew
/// and when it got to each point.
class WrittenStroke {
  WrittenStroke._(this._s, this.index, this.line, this.character)
      : points = List.unmodifiable(_s.p),
        halfWidths = List.unmodifiable(_s.half),
        times = List.unmodifiable([for (final t in _s.tt) _s.t0 + t]);

  final _Stroke _s;

  /// The centre line (px, round the point the text is centred on).
  final List<Offset> points;

  /// The ink's half-width at each point (px).
  final List<double> halfWidths;

  /// When the pen reaches each point (s from the start of the writing).
  final List<double> times;

  /// Its place in the writing order; its line; the character it's part of
  /// (its index in the line as written: Arabic's in its joined forms).
  final int index, line, character;

  /// A dot (one point, drawn as a disc).
  bool get dot => _s.dot;

  /// Written once its word was done (an i's dot, a t's bar, Arabic's dots).
  bool get late => _s.late;

  /// Whether the pen came down for it (false: on from the stroke before, the
  /// pen not lifted).
  bool get lands => _s.lands;

  /// Joined on from the letter before without the pen lifting (Arabic).
  bool get joined => _s.joined;

  /// Its ink (each stroke a little different).
  Color get ink => _s.ink;

  double get start => times.first;
  double get end => times.last;
}

/// [text] laid out and timed exactly as `PenWriting` lays it out, with its
/// strokes in reach ([strokes]).
class WrittenText {
  WrittenText(
    this.text, {
    this.hand = homemadeApple,
    this.fontSize = 48,
    this.ink = PenInk.blueBlack,
    double speed = 3,
    double? duration,
    double? maxWidth,
    this.lineHeight = 1.3,
    this.align = PenAlign.center,
    this.seed = 7,
    this.typing = false,
    List<double>? typedAt,
  })  : _typedAt = typedAt,
        _speed = speed,
        _duration = duration,
        _maxWidth = maxWidth {
    final widths = [for (final line in _lines) _width(line.chars)];
    final widest = widths.isEmpty ? 0.0 : widths.reduce(math.max);
    em = maxWidth == null || widest <= 0 ? fontSize : math.min(fontSize, maxWidth / widest);
    _layout(speed);
    if (maxWidth != null && bounds.width > maxWidth && bounds.width > 0) {
      em *= maxWidth / bounds.width * 0.999;
      _relayout(speed);
    }
    if (duration != null && duration > 0 && this.duration > 0) {
      _relayout(speed * this.duration / duration);
    }
    strokes = List.unmodifiable([
      for (final (i, s) in _strokes.indexed) WrittenStroke._(s, i, s.line, s.character),
    ]);
  }

  /// The same text as fountain_pen writes it (for plain ink beside the
  /// effects).
  PenWriting toPenWriting() => PenWriting(text,
      hand: hand,
      fontSize: fontSize,
      ink: ink,
      speed: _speed,
      duration: _duration,
      maxWidth: _maxWidth,
      lineHeight: lineHeight,
      align: align,
      seed: seed);

  final double _speed;
  final double? _duration, _maxWidth;

  /// Laid out for typing (not as fountain_pen does): each character's
  /// wobble its own, from its place in the text, and the pen starting at x
  /// = 0, so typing more leaves what's written as it was; a dot or bar
  /// written straight after its letter; and each character written no sooner
  /// than [typedAt] says it was typed (s).
  final bool typing;
  final List<double>? _typedAt;

  /// Where the pen ends up on each line (px): after its last character (to
  /// its left, right to left).
  List<Offset> get lineEnds => List.unmodifiable(_lineEnd);
  final _lineEnd = <Offset>[];

  void _relayout(double speed) {
    _strokes.clear();
    _lineMid.clear();
    _lineRtl.clear();
    _lineEnd.clear();
    _boundsCache = null;
    _layout(speed);
  }

  final String text;
  final PenHand hand;
  final double fontSize;
  final PenInk ink;
  final double lineHeight;
  final PenAlign align;
  final int seed;

  /// The size it's written at (px to the em), and the x-height (px).
  late double em;
  double get xHeight => hand.xHeight * em;

  /// How long it takes to write (s).
  late double duration;

  /// Every stroke, in the order it's written.
  late final List<WrittenStroke> strokes;

  final _strokes = <_Stroke>[];
  final _lineMid = <double>[];
  final _lineRtl = <bool>[];

  /// Where the ink reaches, round the point the text is centred on.
  Rect get bounds => _boundsCache ??= _bounds();
  Rect? _boundsCache;

  Size get size => bounds.size;

  double _width(List<String> chars) => chars.fold(0.0, (w, ch) => w + (hand.glyphs[ch]?.advance ?? _gap(ch)));

  List<({List<String> chars, List<bool> joined, bool rtl})> get _lines => [
        for (final line in text.split('\n'))
          if (isRightToLeft(line))
            (chars: arabicShaped(line).text.split(''), joined: arabicShaped(line).joined, rtl: true)
          else
            (chars: line.split(''), joined: List.filled(line.length, false), rtl: false),
      ];

  double _gap(String ch) => ch == '　' ? 1.0 : hand.space;

  void _layout(double speed) {
    var r = math.Random(seed);
    double rnd() => r.nextDouble() * 2 - 1;
    var typed = 0;
    final pause = 3 / speed;
    final lines = _lines;
    final x = hand.xHeight, xh = x * em;
    final widest = lines.map((l) => _width(l.chars)).fold(0.0, math.max);
    var t = 0.0;
    Offset? last;
    for (final (k, line) in lines.indexed) {
      final chars = line.chars, rtl = line.rtl;
      if (typing) r = math.Random(seed * 31 + k);
      final gaps = [
        for (var i = 0; i < chars.length; i++) typing ? 0.02 * (math.Random(seed * 7 + typed + i).nextDouble() * 2 - 1) : 0.02 * rnd(),
      ];
      final width = _width(chars) + gaps.fold(0.0, (a, b) => a + b);
      final baseline = (k - (lines.length - 1) / 2) * lineHeight * em + xh / 2;
      _lineMid.add(baseline - xh / 2);
      _lineRtl.add(rtl);
      final tilt = 0.015 * rnd(), wave = r.nextDouble() * 6;
      final side = rtl ? -1 : 1;
      var pen = typing ? 0.0 : side * -(align == PenAlign.center ? width : widest) / 2;
      final late = <_Stroke>[];
      void dots() {
        for (final s in late) {
          s.t0 = t + 0.06 * pause;
          t = s.t0 + s.time;
          s.lands = true;
          _strokes.add(s);
        }
        late.clear();
        last = null;
      }

      for (final (i, ch) in chars.indexed) {
        if (typing) {
          // (Its own wobble, whatever comes after it; written once typed.)
          r = math.Random(seed * 1000003 + typed + i);
          final at = _typedAt;
          if (at != null && at.isNotEmpty) t = math.max(t, at[math.min(typed + i, at.length - 1)]);
        }
        final g = hand.glyphs[ch];
        if (g == null) {
          dots();
          t += 0.07 * pause;
          pen += side * (_gap(ch) + gaps[i]);
          continue;
        }
        if (rtl) pen -= g.advance + gaps[i];
        var joins = rtl && i > 0 && line.joined[i - 1];
        final cjk = _cjk(ch);
        final steady = rtl ? 0.3 : 1.0;
        final rot = 0.04 * rnd() * ink.waver * steady, scale = 1 + 0.045 * rnd() * ink.waver * steady;
        final lift = (0.025 * rnd() * steady + 0.03 * math.sin(pen * 1.1 + wave)) * ink.waver;
        final cx = g.advance / 2, cy = cjk ? 0.38 : x / 2, rise = cjk ? 0.06 + 0.02 * rnd() : 0.0;
        Offset place(double px, double py) {
          final dx = (px - cx) * scale, dy = (py + rise * (px - cx) - cy) * scale;
          final ux = cx + dx * math.cos(rot) - dy * math.sin(rot),
              uy = cy + dx * math.sin(rot) + dy * math.cos(rot) + lift;
          return Offset((pen + ux) * em, baseline - (uy + (pen + ux) * tilt * ink.waver) * em);
        }

        for (final s in g.strokes) {
          var pts = [for (var j = 0; j + 2 < s.points.length; j += 3) place(s.points[j], s.points[j + 1])];
          if (pts.isEmpty) continue;
          final bridged = joins && !s.late && last != null;
          if (bridged && (pts.last - last!).distance < (pts.first - last!).distance) pts = pts.reversed.toList();
          if (bridged) pts.insert(0, last!);
          final path = s.dot ? pts : (cjk ? _straight(pts, 1.2) : _smooth(pts, 1.2));
          final stroke =
              _Stroke(path, xh, speed * em, ink, r, dot: s.dot, nib: cjk ? _Nib.fine : (rtl ? _Nib.level : _Nib.broad))
                ..late = s.late
                ..joined = bridged
                ..line = k
                ..character = i;
          if (s.late && !typing) {
            late.add(stroke);
            continue;
          }
          if (s.late) {
            // (Typing: dotted, or barred, straight after its letter.)
            stroke.lands = true;
            stroke.t0 = t + 0.06 * pause;
            t = stroke.t0 + stroke.time;
            _strokes.add(stroke);
            continue;
          }
          if (cjk) {
            final carry = last == null ? 0.0 : (pts.first - last!).distance / em;
            stroke.lands = true;
            stroke.t0 = t + (0.05 + 0.03 * r.nextDouble() + 0.12 * carry) * pause;
            t = stroke.t0 + stroke.time;
            last = stroke.p.last;
            _strokes.add(stroke);
            continue;
          }
          final from = pts.first;
          final on = bridged ||
              (last != null && (from - last!).distance < 0.05 * em) ||
              _strokes.reversed.take(4).any((o) => o.p.any((q) => (q - from).distance < 0.04 * em));
          joins = false;
          stroke.lands = !on;
          stroke.t0 = on ? t : t + (0.03 + 0.03 * r.nextDouble()) * pause;
          t = stroke.t0 + stroke.time;
          last = stroke.p.last;
          _strokes.add(stroke);
        }
        if (!rtl) pen += g.advance + gaps[i];
      }
      _lineEnd.add(Offset(pen * em, baseline - xh / 2));
      typed += chars.length + 1;
      dots();
      if (k < lines.length - 1) t += 0.15 * pause;
    }
    duration = t;
  }

  Rect _bounds() {
    if (_strokes.isEmpty) return Rect.zero;
    var l = double.infinity, tp = double.infinity, rt = -double.infinity, b = -double.infinity;
    for (final s in _strokes) {
      for (final p in s.p) {
        l = math.min(l, p.dx);
        tp = math.min(tp, p.dy);
        rt = math.max(rt, p.dx);
        b = math.max(b, p.dy);
      }
    }
    final pad = hand.xHeight * em * (ink.fine + ink.heavy) + 2;
    return Rect.fromLTRB(l - pad, tp - pad, rt + pad, b + pad);
  }

  static bool _cjk(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 0x3000 && c <= 0x30FF) ||
        (c >= 0x3400 && c <= 0x9FFF) ||
        (c >= 0xF900 && c <= 0xFAFF) ||
        (c >= 0xFF00 && c <= 0xFFEF);
  }

  static List<Offset> _straight(List<Offset> p, double step) {
    if (p.length < 2) return p;
    final out = <Offset>[p.first];
    for (var i = 0; i + 1 < p.length; i++) {
      final n = math.max(1, ((p[i + 1] - p[i]).distance / step).ceil());
      for (var k = 1; k <= n; k++) {
        out.add(Offset.lerp(p[i], p[i + 1], k / n)!);
      }
    }
    return out;
  }

  static List<Offset> _smooth(List<Offset> p, double step) {
    if (p.length < 2) return p;
    final out = <Offset>[p.first];
    for (var i = 0; i + 1 < p.length; i++) {
      final p0 = i == 0 ? p[0] * 2 - p[1] : p[i - 1],
          p1 = p[i],
          p2 = p[i + 1],
          p3 = i + 2 < p.length ? p[i + 2] : p[i + 1] * 2 - p[i];
      final n = math.max(1, ((p2 - p1).distance / step).ceil());
      for (var k = 1; k <= n; k++) {
        final u = k / n, u2 = u * u, u3 = u2 * u;
        out.add(
            (p1 * 2 + (p2 - p0) * u + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2 + (p1 * 3 - p0 - p2 * 3 + p3) * u3) * 0.5);
      }
    }
    return out;
  }

  /// Where the pen is [t] seconds in (as `PenWriting.tip`).
  Offset tip(double t) {
    var at = _strokes.isEmpty ? Offset.zero : _strokes.first.p.first;
    for (final s in _strokes) {
      if (t < s.t0) break;
      at = s.at(t - s.t0);
    }
    return at;
  }
}

enum _Nib { broad, fine, level }

class _Stroke {
  _Stroke(List<Offset> pts, this.xh, double v, this.style, math.Random r, {this.dot = false, _Nib nib = _Nib.broad})
      : ink = Color.lerp(
            style.color, style.isLight ? const Color(0xFFD8CDB8) : const Color(0xFF070B1E), 0.3 * r.nextDouble())! {
    final ph = [for (var i = 0; i < 4; i++) r.nextDouble() * 6.3];
    var s = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) s += (pts[i] - pts[i - 1]).distance;
      final k = s / xh;
      p.add(pts[i] +
          Offset(math.sin(k * 1.9 + ph[0]) + 0.4 * math.sin(k * 4.3 + ph[1]),
                  math.sin(k * 1.7 + ph[2]) + 0.4 * math.sin(k * 3.9 + ph[3])) *
              (0.014 * xh * style.waver));
    }
    final speed = v * (0.88 + 0.24 * r.nextDouble());
    final run = [0.0];
    for (var i = 1; i < p.length; i++) {
      run.add(run.last + (p[i] - p[i - 1]).distance);
    }
    final total = run.last, ramp = 0.3 * xh;
    final bend = _bend(p, run, 0.04 * xh);
    final pace = <double>[];
    for (var i = 0; i < p.length; i++) {
      final law = math.max(math.pow(1 / (xh * math.max(bend[i], 1 / (4 * xh))), 1 / 3).toDouble(), 0.3);
      final end = math.min(run[i], total - run[i]) / ramp;
      final ease = end >= 1 ? 1.0 : 0.25 + 0.75 * end * end * (3 - 2 * end);
      pace.add(law * ease);
    }
    var at = 0.0;
    for (var i = 1; i < p.length; i++) {
      at += (run[i] - run[i - 1]) / ((pace[i] + pace[i - 1]) / 2);
    }
    final scale = at > 0 && total > 0 ? at / total : 1.0;
    tt.add(0);
    for (var i = 1; i < p.length; i++) {
      tt.add(tt.last + (run[i] - run[i - 1]) / (speed * (pace[i] + pace[i - 1]) / 2 * scale));
    }
    if (dot) tt.last = 0.05 * 3 * xh / math.max(v, 1e-6);
    final q = r.nextDouble() * 6.3, raw = <double>[];
    final hair = style.fine * switch (nib) { _Nib.fine => 2.2, _Nib.level => 1.5, _Nib.broad => 1.0 };
    final press = style.heavy * switch (nib) { _Nib.fine => 0.45, _Nib.level => 0.75, _Nib.broad => 1.0 };
    for (var i = 0; i < p.length; i++) {
      final d = i + 1 < p.length ? p[i + 1] - p[i] : (i > 0 ? p[i] - p[i - 1] : const Offset(0, 1));
      final len = math.max(d.distance, 1e-6);
      final down = (d.dy / len).clamp(0.0, 1.0), level = d.dx.abs() / len;
      final across = ((d.dx * math.sin(style.nibAngle) + d.dy * math.cos(style.nibAngle)) / len).abs();
      final weight = nib == _Nib.level ? 0.65 * level * level + 0.35 * down * down : 0.7 * down * down + 0.3 * across;
      raw.add(xh * (hair + press * weight * (0.85 + 0.15 * math.sin(i * 0.035 + q))) / 2);
    }
    for (var i = 0; i < raw.length; i++) {
      var sum = 0.0, n = 0;
      for (var j = math.max(0, i - 6); j <= math.min(raw.length - 1, i + 6); j++) {
        sum += raw[j];
        n++;
      }
      half.add(dot ? xh * 0.11 : sum / n);
    }
  }

  static List<double> _bend(List<Offset> p, List<double> run, double sigma) {
    final total = run.last;
    if (p.length < 3 || total <= 0) return List.filled(p.length, 0);
    final n = math.max((total / (sigma / 4)).ceil(), 2) + 1, step = total / (n - 1);
    final xy = <Offset>[];
    for (var i = 0, j = 0; i < n; i++) {
      final s = step * i;
      while (j < p.length - 2 && run[j + 1] < s) {
        j++;
      }
      final seg = run[j + 1] - run[j];
      xy.add(Offset.lerp(p[j], p[j + 1], seg > 0 ? ((s - run[j]) / seg).clamp(0.0, 1.0) : 0)!);
    }
    final w = (3 * sigma / step).round();
    final bell = [for (var k = -w; k <= w; k++) math.exp(-0.5 * math.pow(k * step / sigma, 2))];
    final sum = bell.fold(0.0, (a, b) => a + b);
    Offset at(int i) => i < 0
        ? xy[0] * 2 - xy[math.min(-i, n - 1)]
        : (i >= n ? xy[n - 1] * 2 - xy[math.max(2 * (n - 1) - i, 0)] : xy[i]);
    final sm = [
      for (var i = 0; i < n; i++)
        () {
          var o = Offset.zero;
          for (var k = -w; k <= w; k++) {
            o += at(i + k) * bell[k + w];
          }
          return o / sum;
        }(),
    ];
    final k = List<double>.filled(n, 0);
    for (var i = 1; i < n - 1; i++) {
      final d = (sm[i + 1] - sm[i - 1]) / 2, dd = sm[i + 1] - sm[i] * 2 + sm[i - 1];
      k[i] = (d.dx * dd.dy - d.dy * dd.dx).abs() / math.max(math.pow(d.distance, 3).toDouble(), 1e-18);
    }
    k[0] = k[1];
    k[n - 1] = k[n - 2];
    return [
      for (final s in run)
        () {
          final f = (s / step).clamp(0.0, n - 1.0), i = math.min(f.floor(), n - 2);
          return k[i] + (k[i + 1] - k[i]) * (f - i);
        }(),
    ];
  }

  final double xh;
  final PenInk style;
  final bool dot;
  final Color ink;
  final p = <Offset>[];
  final tt = <double>[];
  final half = <double>[];
  double t0 = 0;
  bool lands = true, late = false, joined = false;
  int line = 0, character = 0;

  double get time => tt.last;

  Offset at(double t) {
    var n = 1;
    while (n < p.length && tt[n] <= t) {
      n++;
    }
    if (n >= p.length) return p.last;
    return Offset.lerp(p[n - 1], p[n], ((t - tt[n - 1]) / (tt[n] - tt[n - 1])).clamp(0.0, 1.0))!;
  }
}
