import 'package:flutter/material.dart';

enum ScreenSize { phone, tablet, desktop }

class ResponsiveLayout {
  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return ScreenSize.phone;
    if (width < 900) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  static bool isPhone(BuildContext context) =>
      getScreenSize(context) == ScreenSize.phone;

  static EdgeInsets pagePaddingAll(BuildContext context) {
    final s = isPhone(context) ? 12.0 : 24.0;
    return EdgeInsets.all(s);
  }
}
