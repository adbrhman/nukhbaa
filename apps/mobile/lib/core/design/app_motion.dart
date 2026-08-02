library;

import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const Duration instant  = Duration(milliseconds: 100);
  static const Duration fast     = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration slow     = Duration(milliseconds: 420);
  static const Duration lazy     = Duration(milliseconds: 600);

  static const Curve emphasized    = Curves.easeInOutCubicEmphasized;
  static const Curve emphasizedIn  = Curves.easeInCubic;
  static const Curve emphasizedOut = Curves.easeOutCubic;
  static const Duration shimmer  = Duration(milliseconds: 1400);

  static const Curve standardCurve = Curves.easeInOut;
}
