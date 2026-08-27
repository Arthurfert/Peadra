import 'package:flutter/material.dart';

enum ScreenSize { phone, tablet, desktop }

class ResponsiveLayout extends StatelessWidget {
  final Widget phone;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.phone,
    this.tablet,
    required this.desktop,
  });

  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return ScreenSize.phone;
    if (width < 900) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  static bool isPhone(BuildContext context) =>
      getScreenSize(context) == ScreenSize.phone;
  static bool isTablet(BuildContext context) =>
      getScreenSize(context) == ScreenSize.tablet;
  static bool isDesktop(BuildContext context) =>
      getScreenSize(context) == ScreenSize.desktop;

  static EdgeInsets pagePadding(BuildContext context) {
    final h = isPhone(context) ? 12.0 : 24.0;
    return EdgeInsets.symmetric(horizontal: h);
  }

  static EdgeInsets pagePaddingAll(BuildContext context) {
    final s = isPhone(context) ? 12.0 : 24.0;
    return EdgeInsets.all(s);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return phone;
        } else if (constraints.maxWidth < 900) {
          return tablet ?? desktop;
        }
        return desktop;
      },
    );
  }
}
