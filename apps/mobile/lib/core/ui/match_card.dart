import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

/// Compact, data-driven fixture card shared by summary surfaces.
class MatchCard extends StatelessWidget {
  const MatchCard({
    required this.competition,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.onTap,
    super.key,
  });

  final String competition;
  final String? homeTeam;
  final String? awayTeam;
  final String? kickoffAt;
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
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.sports_soccer_rounded,
                  color: tokens.primaryLight,
                  size: 20,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    kickoff,
                    style: TextStyle(
                      color: tokens.primaryLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_left_rounded,
                    color: tokens.textMuted,
                    size: 18,
                  ),
                ],
              ),
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