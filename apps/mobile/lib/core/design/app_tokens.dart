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
    required this.controlBorder,
    required this.primary,
    required this.primaryLight,
    required this.primaryText,
    required this.gold,
    required this.silver,
    required this.bronze,
    required this.error,
    required this.errorContainer,
    required this.success,
    required this.successContainer,
    required this.successText,
    required this.errorText,
    required this.errorFill,
    required this.onSuccess,
    required this.onGold,
    required this.tintStrength,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.onPrimary,
    required this.backgroundGradient,
    required this.primaryGradient,
    required this.goldGradient,
    required this.actionGradient,
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
  final Color controlBorder;
  final Color primary;
  final Color primaryLight;

  /// Blue for text, figures and links: AA (4.5:1) on every surface and blue
  /// wash of its theme, which [primary] -- a fill colour -- is not.
  final Color primaryText;
  final Color gold;
  final Color silver;
  final Color bronze;
  final Color error;
  final Color errorContainer;
  final Color success;
  final Color successContainer;

  /// Green for text: AA (4.5:1) on every surface, its container and the blue
  /// viewer row -- [success] is a fill and an icon colour.
  final Color successText;

  /// Red for text, likewise; [error] stays the fill and icon colour.
  final Color errorText;

  /// Red under white text (the unread badge): 5.4:1 in both themes.
  final Color errorFill;

  /// Content on a [success] fill (the saved check).
  final Color onSuccess;

  /// Content on a [gold] fill (the day strip's relative badge).
  final Color onGold;

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

  /// The gradient behind white text (4.5:1 or better across it);
  /// [primaryGradient] is decorative.
  final Gradient actionGradient;
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
    controlBorder: AppColors.textMuted,
    primary: AppColors.primary,
    primaryLight: AppColors.primaryLight,
    primaryText: AppColors.primaryText,
    gold: AppColors.gold,
    silver: AppColors.silver,
    bronze: AppColors.bronze,
    error: AppColors.error,
    errorContainer: AppColors.errorContainer,
    success: AppColors.success,
    successContainer: AppColors.successContainer,
    successText: AppColors.success,
    errorText: AppColors.errorText,
    errorFill: AppColors.errorFill,
    onSuccess: AppColors.onSuccess,
    onGold: AppColors.onGold,
    tintStrength: 0.14,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    onPrimary: AppColors.onPrimary,
    backgroundGradient: AppColors.backgroundGradient,
    primaryGradient: AppColors.primaryGradient,
    goldGradient: AppColors.goldGradient,
    actionGradient: AppColors.actionGradient,
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
    controlBorder: AppColorsLight.textMuted,
    primary: AppColorsLight.primary,
    primaryLight: AppColorsLight.primaryLight,
    primaryText: AppColorsLight.primary,
    gold: AppColorsLight.gold,
    silver: AppColorsLight.silver,
    bronze: AppColorsLight.bronze,
    error: AppColorsLight.error,
    errorContainer: AppColorsLight.errorContainer,
    success: AppColorsLight.success,
    successContainer: AppColorsLight.successContainer,
    successText: AppColorsLight.successText,
    errorText: AppColorsLight.errorText,
    errorFill: AppColorsLight.error,
    onSuccess: AppColorsLight.onSuccess,
    onGold: AppColorsLight.onGold,
    tintStrength: 0.07,
    textPrimary: AppColorsLight.textPrimary,
    textSecondary: AppColorsLight.textSecondary,
    textMuted: AppColorsLight.textMuted,
    onPrimary: AppColorsLight.onPrimary,
    backgroundGradient: AppColorsLight.backgroundGradient,
    primaryGradient: AppColorsLight.primaryGradient,
    goldGradient: AppColorsLight.goldGradient,
    actionGradient: AppColorsLight.actionGradient,
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
    Color? controlBorder,
    Color? primary,
    Color? primaryLight,
    Color? primaryText,
    Color? gold,
    Color? silver,
    Color? bronze,
    Color? error,
    Color? errorContainer,
    Color? success,
    Color? successContainer,
    Color? successText,
    Color? errorText,
    Color? errorFill,
    Color? onSuccess,
    Color? onGold,
    double? tintStrength,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? onPrimary,
    Gradient? backgroundGradient,
    Gradient? primaryGradient,
    Gradient? goldGradient,
    Gradient? actionGradient,
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
      controlBorder: controlBorder ?? this.controlBorder,
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      primaryText: primaryText ?? this.primaryText,
      gold: gold ?? this.gold,
      silver: silver ?? this.silver,
      bronze: bronze ?? this.bronze,
      error: error ?? this.error,
      errorContainer: errorContainer ?? this.errorContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      successText: successText ?? this.successText,
      errorText: errorText ?? this.errorText,
      errorFill: errorFill ?? this.errorFill,
      onSuccess: onSuccess ?? this.onSuccess,
      onGold: onGold ?? this.onGold,
      tintStrength: tintStrength ?? this.tintStrength,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      onPrimary: onPrimary ?? this.onPrimary,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      goldGradient: goldGradient ?? this.goldGradient,
      actionGradient: actionGradient ?? this.actionGradient,
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
      controlBorder: Color.lerp(controlBorder, other.controlBorder, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
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
      successText: Color.lerp(successText, other.successText, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      errorFill: Color.lerp(errorFill, other.errorFill, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      onGold: Color.lerp(onGold, other.onGold, t)!,
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
      actionGradient: t < 0.5 ? actionGradient : other.actionGradient,
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
