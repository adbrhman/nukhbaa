library;

import 'package:flutter/material.dart';

abstract final class AppColorsLight {
  static const Color background         = Color(0xFFF4F6FA);
  static const Color backgroundElevated = Color(0xFFFFFFFF);
  static const Color surface            = Color(0xFFFFFFFF);
  static const Color surfaceElevated    = Color(0xFFF0F2F7);
  static const Color surfaceHigh        = Color(0xFFE4E8F0);
  static const Color primary            = Color(0xFF0BAD75);
  static const Color primaryDark        = Color(0xFF08895C);
  static const Color primaryLight       = Color(0xFF12D18E);
  static const Color gold               = Color(0xFFD4930A);
  static const Color goldDark           = Color(0xFFAA7508);
  static const Color silver             = Color(0xFF6B7A8D);
  static const Color bronze             = Color(0xFF9B5E1E);
  static const Color error              = Color(0xFFD32F2F);
  static const Color errorContainer     = Color(0xFFFFEBEE);
  static const Color textPrimary        = Color(0xFF0D1B2A);
  static const Color textSecondary      = Color(0xFF3D5166);
  static const Color textMuted          = Color(0xFF7A92A8);
  static const Color onPrimary          = Color(0xFFFFFFFF);
  static const Color onGold             = Color(0xFFFFFFFF);
  static const Color onError            = Color(0xFFFFFFFF);
  static const Color border             = Color(0x1A0D1B2A);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundElevated, background],
  );
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary],
  );
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gold, goldDark],
  );
}
