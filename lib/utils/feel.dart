import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The three haptic strengths BeauTap uses. Keep them for meaningful
/// moments (a selection, a success, a warning), never for every tap or
/// scroll. On the web, Android Chrome turns these into short vibrations;
/// iPhone browsers ignore them.
class Haptics {
  /// Switching tabs, picking a chip, a date or a time.
  static void light() => HapticFeedback.selectionClick();

  /// Confirming: booking sent, request accepted, favourite saved.
  static void firm() => HapticFeedback.mediumImpact();

  /// Cancelling, deleting, or something went wrong.
  static void warn() => HapticFeedback.heavyImpact();
}

/// Standard animation timings, so the app moves with one rhythm.
class Motion {
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 350);
  static const curve = Cubic(0.22, 0.8, 0.3, 1);

  /// True when the phone asks for less motion: animate with a plain fade
  /// or not at all.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when the phone asks for less motion.
  static Duration of(BuildContext context, [Duration d = normal]) => reduced(context) ? Duration.zero : d;
}
