library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_breakpoints.dart';
import '../../../../core/design/app_radius.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/time/riyadh_day_turnover.dart';
import '../../../../core/ui/forward_chevron.dart';
import '../../../fixture_prediction/widgets/live_matches_chip.dart';
import '../../admin_providers.dart';
import '../../admin_sections.dart';
import '../../widgets/admin_month_card.dart';
import '../../widgets/admin_ui_kit.dart';

/// الرئيسية (2026-10-07): ما يحتاج قراراً الآن، ثم مباريات اليوم، ثم نبض
/// اللعبة، ثم آخر الإجراءات بجمل مقروءة.
///
/// كل رقم من API حقيقي. عدد اللاعبين من `GET /admin/user-stats` (تجميع
/// `COUNT(*)` على كل `identity.users`، لا صفحة `GET /admin/users`
/// المحدودة)، ولاعبو الأسبوع من `GET /admin/retention`، والدعوات المحجوزة
/// والأخطاء الجديدة من [adminAttentionProvider]. كل مصدر يفشل وحده: يظهر
/// «تعذّر التحقق» مكانه بدل صفر غير صحيح، وتعمل بقية الصفحة.
///
/// «اليوم» هو يوم الرياض، يوم التطبيق في كل مكان (الهجرة 0076).
class AdminHomeSection extends ConsumerWidget {
  const AdminHomeSection({super.key, required this.onNavigate, this.now});

  final ValueChanged<AdminSection> onNavigate;

  /// The clock; null reads the real time. Tests pass a fixed one.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminDashboardProvider);

    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(adminAttentionProvider);
        ref.invalidate(adminMonthPulseProvider);
        ref.invalidate(adminRetentionProvider);
        return ref.refresh(adminDashboardProvider.future);
      },
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
              detail: 'تعذر تحميل أحد مصادر لوحة التحكم',
            ),
          ],
        ),
        data: (snapshot) => _HomeContent(
          snapshot: snapshot,
          now: (now ?? DateTime.now)(),
          onNavigate: onNavigate,
        ),
      ),
    );
  }
}

DateTime? _kickoff(CurrentMonthFixtureItemDto item) {
  final String? raw = item.fixture.kickoffAt;
  return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
}

bool _hasResult(CurrentMonthFixtureItemDto item) =>
    item.resultHomeGoals != null && item.resultAwayGoals != null;

/// Whether [item] is over at [now]: reported finished by the live feed, or
/// past [liveWindow] -- the same estimate the players' cards use.
bool _isOver(CurrentMonthFixtureItemDto item, DateTime now) {
  if (item.liveFinished ?? false) return true;
  final DateTime? kickoff = _kickoff(item);
  if (kickoff == null) return false;
  return now.toUtc().difference(kickoff) >= liveWindow;
}

/// The month's fixtures that are over at [now] with no result recorded.
/// A test fixture is left out: it is never scored by design (migration
/// 0098), so it would wait forever. Hidden ones never reach this feed.
List<CurrentMonthFixtureItemDto> fixturesAwaitingResult(
  List<CurrentMonthFixtureItemDto> items,
  DateTime now,
) {
  return <CurrentMonthFixtureItemDto>[
    for (final CurrentMonthFixtureItemDto item in items)
      if (!item.fixture.isTest && _isOver(item, now) && !_hasResult(item)) item,
  ];
}

/// The fixtures kicking off on [now]'s Riyadh day, earliest first.
List<CurrentMonthFixtureItemDto> riyadhTodayFixtures(
  List<CurrentMonthFixtureItemDto> items,
  DateTime now,
) {
  final DateTime today = RiyadhDayTurnover.riyadhDayOf(now);
  final List<(DateTime, CurrentMonthFixtureItemDto)> keyed =
      <(DateTime, CurrentMonthFixtureItemDto)>[];
  for (final CurrentMonthFixtureItemDto item in items) {
    final DateTime? kickoff = _kickoff(item);
    // Real matches only: a test fixture is the admins' own.
    if (kickoff != null &&
        !item.fixture.isTest &&
        RiyadhDayTurnover.riyadhDayOf(kickoff) == today) {
      keyed.add((kickoff, item));
    }
  }
  keyed.sort((a, b) => a.$1.compareTo(b.$1));
  return <CurrentMonthFixtureItemDto>[for (final k in keyed) k.$2];
}

/// Where [item] stands at [now], in words.
String fixturePhaseLabel(CurrentMonthFixtureItemDto item, DateTime now) {
  if (_hasResult(item)) {
    return 'انتهت ${item.resultHomeGoals}-${item.resultAwayGoals}';
  }
  final DateTime? kickoff = _kickoff(item);
  if (kickoff == null) return 'موعد غير محدد';
  if (now.toUtc().isBefore(kickoff)) return 'قادمة';
  if (_isOver(item, now)) return 'بانتظار النتيجة';
  return 'مباشرة';
}

/// An audit action's wire token (`AuditAction.wireValue`, domain) in words.
/// A token this build does not know reads as a plain admin action.
String auditActionLabel(String action) => switch (action) {
  'user_suspended' => 'إيقاف لاعب',
  'user_reinstated' => 'إعادة تفعيل لاعب',
  'user_renamed' => 'تغيير اسم لاعب',
  'participant_ledger_viewed' => 'اطّلاع على سجل نقاط لاعب',
  'user_predictions_viewed' => 'اطّلاع على توقعات لاعب',
  'fixture_result_recorded' => 'تسجيل نتيجة مباراة',
  'fixture_schedule_corrected' => 'تعديل موعد مباراة',
  'fixture_hidden' => 'إخفاء مباراة',
  'fixture_shown' => 'إظهار مباراة',
  'fixture_predictions_viewed' => 'اطّلاع على توقعات مباراة',
  'fixture_linked_to_round' => 'ربط مباراة بجولة',
  'competition_created' => 'إنشاء مسابقة',
  'season_started' => 'بدء موسم',
  'round_opened' => 'فتح جولة',
  'round_locked' => 'إغلاق جولة',
  'round_scored' => 'احتساب جولة',
  'round_posted_to_ledger' => 'ترحيل جولة إلى سجل النقاط',
  'round_predictions_viewed' => 'اطّلاع على توقعات جولة',
  'error_updated' => 'تحديث حالة خطأ',
  _ => 'إجراء إداري',
};

/// One audit entry as a sentence: the action in words, the match's name
/// when the entry points at one of [fixtureNames], and the reason when one
/// was given. Ids never show.
String auditSentence(AuditEntryDto entry, Map<String, String> fixtureNames) {
  final StringBuffer out = StringBuffer(auditActionLabel(entry.action));
  final String? fixture = fixtureNames[entry.targetRef];
  if (fixture != null) out.write(': $fixture');
  final String? reason = entry.reason;
  if (reason != null && reason.isNotEmpty) out.write(' ($reason)');
  return out.toString();
}

String _teams(CurrentMonthFixtureItemDto item) =>
    '${item.fixture.homeTeam ?? 'غير محدد'} × '
    '${item.fixture.awayTeam ?? 'غير محدد'}';

class _HomeContent extends ConsumerWidget {
  const _HomeContent({
    required this.snapshot,
    required this.now,
    required this.onNavigate,
  });

  final AdminDashboardSnapshot snapshot;
  final DateTime now;
  final ValueChanged<AdminSection> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<CurrentMonthFixtureItemDto> fixtures =
        snapshot.currentMonthFixtures;
    return ListView(
      key: const Key('admin.dashboard.scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        _NeedsAttention(
          awaitingResult: fixturesAwaitingResult(fixtures, now).length,
          attention: ref.watch(adminAttentionProvider),
          month: ref.watch(adminMonthPulseProvider),
          onNavigate: onNavigate,
        ),
        const SizedBox(height: AppSpacing.lg),
        _TodayFixtures(
          fixtures: riyadhTodayFixtures(fixtures, now),
          now: now,
          onOpenAll: () => onNavigate(AdminSection.fixtures),
        ),
        const SizedBox(height: AppSpacing.lg),
        AdminMonthCard(
          pulse: ref.watch(adminMonthPulseProvider),
          now: now,
          onOpen: () => onNavigate(AdminSection.champions),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Pulse(
          snapshot: snapshot,
          retention: ref.watch(adminRetentionProvider),
          now: now,
          onNavigate: onNavigate,
        ),
        const SizedBox(height: AppSpacing.lg),
        _RecentActivity(
          entries: snapshot.auditLog.entries,
          fixtureNames: <String, String>{
            for (final CurrentMonthFixtureItemDto item in fixtures)
              item.fixture.fixtureId: _teams(item),
          },
          onOpenAll: () => onNavigate(AdminSection.audit),
        ),
      ],
    );
  }
}

/// «يحتاج تدخلك»: one row per thing waiting, each opening its section; a
/// calm line when nothing waits; a plain «تعذّر التحقق» for a source that
/// could not be read.
class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({
    required this.awaitingResult,
    required this.attention,
    required this.month,
    required this.onNavigate,
  });

  final int awaitingResult;
  final AsyncValue<AdminAttention> attention;
  final AsyncValue<AdminMonthPulse> month;
  final ValueChanged<AdminSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final List<Widget> rows = <Widget>[];
    final List<String> unchecked = <String>[];
    bool loading = false;

    if (awaitingResult > 0) {
      rows.add(
        _AttentionRow(
          key: const Key('admin.dashboard.attention.results'),
          icon: Icons.scoreboard_rounded,
          label: 'مباريات انتهت بلا نتيجة',
          count: awaitingResult,
          onTap: () => onNavigate(AdminSection.resultsScoring),
        ),
      );
    }
    switch (month) {
      case AsyncData<AdminMonthPulse>(:final value):
        if (value.uncrowned.isNotEmpty) {
          rows.add(
            _AttentionRow(
              key: const Key('admin.dashboard.attention.crowning'),
              icon: Icons.emoji_events_rounded,
              label: 'أشهر انتهت بلا تتويج',
              count: value.uncrowned.length,
              onTap: () => onNavigate(AdminSection.champions),
            ),
          );
        }
      case AsyncError<AdminMonthPulse>():
        unchecked.add('التتويج');
      default:
        loading = true;
    }
    switch (attention) {
      case AsyncData<AdminAttention>(:final value):
        final int? held = value.heldReferrals;
        if (held == null) {
          unchecked.add('الدعوات');
        } else if (held > 0) {
          rows.add(
            _AttentionRow(
              key: const Key('admin.dashboard.attention.referrals'),
              icon: Icons.group_add_rounded,
              label: 'دعوات محجوزة للمراجعة',
              count: held,
              onTap: () => onNavigate(AdminSection.referrals),
            ),
          );
        }
        final int? fresh = value.freshErrors;
        if (fresh == null) {
          unchecked.add('الأخطاء');
        } else if (fresh > 0) {
          rows.add(
            _AttentionRow(
              key: const Key('admin.dashboard.attention.errors'),
              icon: Icons.bug_report_rounded,
              label: 'أخطاء جديدة',
              count: fresh,
              onTap: () => onNavigate(AdminSection.errorLog),
            ),
          );
        }
      case AsyncError<AdminAttention>():
        unchecked.addAll(<String>['الدعوات', 'الأخطاء']);
      default:
        loading = true;
    }

    return AdminCard(
      key: const Key('admin.dashboard.attention'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSectionHeader(title: 'يحتاج تدخلك'),
          ...rows,
          if (loading) const LinearProgressIndicator(),
          if (rows.isEmpty && unchecked.isEmpty && !loading)
            Row(
              key: const Key('admin.dashboard.attention.clear'),
              children: [
                Icon(Icons.check_circle_rounded, color: t.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'لا شيء ينتظرك الآن',
                    style: context.text.bodyMedium?.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          if (unchecked.isNotEmpty)
            Padding(
              key: const Key('admin.dashboard.attention.unchecked'),
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: t.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'تعذّر التحقق من ${unchecked.join(' و')}',
                      style: context.text.bodyMedium?.copyWith(
                        color: t.textSecondary,
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

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // A ListTile paints its ink on the nearest Material; the card's own
    // background would hide it, so the tile gets a Material of its own.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: t.gold),
        title: Text(
          label,
          style: context.text.bodyMedium?.copyWith(color: t.textPrimary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: context.text.titleMedium?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            ForwardChevron(color: t.textSecondary),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// A text button that opens a section: the label, then the forward chevron
/// (left in Arabic, see [ForwardChevron]).
///
/// [buttonKey] is on the button itself, not on the full-width [Align]
/// around it: a tap at the Align's centre lands on empty card.
class _OpenButton extends StatelessWidget {
  const _OpenButton({
    required this.buttonKey,
    required this.label,
    required this.onTap,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton(
        key: buttonKey,
        style: TextButton.styleFrom(foregroundColor: t.primaryText),
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flexible: at large text sizes the label wraps instead of
            // pushing the chevron past the card's edge.
            Flexible(child: Text(label)),
            const SizedBox(width: AppSpacing.xs),
            ForwardChevron(color: t.primaryText, size: 18),
          ],
        ),
      ),
    );
  }
}

/// «مباريات اليوم»: the Riyadh day's matches, each with its kickoff in the
/// reader's time and where it stands.
class _TodayFixtures extends StatelessWidget {
  const _TodayFixtures({
    required this.fixtures,
    required this.now,
    required this.onOpenAll,
  });

  final List<CurrentMonthFixtureItemDto> fixtures;
  final DateTime now;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AdminCard(
      key: const Key('admin.dashboard.today'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSectionHeader(title: 'مباريات اليوم'),
          if (fixtures.isEmpty)
            const AdminEmptyState(
              icon: Icons.sports_soccer_outlined,
              title: 'لا مباريات اليوم',
            )
          else
            for (final CurrentMonthFixtureItemDto item in fixtures)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: Key('admin.dashboard.today.${item.fixture.fixtureId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sports_soccer_rounded, color: t.primary),
                  title: Text(
                    _teams(item),
                    style: context.text.bodyMedium?.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '${_kickoffText(context, item)} · '
                    '${fixturePhaseLabel(item, now)}',
                    style: context.text.bodySmall?.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ),
          _OpenButton(
            buttonKey: const Key('admin.dashboard.today.all'),
            label: 'كل المباريات',
            onTap: onOpenAll,
          ),
        ],
      ),
    );
  }

  static String _kickoffText(
    BuildContext context,
    CurrentMonthFixtureItemDto item,
  ) {
    final String? raw = item.fixture.kickoffAt;
    return raw == null ? 'موعد غير محدد' : formatKickoffTime(context, raw);
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
  final String value;
  final IconData icon;
  final Color color;
  final AdminSection section;
}

/// «نبض اللعبة»: four numbers, each opening where it comes from.
class _Pulse extends StatelessWidget {
  const _Pulse({
    required this.snapshot,
    required this.retention,
    required this.now,
    required this.onNavigate,
  });

  final AdminDashboardSnapshot snapshot;
  final AsyncValue<AdminRetentionDto> retention;
  final DateTime now;
  final ValueChanged<AdminSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final isMobile = AppBreakpoints.isMobile(context);
    final t = context.tokens;
    final String thisWeek = switch (retention) {
      AsyncData<AdminRetentionDto>(:final value) =>
        value.weeks.isEmpty ? '0' : '${value.weeks.first.activeUsers}',
      _ => '—',
    };
    final int upcoming = snapshot.currentMonthFixtures.where((item) {
      final DateTime? kickoff = _kickoff(item);
      // Test fixtures are not matches left to play.
      return kickoff != null &&
          !item.fixture.isTest &&
          kickoff.isAfter(now.toUtc());
    }).length;
    final cards = <_MetricData>[
      _MetricData(
        label: 'إجمالي اللاعبين',
        value: '${snapshot.totalUsers}',
        icon: Icons.people_alt_rounded,
        color: t.primary,
        section: AdminSection.users,
      ),
      _MetricData(
        label: 'لعبوا هذا الأسبوع',
        value: thisWeek,
        icon: Icons.insights_rounded,
        color: t.gold,
        section: AdminSection.analytics,
      ),
      _MetricData(
        label: 'موقوفون',
        value: '${snapshot.suspendedUsers}',
        icon: Icons.block_rounded,
        color: t.error,
        section: AdminSection.users,
      ),
      _MetricData(
        label: 'مباريات متبقية هذا الشهر',
        value: '$upcoming',
        icon: Icons.schedule_rounded,
        color: t.primary,
        section: AdminSection.fixtures,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminSectionHeader(title: 'نبض اللعبة'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = isMobile
                ? 2
                : constraints.maxWidth >= 1100
                ? 4
                : 2;
            final double width =
                (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                columns;
            // Rows of cards as tall as their tallest content: the cards keep
            // the grid's shape at normal text size and grow with larger text
            // instead of overflowing a fixed aspect ratio (UI-34).
            final double minHeight = width / (isMobile ? 1.25 : 1.8);
            return Column(
              key: const Key('admin.dashboard.metrics'),
              children: [
                for (int start = 0; start < cards.length; start += columns) ...[
                  if (start > 0) const SizedBox(height: AppSpacing.md),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = start; i < start + columns; i++) ...[
                          if (i > start) const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: i < cards.length
                                ? ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: minHeight,
                                    ),
                                    child: _MetricCard(
                                      data: cards[i],
                                      onTap: () => onNavigate(cards[i].section),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
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
      borderRadius: AppRadius.brCard,
      onTap: onTap,
      child: AdminCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, color: data.color, size: 22),
            const Spacer(),
            Text(
              data.value,
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
              style: context.text.labelMedium?.copyWith(color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// «آخر الإجراءات»: the newest five, each a sentence with its time.
class _RecentActivity extends StatelessWidget {
  const _RecentActivity({
    required this.entries,
    required this.fixtureNames,
    required this.onOpenAll,
  });

  final List<AuditEntryDto> entries;
  final Map<String, String> fixtureNames;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AdminCard(
      key: const Key('admin.dashboard.activity'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSectionHeader(title: 'آخر الإجراءات'),
          if (entries.isEmpty)
            const AdminEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'لا توجد إجراءات مسجلة',
            )
          else
            for (final AuditEntryDto entry in entries.take(5))
              Padding(
                key: Key('admin.dashboard.activity.${entry.id}'),
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.history_rounded, size: 18, color: t.gold),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auditSentence(entry, fixtureNames),
                            style: context.text.bodySmall?.copyWith(
                              color: t.textPrimary,
                            ),
                          ),
                          Text(
                            formatTimestamp(context, entry.occurredAt),
                            style: context.text.labelSmall?.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          _OpenButton(
            buttonKey: const Key('admin.dashboard.activity.all'),
            label: 'السجل كاملاً',
            onTap: onOpenAll,
          ),
        ],
      ),
    );
  }
}
