library;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_colors_light.dart';

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.background,
    required this.backgroundElevated,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHigh,
    required this.border,
    required this.primary,
    required this.primaryLight,
    required this.gold,
    required this.silver,
    required this.bronze,
    required this.error,
    required this.errorContainer,
    required this.success,
    required this.successContainer,
    required this.tintStrength,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.onPrimary,
    required this.backgroundGradient,
    required this.primaryGradient,
    required this.goldGradient,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  final Brightness brightness;
  final Color background;
  final Color backgroundElevated;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHigh;
  final Color border;
  final Color primary;
  final Color primaryLight;
  final Color gold;
  final Color silver;
  final Color bronze;
  final Color error;
  final Color errorContainer;
  final Color success;
  final Color successContainer;

  /// Alpha for a brand-color wash (e.g. a match card's corner glow) —
  /// deliberately weaker in light mode, where the same alpha reads far more
  /// saturated against a light surface than it does in dark mode.
  final double tintStrength;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color onPrimary;
  final Gradient backgroundGradient;
  final Gradient primaryGradient;
  final Gradient goldGradient;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;
  final Color skeletonBase;
  final Color skeletonHighlight;

  bool get isDark => brightness == Brightness.dark;

  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    background: AppColors.background,
    backgroundElevated: AppColors.backgroundElevated,
    surface: AppColors.surface,
    surfaceElevated: AppColors.surfaceElevated,
    surfaceHigh: AppColors.surfaceHigh,
    border: AppColors.border,
    primary: AppColors.primary,
    primaryLight: AppColors.primaryLight,
    gold: AppColors.gold,
    silver: AppColors.silver,
    bronze: AppColors.bronze,
    error: AppColors.error,
    errorContainer: AppColors.errorContainer,
    success: AppColors.success,
    successContainer: AppColors.successContainer,
    tintStrength: 0.14,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    onPrimary: AppColors.onPrimary,
    backgroundGradient: AppColors.backgroundGradient,
    primaryGradient: AppColors.primaryGradient,
    goldGradient: AppColors.goldGradient,
    shadowSm: [
      BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4)),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x59000000),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
    ],
    shadowLg: [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 40,
        offset: Offset(0, 18),
      ),
    ],
    skeletonBase: AppColors.surfaceElevated,
    skeletonHighlight: AppColors.surfaceHigh,
  );

  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    background: AppColorsLight.background,
    backgroundElevated: AppColorsLight.backgroundElevated,
    surface: AppColorsLight.surface,
    surfaceElevated: AppColorsLight.surfaceElevated,
    surfaceHigh: AppColorsLight.surfaceHigh,
    border: AppColorsLight.border,
    primary: AppColorsLight.primary,
    primaryLight: AppColorsLight.primaryLight,
    gold: AppColorsLight.gold,
    silver: AppColorsLight.silver,
    bronze: AppColorsLight.bronze,
    error: AppColorsLight.error,
    errorContainer: AppColorsLight.errorContainer,
    success: AppColorsLight.success,
    successContainer: AppColorsLight.successContainer,
    tintStrength: 0.07,
    textPrimary: AppColorsLight.textPrimary,
    textSecondary: AppColorsLight.textSecondary,
    textMuted: AppColorsLight.textMuted,
    onPrimary: AppColorsLight.onPrimary,
    backgroundGradient: AppColorsLight.backgroundGradient,
    primaryGradient: AppColorsLight.primaryGradient,
    goldGradient: AppColorsLight.goldGradient,
    shadowSm: [
      BoxShadow(color: Color(0x14101A28), blurRadius: 12, offset: Offset(0, 4)),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x1F101A28),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
    ],
    shadowLg: [
      BoxShadow(
        color: Color(0x29101A28),
        blurRadius: 40,
        offset: Offset(0, 18),
      ),
    ],
    skeletonBase: AppColorsLight.surfaceElevated,
    skeletonHighlight: AppColorsLight.surfaceHigh,
  );

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? background,
    Color? backgroundElevated,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHigh,
    Color? border,
    Color? primary,
    Color? primaryLight,
    Color? gold,
    Color? silver,
    Color? bronze,
    Color? error,
    Color? errorContainer,
    Color? success,
    Color? successContainer,
    double? tintStrength,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? onPrimary,
    Gradient? backgroundGradient,
    Gradient? primaryGradient,
    Gradient? goldGradient,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
    List<BoxShadow>? shadowLg,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      backgroundElevated: backgroundElevated ?? this.backgroundElevated,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      gold: gold ?? this.gold,
      silver: silver ?? this.silver,
      bronze: bronze ?? this.bronze,
      error: error ?? this.error,
      errorContainer: errorContainer ?? this.errorContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      tintStrength: tintStrength ?? this.tintStrength,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      onPrimary: onPrimary ?? this.onPrimary,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      goldGradient: goldGradient ?? this.goldGradient,
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
      shadowLg: shadowLg ?? this.shadowLg,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    );
  }

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      backgroundElevated: Color.lerp(
        backgroundElevated,
        other.backgroundElevated,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      silver: Color.lerp(silver, other.silver, t)!,
      bronze: Color.lerp(bronze, other.bronze, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      tintStrength: tintStrength + (other.tintStrength - tintStrength) * t,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      backgroundGradient: t < 0.5
          ? backgroundGradient
          : other.backgroundGradient,
      primaryGradient: t < 0.5 ? primaryGradient : other.primaryGradient,
      goldGradient: t < 0.5 ? goldGradient : other.goldGradient,
      shadowSm: t < 0.5 ? shadowSm : other.shadowSm,
      shadowMd: t < 0.5 ? shadowMd : other.shadowMd,
      shadowLg: t < 0.5 ? shadowLg : other.shadowLg,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(
        skeletonHighlight,
        other.skeletonHighlight,
        t,
      )!,
    );
  }
}

extension BuildContextTokens on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.dark;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}
