library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/forward_chevron.dart';
import '../../competition/month_label.dart';
import '../admin_providers.dart';
import 'admin_ui_kit.dart';

/// How long the month has left at [now], in words: «بقي 12 يوماً». A part
/// of a day counts as a day.
String monthTimeLeft(DateTime endAt, DateTime now) {
  final Duration left = endAt.toUtc().difference(now.toUtc());
  if (left <= Duration.zero) return 'انتهى الشهر';
  final int days = (left.inMinutes / Duration.minutesPerDay).ceil();
  if (days <= 1) return 'بقي يوم واحد';
  if (days == 2) return 'بقي يومان';
  if (days <= 10) return 'بقي $days أيام';
  return 'بقي $days يوماً';
}

/// [points] with the Arabic count noun: «نقطة»، «نقطتان»، «5 نقاط».
String pointsLabel(int points) {
  if (points == 2) return 'نقطتان';
  if (points >= 3 && points <= 10) return '$points نقاط';
  return '$points نقطة';
}

/// «مسابقة الشهر» on the admin home (2026-10-08): the running month, the
/// time it has left and the top of its live board, opening «الترتيب
/// والأبطال». Its data is [adminMonthPulseProvider].
class AdminMonthCard extends StatelessWidget {
  const AdminMonthCard({
    super.key,
    required this.pulse,
    required this.now,
    required this.onOpen,
  });

  final AsyncValue<AdminMonthPulse> pulse;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final List<Widget> body = switch (pulse) {
      AsyncData<AdminMonthPulse>(:final value) => _body(value),
      AsyncError<AdminMonthPulse>() => <Widget>[
        const AdminSectionHeader(title: 'مسابقة الشهر'),
        _Note(
          key: const Key('admin.dashboard.month.error'),
          icon: Icons.error_outline_rounded,
          color: t.error,
          text: 'تعذّر تحميل ترتيب الشهر',
        ),
      ],
      _ => const <Widget>[
        AdminSectionHeader(title: 'مسابقة الشهر'),
        LinearProgressIndicator(),
      ],
    };
    return AdminCard(
      key: const Key('admin.dashboard.month'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...body,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('admin.dashboard.month.open'),
              style: TextButton.styleFrom(foregroundColor: t.primaryText),
              onPressed: onOpen,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Flexible(child: Text('الترتيب والتتويج')),
                  const SizedBox(width: AppSpacing.xs),
                  ForwardChevron(color: t.primaryText, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(AdminMonthPulse value) {
    final SeasonDto? month = value.current;
    if (month == null) {
      return const <Widget>[
        AdminSectionHeader(title: 'مسابقة الشهر'),
        _Note(
          key: Key('admin.dashboard.month.none'),
          icon: Icons.event_busy_rounded,
          text: 'لا مسابقة جارية الآن',
        ),
      ];
    }
    final List<ChampionCandidateDto> top =
        value.board?.candidates ?? const <ChampionCandidateDto>[];
    return <Widget>[
      AdminSectionHeader(
        title: 'مسابقة ${monthLabelFromStored(month.label)}',
        subtitle: monthTimeLeft(month.endAt, now),
      ),
      if (top.isEmpty)
        const _Note(
          key: Key('admin.dashboard.month.empty'),
          icon: Icons.hourglass_empty_rounded,
          text: 'لا نقاط بعد هذا الشهر',
        )
      else
        for (final ChampionCandidateDto line in top) _BoardLine(line: line),
    ];
  }
}

class _BoardLine extends StatelessWidget {
  const _BoardLine({required this.line});

  final ChampionCandidateDto line;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bool first = line.rank == 1;
    return Padding(
      key: Key('admin.dashboard.month.line.${line.userId}'),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${line.rank}',
            style: context.text.titleSmall?.copyWith(
              color: first ? t.gold : t.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.displayName,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: first ? FontWeight.w700 : null,
                  ),
                ),
                Text(
                  'نتائج دقيقة: ${line.exactCount}',
                  style: context.text.labelSmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            pointsLabel(line.points),
            style: context.text.bodyMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Icon(icon, color: color ?? t.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: context.text.bodyMedium?.copyWith(color: t.textSecondary),
          ),
        ),
      ],
    );
  }
}
