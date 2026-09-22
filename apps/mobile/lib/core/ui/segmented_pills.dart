library;

import 'package:flutter/material.dart';

import '../design/app_motion.dart';
import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

/// A row of equal-width pill tabs -- one filled with the action colour, the
/// rest quiet. Used where a screen switches between a few views of the same
/// data (the leaderboard's month / day / season, the predictions filter).
///
/// Purely presentational: the caller owns the selection.
class SegmentedPills extends StatelessWidget {
  /// Creates the pills for [labels], [selectedIndex] filled.
  const SegmentedPills({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.keyPrefix,
    super.key,
  });

  /// One label per pill, in reading order.
  final List<String> labels;

  /// The filled pill.
  final int selectedIndex;

  /// Called with the tapped pill's index.
  final ValueChanged<int> onSelected;

  /// When set, each pill is keyed `'$keyPrefix.$index'`.
  final String? keyPrefix;

  static const double _height = 42;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Row(
      children: <Widget>[
        for (int index = 0; index < labels.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _Pill(
              key: keyPrefix == null ? null : Key('$keyPrefix.$index'),
              label: labels[index],
              selected: index == selectedIndex,
              tokens: tokens,
              onTap: () => onSelected(index),
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final AppTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brButton,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            height: SegmentedPills._height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? tokens.primary : tokens.surfaceElevated,
              borderRadius: AppRadius.brButton,
              border: Border.all(
                color: selected ? tokens.primary : tokens.controlBorder,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? tokens.onPrimary : tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
