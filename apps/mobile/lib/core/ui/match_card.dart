import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';
import 'forward_chevron.dart';
import 'team_logo.dart';

/// Compact, data-driven fixture card shared by summary surfaces.
///
/// Team crests are resolved data the caller already has (per
/// `team_logo.dart`'s doc: `core/ui` never imports a `features/` lookup
/// table itself) — pass `homeCrestUrl`/`awayCrestUrl` from the resolved
/// `football_data.teams` catalog (or leave them `null` for the neutral
/// initials fallback [TeamLogo] already renders, never a blank space).
class MatchCard extends StatelessWidget {
  const MatchCard({
    required this.competition,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.onTap,
    this.homeCrestUrl,
    this.awayCrestUrl,
    super.key,
  });

  final String competition;
  final String? homeTeam;
  final String? awayTeam;
  final String? kickoffAt;
  final String? homeCrestUrl;
  final String? awayCrestUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final kickoff = kickoffAt == null
        ? 'لم يُحدد الموعد'
        : _formatKickoff(kickoffAt!);
    return Material(
      color: tokens.surface,
      borderRadius: AppRadius.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brMd,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brMd,
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 48,
                height: 32,
                child: Stack(
                  children: <Widget>[
                    // Both crests are positioned DIRECTIONALLY now. The away
                    // one used to be `Positioned(left: 16)` while the home one
                    // was unpositioned -- and an unpositioned Stack child sits
                    // at `AlignmentDirectional.topStart`, which under Arabic is
                    // the RIGHT edge, i.e. the very pixels `left: 16` was
                    // already using. The two circles landed on top of each
                    // other, so every card in the app showed one crest where
                    // there should have been two.
                    //
                    // The away crest is listed first so the home one draws over
                    // it: home is the team read first in the title beside it.
                    PositionedDirectional(
                      start: 16,
                      child: _Crest(name: awayTeam, crestUrl: awayCrestUrl),
                    ),
                    PositionedDirectional(
                      start: 0,
                      child: _Crest(name: homeTeam, crestUrl: homeCrestUrl),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      competition,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${awayTeam ?? 'لم يُحدد'}  ×  ${homeTeam ?? 'لم يُحدد'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Kickoff and chevron sit on ONE line rather than stacked. Two
              // short lines made the card tall enough to open a band of empty
              // space across its middle -- the thing users kept pointing at.
              Text(
                kickoff,
                style: TextStyle(
                  color: tokens.primaryLight,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ForwardChevron(color: tokens.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  String _formatKickoff(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// One crest in the overlapped pair, ringed in the card's own colour so two
/// circles that overlap by more than half still read as two.
class _Crest extends StatelessWidget {
  const _Crest({required this.name, required this.crestUrl});

  final String? name;
  final String? crestUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.tokens.surface,
      ),
      child: TeamLogo(displayName: name ?? '؟', crestUrl: crestUrl, size: 28),
    );
  }
}
