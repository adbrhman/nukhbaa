// ignore_for_file: unused_result
library;

import '../../../../core/design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../fixture_prediction/current_month_fixtures_providers.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_ui_kit.dart';

/// Admin read-only view of fixtures that already produced a non-empty
/// per-fixture score projection in the current month.
class AdminCountedFixturesSection extends ConsumerWidget {
  const AdminCountedFixturesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(adminCountedFixturesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSectionHeader(
          title: l10n.adminCountedFixturesTab,
          subtitle: l10n.adminCountedFixturesSubtitle,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(currentMonthFixturesProvider);
              await ref.refresh(adminCountedFixturesProvider.future);
            },
            child: state.when(
              loading: () => ListView(
                physics: AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 280,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
              error: (error, _) {
                final appError = error is AppError
                    ? error
                    : const AppError.transient(
                        'client.unexpected',
                        'Something went wrong. Please try again.',
                      );
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  children: [
                    AdminErrorBanner(
                      message: ErrorPresenter.message(appError),
                      debugDetail: 'تعذر تحميل المباريات المحتسبة',
                    ),
                  ],
                );
              },
              data: (fixtures) {
                if (fixtures.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      AdminEmptyState(
                        icon: Icons.fact_check_outlined,
                        title: l10n.adminCountedFixturesEmpty,
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  itemCount: fixtures.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final counted = fixtures[index];
                    final fixture = counted.item.fixture;
                    final home = fixture.homeTeam ?? '—';
                    final away = fixture.awayTeam ?? '—';
                    final kickoff = _formatKickoff(fixture.kickoffAt);
                    return AdminCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.tokens.primary.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.check_circle_outline_rounded,
                              color: context.tokens.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$home × $away',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.titleSmall?.copyWith(
                                    color: context.tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${fixture.leagueName ?? counted.item.competitionName} • $kickoff',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(
                                    color: context.tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            l10n.adminCountedLabel,
                            style: context.text.labelMedium?.copyWith(
                              color: context.tokens.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

String _formatKickoff(String? raw) {
  final date = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  if (date == null) return '—';
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day}/${date.month} • $hour:$minute';
}
