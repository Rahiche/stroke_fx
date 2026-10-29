import 'package:stroke_fx/stroke_fx.dart';

/// Capturing frames needs a file system: native only.
Future<void> capture(
        String spec, List<StrokeText> texts, List<String> scripts, List<StrokeEffect> effects, double hold) =>
    throw UnsupportedError('CAPTURE runs on macOS, not the web');

void quit() {}
