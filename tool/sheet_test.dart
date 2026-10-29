// Renders each effect in each script, mid-writing and once written, as a
// contact sheet per effect: SHEETS/<effect>.png. (flutter test draws with
// Skia, as the web does: shaders run per pixel.)
//   SHEETS=/some/dir flutter test tool/sheet_test.dart
//   ONLY=Neon,Weld ... just those.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/stroke_fx.dart';

final samples = [
  ('Stroke by stroke', homemadeApple, 4.5),
  ('手書きの日本語', notoSansJapanese, 6.0),
  ('بالقلم والحبر', notoNaskhArabic, 4.0),
];

void main() {
  testWidgets('sheets', (tester) async {
    await tester.runAsync(() async {
      await StrokeShaders.load();
      final out = Directory(Platform.environment['SHEETS'] ?? 'build/sheets')..createSync(recursive: true);
      final only = {...?Platform.environment['ONLY']?.split(',').where((s) => s.isNotEmpty)};
      final texts = [
        for (final (t, hand, d) in samples) await StrokeText.of(WrittenText(t, hand: hand, fontSize: 96, duration: d)),
      ];
      final effects = [PlainInk(), Neon(), Ember(), InkBleed(), Ribbon(), Weld(), Constellation(), Frost(), Dew(), Sakura(), Ivy(), Jelly(), Snow(), Fireflies()];
      const cell = Size(760, 250), k = 1.5;
      for (final e in effects) {
        if (only.isNotEmpty && !only.contains(e.name)) continue;
        final rec = ui.PictureRecorder();
        final c = Canvas(rec)..scale(k);
        for (final (row, text) in texts.indexed) {
          for (final (col, at) in [0.55, 1.0].indexed) {
            final now = at < 1 ? text.duration * at : text.duration + 0.9;
            c.save();
            c.translate(col * cell.width, row * cell.height);
            c.clipRect(Offset.zero & cell);
            StrokeFxPainter(text: text, effect: e, time: ValueNotifier(now), devicePixelRatio: k).paint(c, cell);
            c.restore();
          }
        }
        final img = await rec.endRecording().toImage((cell.width * 2 * k).round(), (cell.height * 3 * k).round());
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/${e.name.replaceAll(' ', '_').toLowerCase()}.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
  });
}
