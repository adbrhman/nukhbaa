/// The small menu button beside a player's name (script 225).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design/app_sizes.dart';
import '../../core/design/app_tokens.dart';
import 'player_actions.dart';

/// Opens the report / block menu of the player called [displayName].
class PlayerMenuButton extends StatelessWidget {
  /// Creates the button; [participantId] keeps it apart from its neighbours.
  const PlayerMenuButton({
    super.key,
    required this.displayName,
    required this.participantId,
    this.size = 20,
  });

  /// The player's own name, not the label shown for a blocked one.
  final String displayName;

  /// The player's participant id in the season shown.
  final String participantId;

  /// The icon's size.
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key('player.menu.$participantId'),
      tooltip: 'الإبلاغ أو الحظر',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTouchTarget,
        minHeight: AppSizes.minTouchTarget,
      ),
      iconSize: size,
      visualDensity: VisualDensity.standard,
      icon: Icon(Icons.more_vert_rounded, color: context.tokens.textMuted),
      onPressed: () => unawaited(
        showPlayerActions(
          context,
          displayName: displayName,
          participantId: participantId,
        ),
      ),
    );
  }
}
