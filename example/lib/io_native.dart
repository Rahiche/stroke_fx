import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:stroke_fx/stroke_fx.dart';

/// Renders each effect:script pair in [spec] ("all", or "Neon:Latin,...") to
/// PNG frames at 30 fps, written and then held [hold] s, in
/// `<temp>/stroke_fx_frames/<effect>_<script>/f00001.png`. Then quits.
Future<void> capture(
    String spec, List<StrokeText> texts, List<String> scripts, List<StrokeEffect> effects, double hold) async {
  String slug(String s) => s.toLowerCase().replaceAll(' ', '_');
  final pairs = <(StrokeEffect, int)>[
    for (final e in effects)
      for (var s = 0; s < scripts.length; s++)
        if (spec == 'all' || spec.split(',').contains('${e.name}:${scripts[s]}')) (e, s),
  ];
  final root = Directory('${Directory.systemTemp.path}/stroke_fx_frames')..createSync(recursive: true);
  const size = Size(800, 300), ratio = 2.0;
  for (final (e, s) in pairs) {
    final dir = Directory('${root.path}/${slug(e.name)}_${slug(scripts[s])}');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final text = texts[s], frames = ((text.duration + hold) * 30).round();
    final clock = ValueNotifier(0.0);
    final painter = StrokeFxPainter(text: text, effect: e, time: clock, devicePixelRatio: ratio);
    final watch = Stopwatch()..start();
    for (var f = 0; f < frames; f++) {
      clock.value = f / 30;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(ratio);
      painter.paint(c, size);
      final img = await rec.endRecording().toImage((size.width * ratio).round(), (size.height * ratio).round());
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/f${(f + 1).toString().padLeft(5, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
      img.dispose();
    }
    debugPrint('CAPTURED ${dir.path} ($frames frames, ${watch.elapsedMilliseconds} ms)');
  }
  debugPrint('CAPTURE done ${root.path}');
  exit(0);
}

void quit() => exit(0);
