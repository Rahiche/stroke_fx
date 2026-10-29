// How far Jelly moves the text, over time, for tuning: the furthest any of
// the sheet has moved (in x-heights) every quarter second.
//   flutter test tool/jelly_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/stroke_fx.dart';

void main() {
  testWidgets('jelly', (tester) async {
    await tester.runAsync(() async {
      for (final (text, hand) in [('Stroke by stroke', homemadeApple), ('手書きの日本語', notoSansJapanese)]) {
        final t = await StrokeText.of(WrittenText(text, hand: hand, fontSize: 96, duration: 5));
        final jelly = Jelly(), xh = t.writing.xHeight, out = <String>[];
        for (var f = 0; f <= 8 * 30; f++) {
          final d = jelly.furthest(t, f / 30);
          if (f % 8 == 0) out.add((d / xh).toStringAsFixed(3));
        }
        // ignore: avoid_print
        print('$text (writing ${t.duration.toStringAsFixed(1)} s): ${out.join(' ')}');
      }
    });
  });
}
