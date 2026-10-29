// A gallery of stroke_fx's effects: pick an effect and a script.
//
//   flutter run -d macos --profile
//   flutter run -d chrome
//
// --dart-define=BENCH=true plays every effect in every script for a few
// seconds each and prints its frame times. --dart-define=CAPTURE=all (or
// Neon:Latin,Weld:Japanese) renders each to PNG frames, for the GIFs
// (tool/make_gifs.sh); native only.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/stroke_fx.dart';

import 'io_stub.dart' if (dart.library.io) 'io_native.dart' as io;

/// The samples: one line in each script.
final samples = <({String name, String text, PenHand hand, double duration})>[
  (name: 'Latin', text: 'Stroke by stroke', hand: homemadeApple, duration: 4.5),
  (name: 'Japanese', text: '手書きの日本語', hand: notoSansJapanese, duration: 6.5),
  (name: 'Arabic', text: 'بالقلم والحبر', hand: notoNaskhArabic, duration: 4.0),
];

List<StrokeEffect> makeEffects() =>
    [PlainInk(), Neon(), Ember(), InkBleed(), Ribbon(), Weld(), Constellation(), Frost(), Dew(), Sakura(), Ivy(), Jelly(), Snow(), Fireflies()];

/// What each effect shows that only stroke space can.
const captions = {
  'Plain ink': 'The control: fountain_pen\'s ink, drawn through the same mesh and shader.',
  'Neon': 'Each tube lights as the pen reaches it; light runs the way each stroke was written.',
  'Ember': 'Hot where the pen has just been: each point cools by when the pen passed it.',
  'Ink bleed': 'Ink spreads as it dries, furthest where the pen went slowly or came down.',
  'Ribbon': 'Each stroke a two-faced ribbon, twisting along it; the mesh itself waves.',
  'Weld': 'Joints: each one flashes and throws sparks as the pen reaches it, then cools.',
  'Constellation': 'Joints: each one a star as the pen reaches it. Joins gold, touches blue, crossings pink.',
  'Frost': 'The ink freezes as it\'s written; frost feathers grow, and ice forms first where strokes meet.',
  'Dew': 'Spider silk, pinned at its joints: it sags with a bounce once written, sways, and gathers dew.',
  'Sakura': 'Branches grow as the pen goes; blossoms open at the joints and shed petals on the breeze.',
  'Ivy': 'A vine climbs each stroke behind the pen, twining round it; leaves open, tendrils reach and coil.',
  'Jelly': 'Soft: the pen drags the jelly it writes on; when it lifts, the jelly springs back and wobbles still.',
  'Snow': 'Snow settles only where an edge faces up, deeper the longer the ink has lain there.',
  'Fireflies': 'Fireflies rise from the ink; blinking each to its own rhythm, they fall into step.',
};

/// How long a sample rests, written, before it's written again (s).
const hold = 3.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StrokeShaders.load();
  final texts = [
    for (final s in samples)
      await StrokeText.of(WrittenText(s.text, hand: s.hand, fontSize: 96, duration: s.duration)),
  ];
  const capture = String.fromEnvironment('CAPTURE');
  if (capture.isNotEmpty) {
    await io.capture(capture, texts, [for (final s in samples) s.name], makeEffects(), hold);
    return;
  }
  runApp(Gallery(texts: texts, bench: const bool.fromEnvironment('BENCH')));
}

class Gallery extends StatefulWidget {
  const Gallery({super.key, required this.texts, this.bench = false});

  final List<StrokeText> texts;
  final bool bench;

  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> with SingleTickerProviderStateMixin {
  final effects = makeEffects();
  var effect = 1, script = 0;
  final clock = ValueNotifier(0.0);
  late final Ticker ticker = createTicker(_tick);
  Duration _start = Duration.zero, _last = Duration.zero;
  final _timings = <FrameTiming>[];
  final perf = ValueNotifier('');
  var _frames = 0;

  /// What you're typing, written as you type it (in place of the sample):
  /// each character no sooner than you typed it, on a clock that doesn't
  /// loop, so what's written goes on ageing.
  StrokeText? typed;
  final _typing = TextEditingController();
  var _typedText = '';
  final _typedAt = <double>[];
  var _session = Duration.zero, _generation = 0;
  final _view = _TypingView();

  StrokeText get text => typed ?? widget.texts[script];

  double get _sessionTime => (_last - _session).inMicroseconds / 1e6;

  void _type(String value) {
    if (_typedText.isEmpty) _session = _last;
    final now = _sessionTime;
    var k = 0;
    while (k < _typedText.length && k < value.length && _typedText.codeUnitAt(k) == value.codeUnitAt(k)) {
      k++;
    }
    _typedAt.length = k;
    for (var i = k; i < value.length; i++) {
      _typedAt.add(now);
    }
    _typedText = value;
    _write();
  }

  /// Lays out what's typed, in the hand for its script, and shows it.
  void _write() {
    final v = _typedText;
    final generation = ++_generation;
    if (v.trim().isEmpty) {
      setState(() => typed = null);
      _typedText = '';
      _typedAt.clear();
      return;
    }
    final (hand, s) = isRightToLeft(v)
        ? (notoNaskhArabic, 2)
        : (RegExp(r'[\u3000-\u30ff\u3400-\u9fff\uff00-\uffef]').hasMatch(v) ? (notoSansJapanese, 1) : (homemadeApple, 0));
    StrokeText.of(WrittenText(v, hand: hand, fontSize: 96, typing: true, typedAt: List.of(_typedAt))).then((t) {
      if (!mounted || generation != _generation) return;
      setState(() {
        typed = t;
        script = s;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    ticker.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    if (widget.bench) _bench();
  }

  void _tick(Duration elapsed) {
    _last = elapsed;
    _frames++;
    _count(elapsed);
    if (typed != null) {
      clock.value = _sessionTime;
      return;
    }
    final t = (elapsed - _start).inMicroseconds / 1e6;
    clock.value = t % (text.duration + hold);
  }

  void replay() {
    _start = _last;
    if (_typedText.isNotEmpty) {
      // (Typing: all of it written again, from now.)
      _session = _last;
      _typedAt.setAll(0, List.filled(_typedAt.length, 0.0));
      _write();
    }
  }

  /// What's drawing it: on the web, WebAssembly (skwasm) or JavaScript
  /// (CanvasKit), whichever the browser can run.
  static const _renderer = kIsWasm ? 'WebAssembly · skwasm' : (kIsWeb ? 'JavaScript · CanvasKit' : 'Impeller');
  final _stamps = <Duration>[];
  var _times = '';

  /// The frames drawn in the last second, with the frame times, every
  /// quarter second or so.
  void _count(Duration elapsed) {
    _stamps.add(elapsed);
    while (elapsed - _stamps.first > const Duration(seconds: 1)) {
      _stamps.removeAt(0);
    }
    if (_frames % 15 == 0) perf.value = '$_renderer · ${_stamps.length} fps$_times';
  }

  void _onTimings(List<FrameTiming> timings) {
    _timings.addAll(timings);
    if (_timings.length > 600) _timings.removeRange(0, _timings.length - 600);
    final recent = _timings.length > 120 ? _timings.sublist(_timings.length - 120) : _timings;
    final s = _stats(recent);
    _times = ' · build ${s.build50.toStringAsFixed(1)} / raster ${s.raster50.toStringAsFixed(1)} ms';
  }

  static ({double build50, double build90, double raster50, double raster90, double rasterMax}) _stats(
      List<FrameTiming> t) {
    double at(List<double> v, double q) => v.isEmpty ? 0 : v[math.min(v.length - 1, (v.length * q).floor())];
    final build = [for (final f in t) f.buildDuration.inMicroseconds / 1000]..sort();
    final raster = [for (final f in t) f.rasterDuration.inMicroseconds / 1000]..sort();
    return (
      build50: at(build, 0.5),
      build90: at(build, 0.9),
      raster50: at(raster, 0.5),
      raster90: at(raster, 0.9),
      rasterMax: raster.isEmpty ? 0 : raster.last,
    );
  }

  /// Each effect in each script for 4 s (the first ignored), its frames
  /// counted and timed.
  Future<void> _bench() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    debugPrint('BENCH effect | script | fps | build p50/p90 | raster p50/p90/max (ms) | frames');
    const only = String.fromEnvironment('BENCH_ONLY');
    for (var e = 0; e < effects.length; e++) {
      if (only.isNotEmpty && !only.split(',').contains(effects[e].name)) continue;
      for (var s = 0; s < widget.texts.length; s++) {
        setState(() {
          effect = e;
          script = s;
        });
        replay();
        await Future<void>.delayed(const Duration(seconds: 1));
        _timings.clear();
        final frames0 = _frames, t0 = _last;
        await Future<void>.delayed(const Duration(seconds: 3));
        final fps = (_frames - frames0) / ((_last - t0).inMicroseconds / 1e6);
        final st = _stats(List.of(_timings));
        debugPrint('BENCH ${effects[e].name} | ${samples[s].name} | ${fps.toStringAsFixed(1)} | '
            '${st.build50.toStringAsFixed(2)}/${st.build90.toStringAsFixed(2)} | '
            '${st.raster50.toStringAsFixed(2)}/${st.raster90.toStringAsFixed(2)}/${st.rasterMax.toStringAsFixed(2)} | '
            '${_timings.length}');
      }
    }
    debugPrint('BENCH done');
    io.quit();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _typing.dispose();
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = effects[effect];
    const bar = Color(0xFF15151B);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF7C8CFF)),
      home: Scaffold(
        backgroundColor: fx.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: bar,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (i, e) in effects.indexed)
                        ChoiceChip(
                          label: Text(e.name),
                          selected: i == effect,
                          onSelected: (_) => setState(() {
                            effect = i;
                            replay();
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<int>(
                        segments: [
                          for (final (i, s) in samples.indexed) ButtonSegment(value: i, label: Text(s.name)),
                        ],
                        selected: {script},
                        onSelectionChanged: (v) => setState(() {
                          script = v.first;
                          typed = null;
                          _generation++;
                          _typing.clear();
                          _typedText = '';
                          _typedAt.clear();
                          replay();
                        }),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Write it again',
                        onPressed: replay,
                        icon: const Icon(Icons.replay),
                      ),
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _typing,
                          onChanged: _type,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            hintText: 'Type: written as you type (Latin, 日本語, عربي)',
                          ),
                        ),
                      ),
                      ValueListenableBuilder(
                        valueListenable: perf,
                        builder: (context, value, _) => Text(value,
                            style: const TextStyle(fontSize: 12, color: Colors.white54, fontFeatures: [
                              FontFeature.tabularFigures(),
                            ])),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(captions[fx.name] ?? '', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ],
              ),
            ),
            Expanded(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: typed == null
                      ? StrokeFxPainter(
                          text: text,
                          effect: fx,
                          time: clock,
                          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                        )
                      : _TypingPainter(typed!, fx, clock, MediaQuery.devicePixelRatioOf(context), _view),
                  size: Size.infinite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scale the typed text is shown at, eased from frame to frame.
class _TypingView {
  var scale = 0.0;
}

/// What's typed, written as it's typed: from the left (or the right, right
/// to left), at a steady size until it nears the far edge, then easing
/// smaller to keep it all in view; a caret once the pen has caught up.
class _TypingPainter extends CustomPainter {
  _TypingPainter(this.text, this.effect, this.time, this.devicePixelRatio, this.view) : super(repaint: time);

  final StrokeText text;
  final StrokeEffect effect;
  final ValueListenable<double> time;
  final double devicePixelRatio;
  final _TypingView view;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = effect.background);
    effect.paintBackdrop(canvas, Offset.zero & size);
    final w = text.writing, xh = w.xHeight, now = time.value;
    final margin = size.width * 0.06;
    final rtl = isRightToLeft(w.text);
    final end = w.lineEnds.isEmpty ? Offset.zero : w.lineEnds.last;
    final extent = rtl ? -math.min(end.dx, w.bounds.left) : math.max(end.dx, w.bounds.right);
    final target = math.min(size.height * 0.13 / xh, (size.width - 2 * margin) / math.max(extent + xh * 0.4, 1));
    view.scale = view.scale == 0 ? target : view.scale + (target - view.scale) * 0.1;
    final k = view.scale;
    canvas
      ..save()
      ..translate(rtl ? size.width - margin : margin, size.height / 2)
      ..scale(k);
    effect.paint(canvas, text, now, k * devicePixelRatio);
    if (now >= text.duration && (now * 1.7).floor().isEven) {
      final light = effect.background.computeLuminance() < 0.3;
      final at = end + Offset(rtl ? -xh * 0.18 : xh * 0.18, 0);
      canvas.drawLine(at + Offset(0, -xh * 0.95), at + Offset(0, xh * 0.65), Paint()
        ..color = (light ? Colors.white : Colors.black).withValues(alpha: 0.55)
        ..strokeWidth = 2 / k);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TypingPainter old) => true;
}
