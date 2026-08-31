library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_breakpoints.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../admin_providers.dart';
import '../../admin_sections.dart';
import '../../widgets/admin_ui_kit.dart';

/// مركز التحكم الرئيسي داخل التطبيق نفسه.
///
/// كل رقم هنا ناتج عن API حقيقي موجود أصلًا. لا توجد بيانات تجريبية أو
/// مستودعات بديلة؛ وعندما تكون قراءة المستخدمين محدودة بصفحة الخادم، نوضح
/// ذلك في الواجهة بدل عرض "إجمالي" غير دقيق.
class AdminDashboardSection extends ConsumerWidget {
  const AdminDashboardSection({super.key, required this.onNavigate});

  final ValueChanged<AdminSection> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(adminDashboardProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminDashboardProvider.future),
      child: state.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            AdminErrorBanner(
              message: ErrorPresenter.message(error as AppError),
              debugDetail: 'تعذر تحميل أحد مصادر لوحة التحكم',
            ),
          ],
        ),
        data: (snapshot) => _DashboardContent(
          snapshot: snapshot,
          onNavigate: onNavigate,
          title: l10n.adminDashboardTab,
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.snapshot,
    required this.onNavigate,
    required this.title,
  });

  final AdminDashboardSnapshot snapshot;
  final ValueChanged<AdminSection> onNavigate;
  final String title;

  @override
  Widget build(BuildContext context) {
    final isMobile = AppBreakpoints.isMobile(context);
    final t = context.tokens;
    final cards = <_MetricData>[
      _MetricData(
        label: 'المستخدمون الظاهرون',
        value: snapshot.users.users.length,
        icon: Icons.people_alt_rounded,
        color: t.primary,
        section: AdminSection.users,
      ),
      _MetricData(
        label: 'مستخدمون نشطون',
        value: snapshot.activeUsers,
        icon: Icons.verified_user_rounded,
        color: t.primary,
        section: AdminSection.users,
      ),
      _MetricData(
        label: 'مستخدمون موقوفون',
        value: snapshot.suspendedUsers,
        icon: Icons.block_rounded,
        color: t.error,
        section: AdminSection.users,
      ),
      _MetricData(
        label: 'مباريات اليوم',
        value: snapshot.todayFixtures,
        icon: Icons.today_rounded,
        color: t.gold,
        section: AdminSection.fixtures,
      ),
      _MetricData(
        label: 'المباريات القادمة',
        value: snapshot.upcomingFixtures,
        icon: Icons.schedule_rounded,
        color: t.primary,
        section: AdminSection.fixtures,
      ),
      _MetricData(
        label: 'مسابقات متاحة',
        value: snapshot.competitions.length,
        icon: Icons.emoji_events_rounded,
        color: t.gold,
        section: AdminSection.competitions,
      ),
    ];

    return ListView(
      key: const Key('admin.dashboard.scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        AdminSectionHeader(
          title: title,
          subtitle: 'تشغيل Nukhbaa من نفس البيانات المستخدمة في واجهة المستخدم',
        ),
        AdminCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: t.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.bolt_rounded, color: t.gold),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مركز العمليات',
                      style: context.text.titleSmall?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'المصادر متصلة الآن • '
                      '${snapshot.auditLog.entries.length} إجراءات حديثة محمّلة',
                      style: context.text.bodySmall?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('admin.dashboard.refresh'),
                tooltip: 'تحديث',
                onPressed: () {
                  // RefreshIndicator is the owner of the provider refresh. The
                  // action remains intentionally passive in this pure view.
                },
                icon: Icon(Icons.sync_rounded, color: t.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = isMobile
                ? 2
                : constraints.maxWidth >= 1100
                ? 3
                : 2;
            return GridView.builder(
              key: const Key('admin.dashboard.metrics'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: isMobile ? 1.25 : 1.8,
              ),
              itemBuilder: (context, index) {
                final card = cards[index];
                return _MetricCard(
                  data: card,
                  onTap: () => onNavigate(card.section),
                );
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!isMobile)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _QuickActions(onNavigate: onNavigate)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _RecentActivity(entries: snapshot.auditLog.entries),
              ),
            ],
          )
        else ...[
          _QuickActions(onNavigate: onNavigate),
          const SizedBox(height: AppSpacing.md),
          _RecentActivity(entries: snapshot.auditLog.entries),
        ],
        const SizedBox(height: AppSpacing.md),
        _FixturePreview(
          fixtures: snapshot.currentMonthFixtures,
          onNavigate: () => onNavigate(AdminSection.fixtures),
        ),
      ],
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.section,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final AdminSection section;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data, required this.onTap});

  final _MetricData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      key: Key('admin.dashboard.metric.${data.section.name}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AdminCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, color: data.color, size: 22),
            const Spacer(),
            Text(
              '${data.value}',
              style: context.text.headlineSmall?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              data.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onNavigate});

  final ValueChanged<AdminSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const actions = <(String, IconData, AdminSection)>[
      ('إضافة مباراة', Icons.add_circle_outline_rounded, AdminSection.fixtures),
      ('تسجيل نتيجة', Icons.scoreboard_outlined, AdminSection.resultsScoring),
      (
        'إنشاء مسابقة',
        Icons.emoji_events_outlined,
        AdminSection.monthlyCompetitions,
      ),
      ('إدارة المستخدمين', Icons.person_search_outlined, AdminSection.users),
      (
        'سجل النقاط',
        Icons.account_balance_wallet_outlined,
        AdminSection.ledger,
      ),
      ('سجل التدقيق', Icons.receipt_long_outlined, AdminSection.audit),
    ];

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: 'إجراءات سريعة',
            subtitle: 'انتقل إلى التدفق الحقيقي المناسب دون مغادرة لوحة التحكم',
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (label, icon, section) in actions)
                ActionChip(
                  avatar: Icon(icon, size: 18, color: t.primary),
                  label: Text(label),
                  onPressed: () => onNavigate(section),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.entries});

  final List<AuditEntryDto> entries;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSectionHeader(
            title: 'آخر الإجراءات الإدارية',
            subtitle: 'قراءة مباشرة من سجل التدقيق',
          ),
          if (entries.isEmpty)
            const AdminEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'لا توجد إجراءات مسجلة',
            )
          else
            for (final entry in entries.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 18, color: t.gold),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${entry.action} • ${entry.targetRef}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _FixturePreview extends StatelessWidget {
  const _FixturePreview({required this.fixtures, required this.onNavigate});

  final List<CurrentMonthFixtureItemDto> fixtures;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: AdminSectionHeader(
                  title: 'مباريات الشهر الحالي',
                  subtitle: 'نفس العناصر التي تظهر في شاشة المباريات للمستخدم',
                ),
              ),
              TextButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('إدارة'),
              ),
            ],
          ),
          if (fixtures.isEmpty)
            const AdminEmptyState(
              icon: Icons.sports_soccer_outlined,
              title: 'لا توجد مباريات مرتبطة بالموسم الحالي',
            )
          else
            for (final item in fixtures.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AdminListRow(
                  leadingIcon: Icons.sports_soccer_rounded,
                  leadingColor: t.primary,
                  title:
                      '${item.fixture.homeTeam ?? 'غير محدد'} × '
                      '${item.fixture.awayTeam ?? 'غير محدد'}',
                  trailing: Text(
                    item.fixture.kickoffAt ?? 'موعد غير محدد',
                    style: context.text.labelSmall?.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
