library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_typography.dart';
import '../design/app_motion.dart';
import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

/// A row of equal-width pill tabs -- one filled with the action colour, the
/// rest quiet. Used where a screen switches between a few views of the same
/// data (the leaderboard's month / day / season, the head-to-head views,
/// the predictions filter).
///
/// One rounded track holds the pills (script 161): four outlined buttons in
/// a row read as four actions, where a track reads as one control with one
/// choice made. Each pill keeps the whole track height as its touch target.
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

  /// A full touch target: the pills were 42 (UI-15).
  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      key: const Key('segmentedPills.track'),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brButton,
        border: Border.all(color: tokens.controlBorder),
      ),
      child: Row(
        children: <Widget>[
          for (int index = 0; index < labels.length; index++) ...<Widget>[
            Expanded(
              child: _Pill(
                key: keyPrefix == null ? null : Key('$keyPrefix.$index'),
                label: labels[index],
                selected: index == selectedIndex,
                tokens: tokens,
                onTap: () {
                  // A light tick only when the choice actually changes.
                  if (index != selectedIndex) {
                    unawaited(HapticFeedback.selectionClick());
                  }
                  onSelected(index);
                },
              ),
            ),
          ],
        ],
      ),
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
          child: SizedBox(
            height: SegmentedPills._height,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              margin: const EdgeInsets.all(AppSpacing.xs),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? tokens.primary
                    : tokens.primary.withValues(alpha: 0),
                borderRadius: AppRadius.brSm,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.s14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? tokens.onPrimary : tokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
