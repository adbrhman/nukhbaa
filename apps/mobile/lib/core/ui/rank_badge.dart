import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

class RankBadge extends StatelessWidget {
  const RankBadge({required this.rank, super.key});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    return CircleAvatar(
      backgroundColor: medal == null
          ? tokens.surfaceHigh
          : tokens.gold.withValues(alpha: 0.16),
      child: Text(
        medal ?? '$rank',
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: medal == null ? 14 : 18,
        ),
      ),
    );
  }
}
