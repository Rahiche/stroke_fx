// Prints each demo text's strokes: how many, how long, how broad.
//   flutter test tool/stats_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:stroke_fx/src/written.dart';

void main() {
  test('stats', () {
    for (final (text, hand, size) in [
      ('Stroke by stroke', homemadeApple, 120.0),
      ('手書きの日本語', notoSansJapanese, 120.0),
      ('بالقلم والحبر', notoNaskhArabic, 150.0),
    ]) {
      final w = WrittenText(text, hand: hand, fontSize: size, maxWidth: 1000);
      final lengths = <double>[];
      var maxHalf = 0.0, flags = <String, int>{};
      for (final s in w.strokes) {
        var l = 0.0;
        for (var i = 1; i < s.points.length; i++) {
          l += (s.points[i] - s.points[i - 1]).distance;
        }
        lengths.add(l);
        maxHalf = math.max(maxHalf, s.halfWidths.reduce(math.max));
        for (final (k, on) in [('dot', s.dot), ('late', s.late), ('lifted', s.lands), ('joined', s.joined)]) {
          if (on) flags[k] = (flags[k] ?? 0) + 1;
        }
      }
      lengths.sort();
      final pts = w.strokes.fold(0, (a, s) => a + s.points.length);
      print('$text: ${w.strokes.length} strokes, $pts points, em ${w.em.toStringAsFixed(1)} xh ${w.xHeight.toStringAsFixed(1)}, '
          'size ${w.size.width.round()}x${w.size.height.round()}, ${w.duration.toStringAsFixed(2)} s; '
          'length min ${lengths.first.round()} median ${lengths[lengths.length ~/ 2].round()} max ${lengths.last.round()} '
          'sum ${lengths.fold(0.0, (a, b) => a + b).round()} px; max half ${maxHalf.toStringAsFixed(1)} px; $flags');
    }
  });
}
