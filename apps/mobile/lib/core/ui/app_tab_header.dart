library;

import 'package:flutter/material.dart';

import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

/// The one header the tabs share (UI-20): the tab's name on the start side
/// in one size, its actions on the end side, on the page colour. Home
/// alone carries the wordmark in its place, and the leaderboards draw the
/// name in the page (under the champion's backdrop) in [titleStyle].
///
/// A pushed screen keeps its back button: the header is an [AppBar].
class AppTabHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppTabHeader({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
    this.bottom,
  });

  /// The tab's name.
  final Widget title;

  /// Buttons on the end side.
  final List<Widget> actions;

  /// A strip under the header (the matches' day strip).
  final PreferredSizeWidget? bottom;

  /// The toolbar's height: a 48 touch target with room around it.
  static const double height = 56;

  /// The tab name's style, for a screen that draws its name in the page.
  static TextStyle? titleStyle(BuildContext context) =>
      context.text.headlineSmall?.copyWith(
        color: context.tokens.textPrimary,
        fontWeight: FontWeight.w800,
      );

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return AppBar(
      backgroundColor: tokens.background,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: height,
      titleSpacing: AppSpacing.lg,
      titleTextStyle: titleStyle(context),
      title: title,
      actions: <Widget>[
        ...actions,
        const SizedBox(width: AppSpacing.xs),
      ],
      bottom: bottom,
    );
  }
}
