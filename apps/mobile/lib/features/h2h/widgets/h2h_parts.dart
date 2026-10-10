/// Small pieces the head-to-head sections share: a side of a match, a
/// result, a round's phase, and the names the server may leave empty.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_badge.dart';
import '../../../core/ui/user_avatar.dart';
import '../h2h_texts.dart';

/// Whether any round of the month was settled: until then every line of
/// the table is level, and its order (seat time, then id) means nothing to
/// a player, so no rank is shown.
bool h2hAnyPlayed(MyH2hLeagueDto league) =>
    league.standings.any((H2hStandingDto s) => s.played > 0);

/// The caller's line of the table, when the server sent one.
H2hStandingDto? h2hMyStanding(MyH2hLeagueDto league) {
  for (final H2hStandingDto s in league.standings) {
    if (s.isMe) return s;
  }
  return null;
}

/// A member's name, never blank.
String h2hNameOf(String? name) =>
    (name ?? '').trim().isEmpty ? h2hUnnamed : name!.trim();

/// The opponent of [round] in words: a member, or the group average.
String h2hOpponentOf(H2hRoundViewDto round) => round.opponentUserId == null
    ? h2hAverageOpponent
    : h2hNameOf(round.opponentName);

/// The round that matters now: the one being played, else the next one
/// (`open`; a version 1 server's first `upcoming`), else the last one
/// played. Null when the month has no round yet, or only void ones.
H2hRoundViewDto? h2hCurrentRound(MyH2hLeagueDto league) {
  for (final H2hRoundViewDto r in league.rounds) {
    if (r.status == 'live') return r;
  }
  for (final H2hRoundViewDto r in league.rounds) {
    if (r.status == 'open') return r;
  }
  for (final H2hRoundViewDto r in league.rounds) {
    if (r.status == 'upcoming') return r;
  }
  for (final H2hRoundViewDto r in league.rounds.reversed) {
    if (r.status == 'settled') return r;
  }
  return null;
}

/// One side of a match: picture and name, the group average as a group.
class H2hSide extends StatelessWidget {
  /// Creates a side.
  const H2hSide({
    required this.name,
    required this.avatarUrl,
    required this.average,
    this.size = 48,
    super.key,
  });

  /// The name under the picture.
  final String name;

  /// The picture, or null for initials.
  final String? avatarUrl;

  /// Whether this side is the group average.
  final bool average;

  /// The picture's size.
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Column(
      children: <Widget>[
        if (average)
          CircleAvatar(
            radius: size / 2,
            backgroundColor: t.surfaceHigh,
            child: Icon(Icons.groups_rounded, color: t.textSecondary),
          )
        else
          UserAvatar(displayName: name, avatarUrl: avatarUrl, size: size),
        const SizedBox(height: AppSpacing.xs),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.labelLarge?.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A result in words, coloured; a live one says it is so far.
class H2hResultBadge extends StatelessWidget {
  /// Creates the badge.
  const H2hResultBadge({required this.result, required this.live, super.key});

  /// `win`, `draw` or `loss`.
  final String result;

  /// Whether the round is still being played.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final String label = h2hResultLabel(result);
    return AppBadge(
      label: live ? '$label حتى الآن' : label,
      tone: switch (result) {
        'win' => AppBadgeTone.success,
        'loss' => AppBadgeTone.danger,
        _ => AppBadgeTone.neutral,
      },
    );
  }
}

/// A round's phase as a chip.
class H2hStatusChip extends StatelessWidget {
  /// Creates the chip.
  const H2hStatusChip({required this.status, super.key});

  /// The phase the server sent.
  final String status;

  @override
  Widget build(BuildContext context) => AppBadge(
    label: h2hRoundStatusLabel(status),
    tone: switch (status) {
      'open' || 'live' => AppBadgeTone.primary,
      _ => AppBadgeTone.neutral,
    },
    icon: switch (status) {
      'live' => Icons.sports_soccer_rounded,
      'open' => Icons.edit_calendar_rounded,
      'voided' => Icons.block_rounded,
      _ => null,
    },
  );
}

/// A section's heading.
class H2hSectionTitle extends StatelessWidget {
  /// Creates the heading.
  const H2hSectionTitle({required this.text, super.key});

  /// The words.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.text.titleMedium?.copyWith(
      color: context.tokens.textPrimary,
      fontWeight: FontWeight.w800,
    ),
  );
}
