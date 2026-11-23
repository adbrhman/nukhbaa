/// تبويب «المواجهات» في «الإدارة العامة للمالك» (السكربت 304): كل ما في
/// دوري المواجهات بيد المالكَين وحدهما. أقفال الجولات والكأس والتتويج،
/// وتشغيل المهام الآن، وجولات الشهر، والكأس كاملاً بمساراته الثلاثة
/// (المتأهلون والمواجهات والنتائج والألقاب).
///
/// كل رقم وكل مواجهة من الخادم (`GET /owner/h2h-cup`)؛ هنا لا يُسحب شيء ولا
/// يُحسم شيء. والخادم يجيب غير المالكَين بمسار غير موجود، فلا يرى المشرفون
/// منه شيئاً. لا يتغير قفل إلا بسبب مكتوب، ويُسجَّل الطلب في سجل المالك.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/providers.dart';
import '../../../../core/ui/segmented_pills.dart';
import '../../../h2h/h2h_cup_texts.dart';
import '../../../h2h/h2h_texts.dart';
import '../../widgets/admin_ui_kit.dart';
import 'owner_switches_section.dart';

/// `GET /owner/h2h-cup?month=` -- the whole cup of a month; the latest month
/// that holds one when the month is null.
final ownerH2hCupProvider = FutureProvider.autoDispose
    .family<OwnerH2hCupDto, String?>((ref, month) async {
      return switch (await ref
          .watch(adminApiProvider)
          .ownerH2hCup(month: month)) {
        Ok<OwnerH2hCupDto>(:final value) => value,
        Err<OwnerH2hCupDto>(:final error) => throw error,
      };
    }, retry: (_, _) => null);

/// The keys of the three locks, in the order they are drawn.
const List<String> ownerH2hSwitchKeys = <String>[
  'h2h_rounds',
  'h2h_cup',
  'h2h_cup_crowning',
];

typedef _LockText = ({String name, String whenOn, String whenOff});

_LockText _lockText(String key) => switch (key) {
  'h2h_rounds' => (
    name: 'اعتماد الجولات',
    whenOn: 'يعمل: تُعتمد الجولات الجديدة تلقائياً ويعتمدها المشرفون.',
    whenOff:
        'موقوف: لا تُعتمد جولة جديدة، لا تلقائياً ولا من المشرفين. الجولات '
        'المعتمدة تُقفل وتُحسم كالمعتاد.',
  ),
  'h2h_cup' => (
    name: 'كأس المواجهات',
    whenOn: 'يعمل: يُدار الكأس تلقائياً بعد انتهاء جولات الشهر.',
    whenOff:
        'موقوف: لا يُسجَّل متأهل ولا مرحلة ولا نتيجة ولا لقب، وما سُجّل '
        'باقٍ. جولات الشهر التالي تنتظر انتهاء الكأس.',
  ),
  'h2h_cup_crowning' => (
    name: 'تتويج الكأس',
    whenOn: 'يعمل: يُتوَّج كل مسار بعد نهائيه.',
    whenOff:
        'موقوف: يستمر الكأس ولا يُتوَّج أي مسار. جولات الشهر التالي تنتظر '
        'التتويج.',
  ),
  _ => (name: key, whenOn: 'يعمل', whenOff: 'موقوف'),
};

/// The owners' head-to-head tab.
class OwnerH2hSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const OwnerH2hSection({super.key});

  @override
  ConsumerState<OwnerH2hSection> createState() => _OwnerH2hSectionState();
}

class _OwnerH2hSectionState extends ConsumerState<OwnerH2hSection> {
  /// The month the owner picked, or null for the latest with a cup.
  String? _month;
  bool _busy = false;

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _turn(String key, bool on) async {
    final _LockText text = _lockText(key);
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: on ? 'تشغيل «${text.name}»' : 'إيقاف «${text.name}»',
        notice: on ? text.whenOn : text.whenOff,
        confirmLabel: on ? 'شغّل' : 'أوقف',
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final Result<OwnerSwitchDto> result = await ref
        .read(adminApiProvider)
        .setOwnerSwitch(key, on: on, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<OwnerSwitchDto>(:final value):
        _say(value.isOn ? 'شُغّل «${text.name}»' : 'أُوقف «${text.name}»');
        ref.invalidate(ownerSwitchesProvider);
      case Err<OwnerSwitchDto>(:final error):
        _say(ErrorPresenter.message(error));
    }
  }

  Future<void> _runJobs() async {
    setState(() => _busy = true);
    final Result<H2hJobsRunDto> result = await ref
        .read(adminApiProvider)
        .runH2hJobs();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<H2hJobsRunDto>(:final value):
        _say(
          'اعتُمدت ${value.approved} وأُقفلت ${value.locked} '
          'وحُسم ${value.closedMonths} من الأشهر.',
        );
        ref.invalidate(ownerH2hCupProvider);
      case Err<H2hJobsRunDto>(:final error):
        _say(ErrorPresenter.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AsyncValue<OwnerH2hCupDto> cup = ref.watch(
      ownerH2hCupProvider(_month),
    );
    return ListView(
      key: const Key('owner.h2h.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'مواجهات المالك',
          subtitle:
              'أقفال الجولات والكأس والتتويج، والكأس كاملاً بمساراته. لا يرى '
              'المشرفون شيئاً من هذه الصفحة.',
        ),
        _Locks(busy: _busy, onTurn: (k, on) => unawaited(_turn(k, on))),
        const SizedBox(height: AppSpacing.sm),
        AdminSecondaryButton(
          key: const Key('owner.h2h.run'),
          label: 'تشغيل مهام المواجهات الآن',
          icon: Icons.play_arrow_rounded,
          loading: _busy,
          onPressed: _busy ? null : () => unawaited(_runJobs()),
        ),
        const SizedBox(height: AppSpacing.md),
        cup.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (Object e, _) => AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  ErrorPresenter.messageOf(e),
                  key: const Key('owner.h2h.loadError'),
                  style: TextStyle(color: t.errorText),
                ),
                TextButton(
                  key: const Key('owner.h2h.retry'),
                  onPressed: () => ref.invalidate(ownerH2hCupProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: (OwnerH2hCupDto data) => _Body(
            data: data,
            onMonth: (String month) => setState(() => _month = month),
          ),
        ),
      ],
    );
  }
}

/// The three locks, each with its state.
class _Locks extends ConsumerWidget {
  const _Locks({required this.busy, required this.onTurn});

  final bool busy;
  final void Function(String key, bool on) onTurn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AsyncValue<OwnerSwitchesDto> state = ref.watch(ownerSwitchesProvider);
    return AdminCard(
      key: const Key('owner.h2h.locks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'أقفال المواجهات',
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          state.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object e, _) => Text(
              ErrorPresenter.messageOf(e),
              key: const Key('owner.h2h.locks.error'),
              style: TextStyle(color: t.errorText),
            ),
            data: (OwnerSwitchesDto data) => Column(
              children: <Widget>[
                for (final String key in ownerH2hSwitchKeys)
                  _lock(context, t, key, data),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lock(
    BuildContext context,
    AppTokens t,
    String key,
    OwnerSwitchesDto data,
  ) {
    final _LockText text = _lockText(key);
    OwnerSwitchDto? line;
    for (final OwnerSwitchDto s in data.switches) {
      if (s.key == key) line = s;
    }
    if (line == null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          '«${text.name}»: لا مفتاح بعد. طبّق الهجرة 0225 في SQL Editor.',
          key: Key('owner.h2h.switch.$key.missing'),
          style: context.text.bodySmall?.copyWith(color: t.errorText),
        ),
      );
    }
    final OwnerSwitchDto found = line;
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        key: Key('owner.h2h.switch.$key'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          text.name,
          style: context.text.titleSmall?.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          found.isOn ? text.whenOn : text.whenOff,
          key: Key('owner.h2h.switch.$key.state'),
          style: context.text.bodySmall?.copyWith(
            color: found.isOn ? t.textSecondary : t.errorText,
            fontWeight: found.isOn ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
        value: found.isOn,
        onChanged: busy ? null : (bool on) => onTurn(key, on),
      ),
    );
  }
}

/// The month's rounds and the cup.
class _Body extends StatelessWidget {
  const _Body({required this.data, required this.onMonth});

  final OwnerH2hCupDto data;
  final ValueChanged<String> onMonth;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int picked = data.months.indexWhere(
      (OwnerH2hCupMonthDto m) => m.monthStart == data.monthStart,
    );
    final int lockedRounds = data.rounds
        .where((OwnerH2hCupRoundDto r) => r.locked)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (data.months.length > 1) ...<Widget>[
          SegmentedPills(
            key: const Key('owner.h2h.months'),
            labels: <String>[
              for (final OwnerH2hCupMonthDto m in data.months)
                h2hMonthLabel(m.monthStart),
            ],
            selectedIndex: picked < 0 ? data.months.length - 1 : picked,
            keyPrefix: 'owner.h2h.month',
            onSelected: (int i) => onMonth(data.months[i].monthStart),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        AdminCard(
          key: const Key('owner.h2h.rounds'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'جولات ${h2hMonthLabel(data.monthStart)}',
                style: context.text.titleSmall?.copyWith(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                data.rounds.isEmpty
                    ? 'لا جولة معتمدة في هذا الشهر.'
                    : '${data.rounds.length} جولة معتمدة · $lockedRounds '
                          'مقفلة',
                key: const Key('owner.h2h.rounds.summary'),
                style: context.text.bodySmall?.copyWith(color: t.textSecondary),
              ),
              for (final OwnerH2hCupRoundDto r in data.rounds)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'الجولة ${r.number} · ${h2hDayLabel(r.day)} · '
                    '${r.fixtureCount} مباراة · '
                    '${r.locked ? 'مقفلة' : 'مفتوحة'} · '
                    '${r.bySystem ? 'تلقائي' : 'مشرف'}',
                    key: Key('owner.h2h.round.${r.number}'),
                    style: context.text.bodySmall?.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (data.paths.isEmpty)
          const AdminEmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'لا كأس في هذا الشهر بعد.',
          ),
        for (final OwnerH2hCupPathDto path in data.paths)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _Path(path: path),
          ),
      ],
    );
  }
}

class _Path extends StatelessWidget {
  const _Path({required this.path});

  final OwnerH2hCupPathDto path;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupPlayerDto? champion = path.title?.champion;
    return AdminCard(
      key: Key('owner.h2h.path.${path.place}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            h2hCupPathName(path.place),
            style: context.text.titleSmall?.copyWith(
              color: t.gold,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'المتأهلون: ${path.entrants.isEmpty ? 'لا أحد' : path.entrants.map((H2hCupPlayerDto p) => '${h2hCupNameOf(p)} (م${p.groupNumber})').join('، ')}',
            key: Key('owner.h2h.path.${path.place}.entrants'),
            style: context.text.bodySmall?.copyWith(color: t.textSecondary),
          ),
          if (path.title != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                champion == null
                    ? 'اللقب شاغر'
                    : 'البطل: ${h2hCupNameOf(champion)}'
                          '${path.title!.runnerUp == null ? '' : ' · الوصيف: ${h2hCupNameOf(path.title!.runnerUp!)}'}',
                key: Key('owner.h2h.path.${path.place}.title'),
                style: context.text.bodyMedium?.copyWith(
                  color: t.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          for (final H2hCupStageDto stage in path.stages)
            _Stage(place: path.place, stage: stage),
        ],
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.place, required this.stage});

  final int place;
  final H2hCupStageDto stage;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${h2hCupRoundName(stage.round)} · ${h2hCupPhaseName(stage.phase)}'
            '${stage.day == null ? '' : ' · ${h2hDayLabel(stage.day!)}'}'
            '${stage.attempt > 1 ? ' · المحاولة ${stage.attempt}' : ''}',
            key: Key('owner.h2h.stage.$place.${stage.round}'),
            style: context.text.labelLarge?.copyWith(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (stage.pairs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                stage.phase == 'skipped'
                    ? 'لا تُلعب هذه المرحلة'
                    : h2hCupWaitingLine(stage),
                style: context.text.bodySmall?.copyWith(color: t.textMuted),
              ),
            ),
          for (final H2hCupPairDto pair in stage.pairs)
            _PairLine(place: place, round: stage.round, pair: pair),
          if (stage.bye != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'تأهل مباشرة: ${h2hCupNameOf(stage.bye!)}',
                style: context.text.bodySmall?.copyWith(color: t.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _PairLine extends StatelessWidget {
  const _PairLine({
    required this.place,
    required this.round,
    required this.pair,
  });

  final int place;
  final String round;
  final H2hCupPairDto pair;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool homeWon = pair.decided && pair.winnerUserId == pair.home.userId;
    final bool awayWon = pair.decided && pair.winnerUserId == pair.away.userId;
    final String score = pair.decided
        ? '${pair.homePoints ?? 0} - ${pair.awayPoints ?? 0}'
        : 'ضد';
    final String why = h2hCupOutcomeName(pair.outcome);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            key: Key('owner.h2h.pair.$place.$round.${pair.slot}'),
            children: <Widget>[
              Expanded(
                child: Text(
                  h2hCupNameOf(pair.home),
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: homeWon ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  score,
                  style: context.text.labelLarge?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  h2hCupNameOf(pair.away),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: awayWon ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (pair.decided && why.isNotEmpty)
            Text(
              why,
              key: Key('owner.h2h.outcome.$place.$round.${pair.slot}'),
              style: context.text.bodySmall?.copyWith(color: t.textMuted),
            ),
        ],
      ),
    );
  }
}

/// Asks the owner why he turns a lock; null when he cancels.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.notice,
    required this.confirmLabel,
  });

  final String title;
  final String notice;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String reason = _reason.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.notice, key: const Key('owner.h2h.dialog.notice')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('owner.h2h.reason'),
              controller: _reason,
              maxLength: ownerSwitchReasonMaxLength,
              decoration: const InputDecoration(labelText: 'السبب (مطلوب)'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('owner.h2h.dialog.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('owner.h2h.dialog.confirm'),
          onPressed: reason.isEmpty
              ? null
              : () => Navigator.of(context).pop(reason),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
