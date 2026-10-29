import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/stroke_fx.dart';

void main() {
  // A fold: a triangle turned over on screen against the way it runs in
  // stroke space. Folds are what showed as rays and cut lines. Inside a
  // tight bend the strip's inner edge meets the line's middle, where
  // slivers may turn over; their area must stay negligible (a corner's fan
  // is flat in stroke space: skipped).
  for (final (text, hand) in [
    ('Stroke by stroke', homemadeApple),
    ('手書きの日本語', notoSansJapanese),
    ('بالقلم والحبر', notoNaskhArabic),
  ]) {
    for (final halo in [2.0, 10.0, 20.0]) {
      testWidgets('no folds: $text, halo $halo', (tester) async {
        await tester.runAsync(() async {
          final t = await StrokeText.of(WrittenText(text, hand: hand, fontSize: 96, duration: 4));
          final m = t.mesh(halo, 2);
          final p = m.positions, uv = m.textureCoordinates, idx = m.indices;
          var folds = 0, triangles = 0, folded = 0.0, total = 0.0;
          for (var i = 0; i + 2 < idx.length; i += 3) {
            double area(List<double> v) {
              final a = idx[i] * 2, b = idx[i + 1] * 2, c = idx[i + 2] * 2;
              return (v[b] - v[a]) * (v[c + 1] - v[a + 1]) - (v[c] - v[a]) * (v[b + 1] - v[a + 1]);
            }

            final screen = area(p), space = area(uv);
            if (screen.abs() < 1e-3 || space.abs() < 1e-3) continue;
            triangles++;
            total += screen.abs();
            if (screen.sign != space.sign) {
              folds++;
              folded += screen.abs();
            }
          }
          expect(triangles, greaterThan(100));
          expect(folded / total, lessThan(0.015),
              reason: '$folds folds in $triangles triangles, ${(folded / total * 100).toStringAsFixed(3)}% of the area');
          // ignore: avoid_print
          print('$text halo $halo: $folds of $triangles turned over, ${(folded / total * 100).toStringAsFixed(4)}% of the area');
        });
      });
    }
  }
}
