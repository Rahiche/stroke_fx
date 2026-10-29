// Draws each demo text's strokes and the joints found in them, to check by
// eye: joins green, touches blue, crossings red.
//   OUT=/some/dir flutter test tool/joints_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/src/joints.dart';
import 'package:stroke_fx/src/written.dart';

void main() {
  testWidgets('joints', (tester) async {
    await tester.runAsync(() async {
      final out = Platform.environment['OUT'] ?? 'build/joints';
      Directory(out).createSync(recursive: true);
      for (final (name, text, hand) in [
        ('latin', 'Stroke by stroke', homemadeApple),
        ('japanese', '手書きの日本語', notoSansJapanese),
        ('arabic', 'بالقلم والحبر', notoNaskhArabic),
      ]) {
        final w = WrittenText(text, hand: hand, fontSize: 150, maxWidth: 1500);
        final joints = findJoints(w.strokes, w.xHeight);
        final counts = <JointKind, int>{};
        for (final j in joints) {
          counts[j.kind] = (counts[j.kind] ?? 0) + 1;
        }
        print('$name: ${w.strokes.length} strokes, ${joints.length} joints $counts');
        final size = Size(w.size.width + 40, w.size.height + 40);
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
        c.translate(size.width / 2 - w.bounds.center.dx, size.height / 2 - w.bounds.center.dy);
        for (final s in w.strokes) {
          final hue = s.index / w.strokes.length * 300;
          final ink = HSVColor.fromAHSV(1, hue, 0.15, 0.7).toColor();
          for (var i = 0; i < s.points.length; i++) {
            c.drawCircle(s.points[i], s.halfWidths[i], Paint()..color = ink);
          }
        }
        for (final j in joints) {
          final col = switch (j.kind) {
            JointKind.join => const Color(0xFF10A040),
            JointKind.touch => const Color(0xFF2050E0),
            JointKind.cross => const Color(0xFFE02020),
          };
          c.drawCircle(j.position, math.max(5, j.size * 1.2), Paint()
            ..color = col
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
        }
        final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
  });
}
