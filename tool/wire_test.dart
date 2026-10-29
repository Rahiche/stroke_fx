// Draws one text's stroke mesh big, as the neon effect paints it, with the
// triangles' edges over it: to see where the mesh goes wrong.
//   WIRE=/some/file.png TEXT=の flutter test tool/wire_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/stroke_fx.dart';

void main() {
  testWidgets('wire', (tester) async {
    await tester.runAsync(() async {
      await StrokeShaders.load();
      final word = Platform.environment['TEXT'] ?? 'の';
      final hand = RegExp(r'[　-鿿]').hasMatch(word)
          ? notoSansJapanese
          : (isRightToLeft(word) ? notoNaskhArabic : homemadeApple);
      final text = await StrokeText.of(WrittenText(word, hand: hand, fontSize: 96, duration: 3));
      const size = Size(900, 700);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final effect = Neon();
      StrokeFxPainter(text: text, effect: effect, time: ValueNotifier(text.duration + 1)).paint(c, size);
      final k = StrokeFxPainter.fit(text, size), b = text.writing.bounds;
      c.translate(size.width / 2, size.height / 2);
      c.scale(k);
      c.translate(-b.center.dx, -b.center.dy);
      final mesh = text.mesh(effect.halo(text.writing.xHeight), k);
      final p = mesh.positions, idx = mesh.indices;
      final line = Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 0.6 / k
        ..style = PaintingStyle.stroke;
      final uv = mesh.textureCoordinates;
      for (var i = 0; i + 2 < idx.length; i += 3) {
        final a = Offset(p[idx[i] * 2], p[idx[i] * 2 + 1]),
            bb = Offset(p[idx[i + 1] * 2], p[idx[i + 1] * 2 + 1]),
            cc = Offset(p[idx[i + 2] * 2], p[idx[i + 2] * 2 + 1]);
        c.drawPath(Path()..addPolygon([a, bb, cc], true), line);
        // (Turned over against stroke space: red.)
        double area(List<double> v) {
          final x = idx[i] * 2, y = idx[i + 1] * 2, z = idx[i + 2] * 2;
          return (v[y] - v[x]) * (v[z + 1] - v[x + 1]) - (v[z] - v[x]) * (v[y + 1] - v[x + 1]);
        }

        final sa = area(p), ta = area(uv);
        if (sa.abs() > 1e-3 && ta.abs() > 1e-3 && sa.sign != ta.sign) {
          c.drawPath(Path()..addPolygon([a, bb, cc], true), Paint()..color = const Color(0xCCFF2020));
        }
      }
      // The centre lines, and their points (every other one).
      for (final s in text.strokes) {
        c.drawPoints(ui.PointMode.polygon, s.points, Paint()
          ..color = const Color(0xFFFFE04A)
          ..strokeWidth = 1.2 / k);
        for (var i = 0; i < s.points.length; i += 2) {
          c.drawCircle(s.points[i], 1.6 / k, Paint()..color = const Color(0xFFFFE04A));
        }
      }
      final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(Platform.environment['WIRE'] ?? 'build/wire.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
