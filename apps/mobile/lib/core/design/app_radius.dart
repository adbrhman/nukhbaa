library;

import 'package:flutter/material.dart';

abstract final class AppRadius {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 14;
  static const double lg  = 18;
  static const double xl  = 24;
  static const double xxl = 32;

  static const BorderRadius brXs  = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm  = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd  = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg  = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl  = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brXxl = BorderRadius.all(Radius.circular(xxl));
}
