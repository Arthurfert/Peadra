import 'dart:math' as math;
import 'dart:ui' show ViewPadding;

import 'package:flutter/material.dart';

/// Physical insets of the screen: the status bar at the top and the
/// navigation bar (3-button navigation) at the bottom.
///
/// Read from the [View] rather than from [MediaQuery], because a bottom
/// sheet route strips the top padding from the [MediaQuery] it hands to the
/// sheet (see `showModalBottomSheet`, which removes the top padding so a
/// [SafeArea] inside the sheet does not double-count it).
ViewPadding physicalPadding(BuildContext context) =>
    View.of(context).viewPadding;

/// Bottom inset that keeps content clear of the phone's bottom system bar.
///
/// Phones with 3-button navigation reserve a strip at the bottom of the
/// screen (and phones with gesture navigation a smaller one). Sheets and
/// dialogs must reserve that strip, otherwise their actions end up under
/// the system bar and are hard to reach.
///
/// The value is the tallest of:
/// - the physical navigation bar;
/// - the on-screen keyboard, which covers the system bar when it is shown.
///
/// [MediaQueryData.padding] is deliberately not used: it is the system bar
/// minus the keyboard, so it collapses to 0 as soon as the keyboard opens.
double bottomSafeInset(BuildContext context) {
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  return math.max(physicalPadding(context).bottom, keyboard);
}

/// Top inset of the phone (status bar / display cutout).
double topSafeInset(BuildContext context) => physicalPadding(context).top;

/// Maximum height a bottom sheet may take.
///
/// Sheets are anchored to the bottom of the screen, so a short one never
/// reaches the status bar. A tall one (a long form, a long list) would
/// otherwise slide under the status bar, hiding its header. Capping the
/// height keeps the sheet below the status bar and lets its content
/// scroll instead.
double maxSheetHeight(BuildContext context) {
  final screenHeight = MediaQuery.sizeOf(context).height;
  return math.max(0, screenHeight - topSafeInset(context));
}
