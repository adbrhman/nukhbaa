library;

import 'package:flutter/material.dart';

enum FormFactor { mobile, tablet, desktop }

abstract final class AppBreakpoints {
  static const double tablet = 600;
  static const double desktop = 1024;

  static FormFactor of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static FormFactor fromWidth(double width) {
    if (width >= desktop) return FormFactor.desktop;
    if (width >= tablet) return FormFactor.tablet;
    return FormFactor.mobile;
  }

  static bool isMobile(BuildContext c) => of(c) == FormFactor.mobile;
  static bool isTabletUp(BuildContext c) => of(c) != FormFactor.mobile;
  static bool isDesktop(BuildContext c) => of(c) == FormFactor.desktop;

  static T select<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    switch (of(context)) {
      case FormFactor.desktop:
        return desktop ?? tablet ?? mobile;
      case FormFactor.tablet:
        return tablet ?? mobile;
      case FormFactor.mobile:
        return mobile;
    }
  }
}
