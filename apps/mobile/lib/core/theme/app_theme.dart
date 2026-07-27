library;
import 'package:flutter/material.dart';
import 'app_colors.dart';
abstract final class AppTheme {
  static ThemeData get dark {
      const ColorScheme scheme = ColorScheme.dark(
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
                                                                                                                      );
                                                                                                                          return ThemeData(
                                                                                                                                useMaterial3: true,
                                                                                                                                      brightness: Brightness.dark,
                                                                                                                                            colorScheme: scheme,
                                                                                                                                                  scaffoldBackgroundColor: AppColors.background,
                                                                                                                                                        canvasColor: AppColors.background,
                                                                                                                                                              dividerColor: AppColors.border,
                                                                                                                                                                    appBarTheme: const AppBarTheme(
                                                                                                                                                                            backgroundColor: AppColors.backgroundElevated,
                                                                                                                                                                                    foregroundColor: AppColors.textPrimary,
                                                                                                                                                                                            elevation: 0,
                                                                                                                                                                                                    centerTitle: true,
                                                                                                                                                                                                          ),
                                                                                                                                                                                                                filledButtonTheme: FilledButtonThemeData(
                                                                                                                                                                                                                        style: FilledButton.styleFrom(
                                                                                                                                                                                                                                  backgroundColor: AppColors.primary,
                                                                                                                                                                                                                                            foregroundColor: AppColors.onPrimary,
                                                                                                                                                                                                                                                      minimumSize: const Size.fromHeight(52),
                                                                                                                                                                                                                                                                shape: RoundedRectangleBorder(
                                                                                                                                                                                                                                                                            borderRadius: BorderRadius.circular(14),
                                                                                                                                                                                                                                                                                      ),
                                                                                                                                                                                                                                                                                              ),
                                                                                                                                                                                                                                                                                                    ),
                                                                                                                                                                                                                                                                                                          progressIndicatorTheme: const ProgressIndicatorThemeData(
                                                                                                                                                                                                                                                                                                                  color: AppColors.primary,
                                                                                                                                                                                                                                                                                                                        ),
                                                                                                                                                                                                                                                                                                                            );
                                                                                                                                                                                                                                                                                                                              }
                                                                                                                                                                                                                                                                                                                              }