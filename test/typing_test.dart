import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/stroke_fx.dart';

void main() {
  // Typing more leaves what's written as it was: the same strokes, in the
  // same places, at the same times.
  for (final (before, after, hand) in [
    ('Stroke', 'Stroke by stroke', homemadeApple),
    ('手書き', '手書きの日本語', notoSansJapanese),
    ('بال', 'بالقلم والحبر', notoNaskhArabic),
  ]) {
    test('typing on keeps what was written: $after', () {
      final typed = [for (var i = 0; i < after.length; i++) i * 0.3];
      final a = WrittenText(before, hand: hand, fontSize: 96, typing: true, typedAt: typed.sublist(0, before.length));
      final b = WrittenText(after, hand: hand, fontSize: 96, typing: true, typedAt: typed);
      expect(b.strokes.length, greaterThan(a.strokes.length));
      // (Arabic: the last letter typed takes its joined form once another
      // follows, so its strokes may change.)
      final keep = isRightToLeft(after)
          ? a.strokes.where((s) => s.character < before.length - 1).length
          : a.strokes.length;
      for (var i = 0; i < keep; i++) {
        expect(b.strokes[i].points, a.strokes[i].points, reason: 'stroke $i moved');
        expect(b.strokes[i].times, a.strokes[i].times, reason: 'stroke $i retimed');
      }
      // And nothing is written before it's typed.
      for (final s in b.strokes) {
        final line = after.split('\n')[s.line];
        expect(s.start, greaterThanOrEqualTo(typed[s.character.clamp(0, line.length - 1)] - 1e-9));
      }
    });
  }
}
