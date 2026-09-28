/// The admin dashboard's view of retention: do players come back
/// (migration 0069, `GET /admin/retention`).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../admin_providers.dart';
import 'admin_ui_kit.dart';

/// Width of one figure column in the two tables.
const double _cellWidth = 66;

/// Width of the week column.
const double _weekWidth = 58;

/// Retention at a glance, then per week and per cohort.
///
/// The three headline figures: players active this week (still counting),
/// the share of last week's players active on three days or more, and the
/// share back on the seventh day after their first. Below, each week's
/// players, the share on three days or more -- all, and inside the weekly
/// league -- and the share of league seats held the next week; then, by the
/// week of their first active day, who was back on day 1, 7, 14 and in
/// week 4. A horizon counts only the players it has had time to judge; a
/// dash means nobody yet.
class AdminRetentionCard extends ConsumerWidget {
  /// Creates the card.
  const AdminRetentionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final AsyncValue<AdminRetentionDto> stats = ref.watch(
      adminRetentionProvider,
    );
    return AdminCard(
      key: const Key('admin.retention'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.autorenew_rounded, color: t.primaryText),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'هل يعود اللاعبون؟',
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          switch (stats) {
            AsyncData(:final value) => _Body(stats: value),
            AsyncError() => Text(
              'تعذّر تحميل أرقام الاحتفاظ',
              key: const Key('admin.retention.error'),
              style: context.text.bodySmall?.copyWith(color: t.error),
            ),
            _ => const LinearProgressIndicator(),
          },
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats});

  final AdminRetentionDto stats;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final TextStyle? muted = context.text.bodySmall?.copyWith(
      color: t.textMuted,
    );
    final bool quiet =
        stats.weeks.every((w) => w.activeUsers == 0) &&
        stats.cohorts.every((c) => c.users == 0);
    if (quiet) {
      return Text(
        'لا نشاط مسجّل في آخر ${stats.weeks.length} أسابيع بعد.',
        key: const Key('admin.retention.empty'),
        style: muted,
      );
    }

    final RetentionWeekDto? thisWeek = stats.weeks.isEmpty
        ? null
        : stats.weeks.first;
    RetentionWeekDto? lastWeek;
    for (final RetentionWeekDto w in stats.weeks) {
      if (w.complete) {
        lastWeek = w;
        break;
      }
    }
    int day7Eligible = 0;
    int day7Retained = 0;
    for (final RetentionCohortDto c in stats.cohorts) {
      day7Eligible += c.day7.eligible;
      day7Retained += c.day7.retained;
    }
    final RetentionRateDto day7 = RetentionRateDto(
      eligible: day7Eligible,
      retained: day7Retained,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _Headline(
              valueKey: const Key('admin.retention.thisWeek'),
              value: '${thisWeek?.activeUsers ?? 0}',
              label: 'نشطون هذا الأسبوع',
              color: t.primaryText,
            ),
            _Headline(
              valueKey: const Key('admin.retention.threePlus'),
              value: _percent(lastWeek?.active3PlusPercent),
              label: 'نشطوا 3 أيام+ الأسبوع الماضي',
              color: t.gold,
            ),
            _Headline(
              valueKey: const Key('admin.retention.day7'),
              value: _percent(day7.percent),
              label: 'عادوا في اليوم السابع',
              color: t.success,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _TableTitle('كل أسبوع'),
        _Grid(
          header: const [
            'الأسبوع',
            'نشطون',
            '3 أيام+',
            '3+ بالدوري',
            'بقوا بالدوري',
          ],
          rows: [
            for (final RetentionWeekDto w in stats.weeks)
              _GridRow(
                week: w.weekStart,
                current: !w.complete,
                cells: [
                  _Cell(
                    key: Key('admin.retention.week.${w.weekStart}.active'),
                    value: '${w.activeUsers}',
                  ),
                  _Cell(
                    key: Key('admin.retention.week.${w.weekStart}.threePlus'),
                    value: _percent(w.active3PlusPercent),
                  ),
                  _Cell(
                    key: Key('admin.retention.week.${w.weekStart}.league'),
                    value: _percent(w.league3PlusPercent),
                    detail: w.leagueActive == 0
                        ? null
                        : _percent(w.others3PlusPercent),
                  ),
                  _Cell(
                    key: Key('admin.retention.week.${w.weekStart}.returned'),
                    value: _percent(w.leagueRetentionPercent),
                    detail: w.leagueReturned == null
                        ? null
                        : _count(w.leagueReturned!, w.leagueMembers),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _TableTitle('حسب أسبوع أول نشاط'),
        _Grid(
          header: const [
            'الأسبوع',
            'لاعبون',
            'يوم 1',
            'يوم 7',
            'يوم 14',
            'أسبوع 4',
          ],
          rows: [
            for (final RetentionCohortDto c in stats.cohorts)
              _GridRow(
                week: c.weekStart,
                current: c.weekStart == thisWeek?.weekStart,
                cells: [
                  _Cell(
                    key: Key('admin.retention.cohort.${c.weekStart}.users'),
                    value: '${c.users}',
                  ),
                  _rate('${c.weekStart}.day1', c.day1),
                  _rate('${c.weekStart}.day7', c.day7),
                  _rate('${c.weekStart}.day14', c.day14),
                  _rate('${c.weekStart}.week4', c.week4),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'النشاط: أي حدث لعب في اليوم بتوقيت الرياض، والأسبوع يبدأ الاثنين. '
          'تحت «3+ بالدوري» نسبة غير المشاركين في الدوري للمقارنة. '
          'لا تُحسب النسبة إلا لمن انقضى عليه اليوم المطلوب؛ «—» تعني لا أحد '
          'بعد. «بقوا بالدوري» تظهر بعد انتهاء الأسبوع التالي.',
          key: const Key('admin.retention.note'),
          style: muted,
        ),
      ],
    );
  }

  static _Cell _rate(String id, RetentionRateDto rate) => _Cell(
    key: Key('admin.retention.cohort.$id'),
    value: _percent(rate.percent),
    detail: rate.eligible == 0 ? null : _count(rate.retained, rate.eligible),
  );
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.valueKey,
    required this.value,
    required this.label,
    required this.color,
  });

  final Key valueKey;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            key: valueKey,
            style: context.text.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TableTitle extends StatelessWidget {
  const _TableTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: context.text.labelLarge?.copyWith(
          color: t.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Cell {
  const _Cell({required this.key, required this.value, this.detail});

  final Key key;
  final String value;
  final String? detail;
}

class _GridRow {
  const _GridRow({
    required this.week,
    required this.current,
    required this.cells,
  });

  final String week;
  final bool current;
  final List<_Cell> cells;
}

/// A small table that scrolls sideways on a narrow screen: the week, then
/// one fixed-width column per figure.
class _Grid extends StatelessWidget {
  const _Grid({required this.header, required this.rows});

  final List<String> header;
  final List<_GridRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final TextStyle? head = context.text.labelSmall?.copyWith(
      color: t.textMuted,
      fontWeight: FontWeight.w700,
    );
    final TextStyle? figure = context.text.labelMedium?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final TextStyle? small = context.text.labelSmall?.copyWith(
      color: t.textMuted,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(_cellWidth),
        columnWidths: const {0: FixedColumnWidth(_weekWidth)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            children: [
              for (final String h in header)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(h, style: head),
                ),
            ],
          ),
          for (final _GridRow row in rows)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_ltr(_shortDay(row.week)), style: figure),
                      if (row.current) Text('جارٍ', style: small),
                    ],
                  ),
                ),
                for (final _Cell cell in row.cells)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cell.value, key: cell.key, style: figure),
                        if (cell.detail != null)
                          Text(cell.detail!, style: small),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Wraps [text] in a left-to-right isolate (U+2066 ... U+2069), so a figure
/// with its unit keeps its order inside an Arabic layout.
String _ltr(String text) => '\u2066$text\u2069';

/// A share as the card writes it, or a dash when nobody can be judged yet.
String _percent(int? value) => value == null ? '—' : _ltr('$value%');

/// "3/12": how many of how many.
String _count(int part, int whole) => _ltr('$part/$whole');

/// `2026-09-21` as `21/9`.
String _shortDay(String isoDay) {
  final DateTime? d = DateTime.tryParse(isoDay);
  return d == null ? isoDay : '${d.day}/${d.month}';
}
