import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/src/written.dart';

void main() {
  // The stand-in lays text out exactly as fountain_pen does: the pen is in
  // the same place at every moment.
  for (final (text, hand) in [
    ('Stroke by stroke', homemadeApple),
    ('手書きの日本語', notoSansJapanese),
    ('بالقلم والحبر', notoNaskhArabic),
    ('Two lines\nof ink', homemadeApple),
  ]) {
    test('same strokes as PenWriting: $text', () {
      final ours = WrittenText(text, hand: hand, fontSize: 96, maxWidth: 900, duration: 5);
      final theirs = ours.toPenWriting();
      expect(ours.duration, theirs.duration);
      expect(ours.bounds, theirs.bounds);
      for (var t = 0.0; t <= ours.duration + 0.1; t += 0.013) {
        expect(ours.tip(t), theirs.tip(t), reason: 't=$t');
      }
      expect(ours.strokes, isNotEmpty);
      for (final s in ours.strokes) {
        expect(s.points.length, s.times.length);
        expect(s.halfWidths.length, s.points.length);
        for (var i = 1; i < s.times.length; i++) {
          expect(s.times[i], greaterThanOrEqualTo(s.times[i - 1]));
        }
      }
    });
  }
}
