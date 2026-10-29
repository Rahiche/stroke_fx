// Prints what stroke space costs for each demo text: building it (layout,
// joints, images), building a mesh, and the image Impeller shades a frame
// (the cells' bounds) at 2 texels to the px.
//   flutter test tool/costs_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/stroke_fx.dart';

void main() {
  testWidgets('costs', (tester) async {
    await tester.runAsync(() async {
      for (final (text, hand) in [
        ('Stroke by stroke', homemadeApple),
        ('手書きの日本語', notoSansJapanese),
        ('بالقلم والحبر', notoNaskhArabic),
      ]) {
        // (Twice: the first run warms the JIT up.)
        late StrokeText t;
        var build = 0, mesh = 0;
        for (var run = 0; run < 2; run++) {
          final w = Stopwatch()..start();
          final writing = WrittenText(text, hand: hand, fontSize: 96, duration: 5);
          t = await StrokeText.of(writing);
          build = w.elapsedMicroseconds;
          w.reset();
          t.mesh(10 + run * 0.001, 2);
          mesh = w.elapsedMicroseconds;
        }
        final xh = t.writing.xHeight;
        final cells = <String>[];
        for (final e in [PlainInk(), Neon(), Frost(), Sakura()]) {
          final m = t.mesh(e.halo(xh), 2);
          final cols = (t.strokes.length / m.rows).ceil();
          cells.add('${e.name} ${(m.cellWidth * cols).round()}x${(m.cellHeight * m.rows).round()} '
              '(${(m.cellWidth * cols * m.cellHeight * m.rows / 1e6).toStringAsFixed(2)} Mpx, '
              '${m.positions.length ~/ 2} vertices)');
        }
        // ignore: avoid_print
        print('$text: ${t.strokes.length} strokes, ${t.joints.length} joints; text ${(build / 1000).toStringAsFixed(1)} ms, '
            'mesh ${(mesh / 1000).toStringAsFixed(1)} ms; ${cells.join('; ')}');
      }
    });
  });
}
