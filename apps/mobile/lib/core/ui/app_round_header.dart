library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../design/app_spacing.dart';

class AppRoundHeader extends StatelessWidget {
  const AppRoundHeader({
    required this.round,
    required this.statusLine,
    this.trailing,
    super.key,
  });

  final RoundDto round;
  final String statusLine;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: scheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Round ${round.sequence}',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(statusLine),
          if (trailing != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}
