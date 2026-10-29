import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:fountain_pen/fountain_pen.dart';

import 'effects.dart';
import 'space.dart';
import 'written.dart';

/// Paints [text] in [effect] as it is [time] s into its writing, fitted into
/// the box (on the effect's background).
class StrokeFxPainter extends CustomPainter {
  StrokeFxPainter({required this.text, required this.effect, required this.time, this.devicePixelRatio = 1})
      : super(repaint: time);

  final StrokeText text;
  final StrokeEffect effect;
  final ValueListenable<double> time;

  /// The screen's, so Impeller's stroke-space image is as sharp as the
  /// screen.
  final double devicePixelRatio;

  /// The scale [text] is painted at in a box of [size].
  static double fit(StrokeText text, Size size) {
    final b = text.writing.bounds;
    return math.min(size.width * 0.9 / b.width, size.height * 0.78 / b.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = effect.background);
    effect.paintBackdrop(canvas, Offset.zero & size);
    final k = fit(text, size), b = text.writing.bounds;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(k)
      ..translate(-b.center.dx, -b.center.dy);
    effect.paint(canvas, text, time.value, k * devicePixelRatio);
    canvas.restore();
  }

  @override
  bool shouldRepaint(StrokeFxPainter old) =>
      old.text != text || old.effect != effect || old.time != time || old.devicePixelRatio != devicePixelRatio;
}

/// [text] written in [hand] with a stroke-space [effect], played as it's
/// written and (if [repeat]) again after [hold] s.
class StrokeFxText extends StatefulWidget {
  const StrokeFxText(
    this.text, {
    super.key,
    required this.effect,
    this.hand = homemadeApple,
    this.fontSize = 96,
    this.duration,
    this.seed = 7,
    this.repeat = true,
    this.hold = 3,
  });

  final String text;
  final StrokeEffect effect;
  final PenHand hand;
  final double fontSize;

  /// How long the writing takes (s; by default a hand's own pace).
  final double? duration;
  final int seed;
  final bool repeat;

  /// How long it rests, written, before it's written again (s).
  final double hold;

  @override
  State<StrokeFxText> createState() => _StrokeFxTextState();
}

class _StrokeFxTextState extends State<StrokeFxText> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier(0.0);
  StrokeText? _text;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    await StrokeShaders.load();
    final writing = WrittenText(widget.text,
        hand: widget.hand, fontSize: widget.fontSize, duration: widget.duration, seed: widget.seed);
    final text = await StrokeText.of(writing);
    if (!mounted) return;
    setState(() {
      _text?.dispose();
      _text = text;
      _ready = true;
    });
    _ticker
      ..stop()
      ..start();
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6, text = _text!;
    final loop = text.duration + widget.hold;
    _time.value = widget.repeat ? t % loop : math.min(t, loop);
  }

  @override
  void didUpdateWidget(StrokeFxText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text ||
        old.hand != widget.hand ||
        old.fontSize != widget.fontSize ||
        old.duration != widget.duration ||
        old.seed != widget.seed) {
      _prepare();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _text?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ready
      ? RepaintBoundary(
          child: CustomPaint(
            painter: StrokeFxPainter(
              text: _text!,
              effect: widget.effect,
              time: _time,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
            size: Size.infinite,
          ),
        )
      : ColoredBox(color: widget.effect.background);
}
