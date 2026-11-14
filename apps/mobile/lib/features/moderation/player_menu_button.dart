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
    this.shownName,
  });

  /// The player's own name, not the label shown for a blocked one.
  final String displayName;

  /// The player's participant id in the season shown.
  final String participantId;

  /// The icon's size.
  final double size;

  /// The name on screen (a blocked player's label): read after the
  /// button's name, so each menu of a list reads its own player
  /// (Accessibility Scanner, script 272). Null reads [displayName].
  final String? shownName;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key('player.menu.$participantId'),
      tooltip: 'الإبلاغ أو الحظر: ${shownName ?? displayName}',
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
