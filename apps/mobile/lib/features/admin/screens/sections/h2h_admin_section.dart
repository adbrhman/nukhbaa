/// لوحة المشرف لدوري المواجهات (migration 0100): قرعة الشهر، الجولات
/// المعتمدة مع سحب آخرها قبل أن تبدأ، والأيام التي يمكن اعتمادها جولةً،
/// وزر بدء الشهر التجريبي قبل انطلاق الدوري. كل قاعدة على الخادم: هذه
/// الصفحة تعرض ما قرّره وترسل الطلب، ولا تقرّر شيئاً.
///
/// منذ الدفعة 93 هي لوحة الدوري كاملة بخمسة تبويبات: الجولات (هنا)،
/// والمجموعات، ولاعب، والإعدادات، والتقرير والسجل (`h2h_admin_tabs.dart`).
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../../h2h/h2h_texts.dart';
import '../../widgets/admin_ui_kit.dart';
import 'h2h_admin_tabs.dart';

/// `GET /admin/h2h/rounds?day=`: the month containing [day], or the
/// server's current month when it is null.
final adminH2hRoundsProvider = FutureProvider.autoDispose
    .family<H2hRoundsOverviewDto, String?>((ref, day) async {
      return switch (await ref.watch(adminApiProvider).h2hRounds(day: day)) {
        Ok<H2hRoundsOverviewDto>(:final value) => value,
        Err<H2hRoundsOverviewDto>(:final error) => throw error,
      };
    });

/// What the admin reads for a refused action.
String h2hAdminErrorMessage(AppError error) => switch (error.code) {
  'h2h.round_day_started' => 'بدأت مباريات هذا اليوم، فلا يمكن اعتماده.',
  'h2h.round_out_of_order' =>
    'الجولة يجب أن تأتي بعد آخر جولة معتمدة في الشهر.',
  'h2h.round_not_eligible' =>
    'لا يصلح هذا اليوم جولة: مبارياته أقل من 5، أو اكتملت 19 جولة.',
  'h2h.round_day_taken' => 'هذا اليوم جولة معتمدة من قبل.',
  'h2h.round_not_last' => 'لا تُسحب إلا آخر جولة في الشهر.',
  'h2h.round_locked' => 'بدأت هذه الجولة، فلا يمكن سحبها.',
  'h2h.round_unknown' => 'الجولة غير موجودة.',
  'h2h.day_invalid' => 'التاريخ غير صالح.',
  'h2h.pilot_after_launch' => 'التجربة متاحة قبل انطلاق الدوري فقط.',
  'h2h.pilot_already_drawn' => 'أُجريت قرعة هذا الشهر من قبل.',
  'h2h.pilot_too_small' =>
    'أضف لاعبَين اثنين على الأقل إلى التجربة (h2h_pilot) أولاً.',
  'h2h.settings_out_of_range' =>
    'المهلة من 1 إلى 24 ساعة، وأيام النشاط من 1 إلى 28.',
  'h2h.settings_invalid' => 'الإعدادات المرسلة غير مكتملة.',
  'h2h.day_past' => 'مضى هذا اليوم، فلا يمكن تغييره.',
  'h2h.excluded_invalid' => 'اختر الاستبعاد أو الإرجاع.',
  'h2h.month_not_drawn' => 'لم تُجرَ قرعة هذا الشهر بعد.',
  'h2h.month_closed' => 'أُغلق هذا الشهر، فلا يُضاف إليه أحد.',
  'h2h.group_unknown' => 'المجموعة ليست من هذا الشهر.',
  'h2h.seat_outside_group' => 'هذا المقعد خارج المجموعة.',
  'h2h.seat_taken' => 'هذا المقعد مشغول. اختر مقعداً آخر.',
  'h2h.player_seated' => 'لهذا اللاعب مقعد في هذا الشهر من قبل.',
  'h2h.player_unknown' => 'اللاعب غير موجود.',
  'h2h.slot_invalid' => 'رقم المقعد غير صالح.',
  'h2h.round_invalid' => 'رقم الجولة من 1 إلى 19.',
  'h2h.groups_out_of_range' => 'أضف من مجموعة واحدة إلى 10 في كل مرة.',
  'h2h.groups_invalid' => 'عدد المجموعات غير صالح.',
  'h2h.groups_no_players' =>
    'لا يوجد لاعبان على الأقل بلا مقعد وبأيام نشاط كافية.',
  'h2h.group_taken' =>
    'أُضيفت مجموعة في الوقت نفسه. حدّث الصفحة ثم أعد المحاولة.',
  _ => ErrorPresenter.message(error),
};

/// The first day of the month after [monthStart] (`YYYY-MM-01`), or null
/// when [monthStart] is not such a day. Derived from the server's month,
/// never from the device's clock.
String? nextMonthOf(String monthStart) {
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-01$').firstMatch(monthStart);
  if (m == null) return null;
  int year = int.parse(m.group(1)!);
  int month = int.parse(m.group(2)!) + 1;
  if (month > 12) {
    month = 1;
    year++;
  }
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-01';
}

/// The dashboard's tabs, in their order.
enum _H2hAdminTab {
  rounds('الجولات'),
  groups('المجموعات'),
  player('لاعب'),
  controls('الإعدادات'),
  report('التقرير والسجل');

  const _H2hAdminTab(this.label);

  final String label;
}

/// The head-to-head section of the admin hub.
class H2hAdminSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const H2hAdminSection({super.key});

  @override
  ConsumerState<H2hAdminSection> createState() => _H2hAdminSectionState();
}

class _H2hAdminSectionState extends ConsumerState<H2hAdminSection> {
  /// The month shown: null is the server's current month, otherwise a day
  /// of the next one.
  String? _day;

  /// The current month as the server named it, kept to return to it.
  String? _currentMonth;

  /// The tab shown.
  _H2hAdminTab _tab = _H2hAdminTab.rounds;

  bool _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _reload() => ref.invalidate(adminH2hRoundsProvider(_day));

  Future<void> _approve(H2hCandidateDayDto day) async {
    setState(() => _busy = true);
    final Result<H2hRoundDto> result = await ref
        .read(adminApiProvider)
        .approveH2hRound(day.day);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(switch (result) {
      Ok<H2hRoundDto>(:final value) =>
        'اعتُمد ${h2hDayLabel(value.day)} الجولة ${value.round}',
      Err<H2hRoundDto>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
  }

  Future<void> _withdraw(H2hRoundDto round) async {
    final bool sure = await _confirm(
      title: 'سحب الجولة ${round.round}',
      body:
          'يعود ${h2hDayLabel(round.day)} يوماً عادياً، ويمكن اعتماده '
          'من جديد قبل انطلاق مبارياته.',
      action: 'سحب',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    final Result<bool> result = await ref
        .read(adminApiProvider)
        .withdrawH2hRound(round.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(switch (result) {
      Ok<bool>() => 'سُحبت الجولة ${round.round}',
      Err<bool>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
  }

  Future<void> _startPilot() async {
    final bool sure = await _confirm(
      title: 'بدء الشهر التجريبي',
      body:
          'تُجرى القرعة الآن على اللاعبين المضافين إلى التجربة (h2h_pilot)، '
          'مرة واحدة لهذا الشهر ولا يمكن التراجع عنها. نتائج التجربة '
          'لا تُحتسب ولا تُرسل شيئاً لأحد.',
      action: 'ابدأ التجربة',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    final Result<int> result = await ref.read(adminApiProvider).startH2hPilot();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(switch (result) {
      Ok<int>(:final value) => 'بدأت التجربة: $value لاعباً في القرعة',
      Err<int>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            key: const Key('admin.h2h.confirm.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('admin.h2h.confirm.ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // The server's current month, for the month chips of every tab.
    final String? current = ref
        .watch(adminH2hRoundsProvider(null))
        .value
        ?.monthStart;
    if (current != null) _currentMonth = current;
    final List<Widget> header = _header(context);
    return switch (_tab) {
      _H2hAdminTab.rounds => _rounds(context, header),
      _H2hAdminTab.groups => H2hAdminGroupsTab(day: _day, header: header),
      _H2hAdminTab.player => H2hAdminPlayerTab(header: header),
      _H2hAdminTab.controls => H2hAdminControlsTab(day: _day, header: header),
      _H2hAdminTab.report => H2hAdminReportTab(day: _day, header: header),
    };
  }

  /// The title, the tabs and, but on the player tab, the month chips.
  List<Widget> _header(BuildContext context) {
    final String? next = _currentMonth == null
        ? null
        : nextMonthOf(_currentMonth!);
    return <Widget>[
      const AdminSectionHeader(
        title: h2hLeagueName,
        subtitle:
            'لوحة الدوري: الجولات، والمجموعات، واللاعبون، والإعدادات، '
            'والتقرير والسجل.',
      ),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final _H2hAdminTab tab in _H2hAdminTab.values)
            ChoiceChip(
              key: Key('admin.h2h.tab.${tab.name}'),
              label: Text(tab.label),
              selected: _tab == tab,
              onSelected: (_) => setState(() => _tab = tab),
            ),
        ],
      ),
      if (_tab != _H2hAdminTab.player) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            ChoiceChip(
              key: const Key('admin.h2h.month.current'),
              label: const Text('هذا الشهر'),
              selected: _day == null,
              onSelected: (_) => setState(() => _day = null),
            ),
            if (next != null)
              ChoiceChip(
                key: const Key('admin.h2h.month.next'),
                label: const Text('الشهر القادم'),
                selected: _day != null,
                onSelected: (_) => setState(() => _day = next),
              ),
          ],
        ),
      ],
      const SizedBox(height: AppSpacing.md),
    ];
  }

  /// The rounds tab: the draw, the approved rounds and the days that
  /// may be approved next.
  Widget _rounds(BuildContext context, List<Widget> header) {
    final AsyncValue<H2hRoundsOverviewDto> overview = ref.watch(
      adminH2hRoundsProvider(_day),
    );
    return overview.when(
      loading: () => ListView(
        children: <Widget>[
          ...header,
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (Object error, _) => ListView(
        children: <Widget>[
          ...header,
          Text(
            error is AppError
                ? h2hAdminErrorMessage(error)
                : 'تعذّر تحميل دوري المواجهات',
            key: const Key('admin.h2h.error'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: TextButton(
              onPressed: _reload,
              child: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      ),
      data: (H2hRoundsOverviewDto data) => _body(context, data, header),
    );
  }

  Widget _body(
    BuildContext context,
    H2hRoundsOverviewDto data,
    List<Widget> header,
  ) {
    final AppTokens tokens = context.tokens;
    final bool beforeLaunch =
        data.startsOn.isNotEmpty &&
        data.monthStart.compareTo(data.startsOn) < 0;
    final int? lastNumber = data.rounds.isEmpty ? null : data.rounds.last.round;
    final TextStyle? heading = context.text.titleSmall?.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w700,
    );
    return ListView(
      key: const Key('admin.h2h.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        ...header,
        Text(
          'اعتمد أيام الجولات واسحب آخرها قبل أن يبدأ. يعتمد الخادم وحده '
          'الأيام التي فيها 6 مباريات أو أكثر حسب «الإعدادات».',
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        AdminCard(
          key: const Key('admin.h2h.month'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(h2hMonthLabel(data.monthStart), style: heading),
              const SizedBox(height: AppSpacing.xs),
              Text(
                data.drawn
                    ? (data.isPilot
                          ? 'القرعة: أُجريت (شهر تجريبي، نتائجه لا تُحتسب)'
                          : 'القرعة: أُجريت')
                    : 'القرعة: لم تُجرَ بعد',
                key: const Key('admin.h2h.draw'),
                style: context.text.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              Text(
                'الجولات المعتمدة: ${data.rounds.length} من 19',
                style: context.text.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (beforeLaunch && !data.drawn) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          AdminCard(
            key: const Key('admin.h2h.pilot'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('الشهر التجريبي', style: heading),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'قبل الانطلاق يلعب اللاعبون المضافون إلى التجربة شهراً '
                  'مخفياً لا تُحتسب نتائجه. بعد القرعة يعتمد الخادم أيام '
                  'هذا الشهر الباقية بنفسه.',
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AdminPrimaryButton(
                  key: const Key('admin.h2h.pilot.start'),
                  label: 'بدء الشهر التجريبي',
                  icon: Icons.science_outlined,
                  loading: _busy,
                  onPressed: _busy ? null : () => unawaited(_startPilot()),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('الجولات المعتمدة', style: heading),
        const SizedBox(height: AppSpacing.sm),
        if (data.rounds.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'لا جولات معتمدة في هذا الشهر بعد',
              key: Key('admin.h2h.rounds.empty'),
              textAlign: TextAlign.center,
            ),
          ),
        for (final H2hRoundDto r in data.rounds) ...<Widget>[
          _RoundCard(
            round: r,
            withdrawable: r.round == lastNumber && !r.locked,
            busy: _busy,
            onWithdraw: () => unawaited(_withdraw(r)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('أيام يمكن اعتمادها', style: heading),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'كل مباريات اليوم تدخل الجولة، وتُجمَّد عند أول مباراة. يوم من 5 '
          'مباريات جولة تكميلية، يعتمدها المشرف وحده.',
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (data.candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'لا أيام قادمة تصلح جولة في هذا الشهر',
              key: Key('admin.h2h.candidates.empty'),
              textAlign: TextAlign.center,
            ),
          ),
        for (final H2hCandidateDayDto c in data.candidates) ...<Widget>[
          _CandidateCard(
            candidate: c,
            busy: _busy,
            onApprove: () => unawaited(_approve(c)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

/// One approved round.
class _RoundCard extends StatelessWidget {
  const _RoundCard({
    required this.round,
    required this.withdrawable,
    required this.busy,
    required this.onWithdraw,
  });

  final H2hRoundDto round;
  final bool withdrawable;
  final bool busy;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String state = round.locked
        ? 'بدأت وجُمّدت مبارياتها'
        : (round.automatic ? 'اعتمدها الخادم' : 'اعتمدها المشرف');
    return AdminCard(
      key: Key('admin.h2h.round.${round.round}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'الجولة ${round.round} · ${h2hDayLabel(round.day)}',
            style: context.text.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${round.fixtureCount} مباريات · $state',
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          if (withdrawable) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            AdminSecondaryButton(
              key: Key('admin.h2h.round.${round.round}.withdraw'),
              label: 'سحب الجولة',
              icon: Icons.undo_rounded,
              onPressed: busy ? null : onWithdraw,
            ),
          ],
        ],
      ),
    );
  }
}

/// One day that may become the next round.
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.busy,
    required this.onApprove,
  });

  final H2hCandidateDayDto candidate;
  final bool busy;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final bool fill = candidate.kind == 'fill';
    return AdminCard(
      key: Key('admin.h2h.candidate.${candidate.day}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            h2hDayLabel(candidate.day),
            style: context.text.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${candidate.fixtureCount} مباريات · أول مباراة '
            '${formatKickoffTime(context, candidate.firstKickoff)}'
            '${fill ? ' · جولة تكميلية' : ''}',
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AdminPrimaryButton(
            key: Key('admin.h2h.candidate.${candidate.day}.approve'),
            label: 'اعتماد جولة',
            icon: Icons.check_rounded,
            onPressed: busy ? null : onApprove,
          ),
        ],
      ),
    );
  }
}
