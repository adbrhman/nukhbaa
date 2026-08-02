library;

import 'package:flutter/material.dart';
import 'app_colors.dart';
import '../design/app_colors_light.dart';
import '../design/app_radius.dart';
import '../design/app_tokens.dart';
import '../design/app_typography.dart';

abstract final class AppTheme {
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        tokens: AppTokens.dark,
        scheme: const ColorScheme.dark(
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: AppColors.primaryDark,
          onPrimaryContainer: AppColors.textPrimary,
          secondary: AppColors.gold,
          onSecondary: AppColors.onGold,
          secondaryContainer: AppColors.goldDark,
          onSecondaryContainer: AppColors.textPrimary,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.surfaceElevated,
          onSurfaceVariant: AppColors.textSecondary,
          error: AppColors.error,
          onError: AppColors.onError,
          errorContainer: AppColors.errorContainer,
          onErrorContainer: AppColors.textPrimary,
          outline: AppColors.textMuted,
          outlineVariant: AppColors.border,
        ),
        scaffold: AppColors.background,
        appBarBg: AppColors.backgroundElevated,
        divider: AppColors.border,
      );

  static ThemeData get light => _build(
        brightness: Brightness.light,
        tokens: AppTokens.light,
        scheme: const ColorScheme.light(
          primary: AppColorsLight.primary,
          onPrimary: AppColorsLight.onPrimary,
          primaryContainer: AppColorsLight.primaryDark,
          onPrimaryContainer: AppColorsLight.onPrimary,
          secondary: AppColorsLight.gold,
          onSecondary: AppColorsLight.onGold,
          secondaryContainer: AppColorsLight.goldDark,
          onSecondaryContainer: AppColorsLight.onPrimary,
          surface: AppColorsLight.surface,
          onSurface: AppColorsLight.textPrimary,
          surfaceContainerHighest: AppColorsLight.surfaceElevated,
          onSurfaceVariant: AppColorsLight.textSecondary,
          error: AppColorsLight.error,
          onError: AppColorsLight.onError,
          errorContainer: AppColorsLight.errorContainer,
          onErrorContainer: AppColorsLight.textPrimary,
          outline: AppColorsLight.textMuted,
          outlineVariant: AppColorsLight.border,
        ),
        scaffold: AppColorsLight.background,
        appBarBg: AppColorsLight.backgroundElevated,
        divider: AppColorsLight.border,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppTokens tokens,
    required ColorScheme scheme,
    required Color scaffold,
    required Color appBarBg,
    required Color divider,
  }) {
    final TextTheme textTheme = AppTypography.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamily: AppTypography.fontFamily,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      dividerColor: divider,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: tokens.border),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceElevated,
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brXl,
          side: BorderSide(color: tokens.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXxl),
        titleTextStyle: textTheme.headlineSmall?.copyWith(color: tokens.textPrimary),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tokens.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
    );
  }
}
