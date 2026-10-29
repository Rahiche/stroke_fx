/// Effects that live along the strokes of written text, and on the joints
/// where strokes meet: a fragment shader that knows, for every pixel, which
/// stroke it's on, how far along and across, and when the pen was there.
///
/// Built on fountain_pen's strokes (Latin, Japanese, Arabic).
library;

export 'src/effects.dart';
export 'src/joints.dart' show Joint, JointKind, findJoints;
export 'src/space.dart';
export 'src/view.dart';
export 'src/written.dart' show WrittenStroke, WrittenText;
