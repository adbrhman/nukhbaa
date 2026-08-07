library;

import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration lazy = Duration(milliseconds: 600);

  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve emphasizedIn = Curves.easeInCubic;
  static const Curve emphasizedOut = Curves.easeOutCubic;
  static const Duration shimmer = Duration(milliseconds: 1400);

  static const Curve standardCurve = Curves.easeInOut;
  // ── Named durations for specific interaction types (additive aliases —
  // prefer these where the interaction matches, otherwise use the
  // generic scale above). Values follow the design addendum §5.5.
  static const Duration micro = Duration(milliseconds: 100);
  static const Duration bottomSheetIn = Duration(milliseconds: 320);
  static const Duration bottomSheetOut = Duration(milliseconds: 220);
  static const Duration dialog = Duration(milliseconds: 200);
  static const Duration snackbarMotion = Duration(milliseconds: 250);
  static const Duration tabSwitch = Duration(milliseconds: 150);
}
