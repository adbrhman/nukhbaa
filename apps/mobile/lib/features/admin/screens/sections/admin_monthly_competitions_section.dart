library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/competition_providers.dart';
import '../../widgets/admin_ui_kit.dart';

/// قسم "المسابقات الشهرية" في لوحة الأدمن (خطة قسم 9).
///
/// الدفعة الأولى: عرض قراءة فقط — قائمة المسابقات العامة
/// (`competitionListProvider`) وحالة الموسم الحالي لكل واحدة
/// (`currentSeasonProvider`، `GET /competitions/{id}/seasons/current`).
/// لا Create ولا Start Season بعد — تُضافان في دفعات لاحقة منفصلة.
class AdminMonthlyCompetitionsSection extends ConsumerWidget {
  const AdminMonthlyCompetitionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<CompetitionDto>> state = ref.watch(
      competitionListProvider,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(title: l10n.adminMonthlyCompetitionsTab),
        switch (state) {
          AsyncData<List<CompetitionDto>>(:final value) when value.isEmpty =>
            AdminEmptyState(
              icon: Icons.calendar_month_rounded,
              title: l10n.adminMonthlyCompetitionsEmpty,
            ),
          AsyncData<List<CompetitionDto>>(:final value) => AdminCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < value.length; i++) ...[
                  _CompetitionCurrentSeasonRow(competition: value[i]),
                  if (i != value.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          AsyncError(:final error) => AdminErrorBanner(
            message: ErrorPresenter.message(error as AppError),
          ),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}

/// صف مسابقة واحدة + حالة موسمها الحالي (شهر تقويمي).
class _CompetitionCurrentSeasonRow extends ConsumerWidget {
  const _CompetitionCurrentSeasonRow({required this.competition});

  final CompetitionDto competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final AsyncValue<SeasonDto?> seasonState = ref.watch(
      currentSeasonProvider(competition.id),
    );

    final Widget trailing = switch (seasonState) {
      AsyncData<SeasonDto?>(value: final SeasonDto season?) => Text(
        season.label,
        style: context.text.labelMedium?.copyWith(
          color: t.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      AsyncData<SeasonDto?>() => Text(
        l10n.adminMonthlyCompetitionsNoActiveSeason,
        style: context.text.labelSmall?.copyWith(color: t.textMuted),
      ),
      AsyncError() => Icon(Icons.error_outline_rounded, color: t.error, size: 18),
      _ => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };

    return AdminListRow(
      leadingIcon: Icons.emoji_events_outlined,
      leadingColor: t.primary,
      title: competition.name,
      trailing: trailing,
    );
  }
}
