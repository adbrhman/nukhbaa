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

import '../../../../core/design/app_radius.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/providers.dart';
import '../../../../core/ui/segmented_pills.dart';
import '../../../competition/team_registry.dart';
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

// NK317_01
/// `GET /owner/h2h-cup/picks?month=` -- the month's board with every
/// player's pick shown, kicked off or not. Read only once a pair is opened.
final ownerH2hCupPicksProvider = FutureProvider.autoDispose
    .family<H2hCupBoardDto, String?>((ref, month) async {
      return switch (await ref
          .watch(adminApiProvider)
          .ownerH2hCupPicks(month: month)) {
        Ok<H2hCupBoardDto>(:final value) => value,
        Err<H2hCupBoardDto>(:final error) => throw error,
      };
    }, retry: (_, _) => null);

/// Opens a pair's picks.
const String _ownerPicksOpen = 'عرض توقعات المباريات';

/// Closes a pair's picks.
const String _ownerPicksClose = 'إخفاء توقعات المباريات';

/// Said above the picks: the owner sees what a player cannot.
const String _ownerPicksNotice = 'للمالك فقط: ترى التوقعات قبل الانطلاق';

/// A pair the board does not hold, or one that holds no fixture yet.
const String _ownerPicksNone = 'لا مباريات لهذا الزوج بعد.';

/// The fixtures of the pair at [place], [round] and [slot] in [board]. Null
/// when the board holds no such pair, or holds it drawn between other
/// players (the pair was redrawn between the two reads).
List<H2hCupBoardFixtureDto>? _ownerPairFixtures(
  H2hCupBoardDto board,
  int place,
  String round,
  H2hCupPairDto pair,
) {
  for (final H2hCupBoardPathDto path in board.paths) {
    if (path.place != place) continue;
    for (final H2hCupBoardStageDto stage in path.stages) {
      if (stage.round != round) continue;
      for (final H2hCupBoardPairDto found in stage.pairs) {
        if (found.slot == pair.slot &&
            found.home.userId == pair.home.userId &&
            found.away.userId == pair.away.userId) {
          return found.fixtures;
        }
      }
    }
  }
  return null;
}

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
        // NK317_02
        ref.invalidate(ownerH2hCupPicksProvider);
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
            child: _Path(path: path, month: data.monthStart),
          ),
      ],
    );
  }
}

class _Path extends StatelessWidget {
  const _Path({required this.path, required this.month});

  final OwnerH2hCupPathDto path;

  /// The month the cup belongs to, asked of the picks route.
  final String month;

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
            _Stage(place: path.place, month: month, stage: stage),
        ],
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.place, required this.month, required this.stage});

  final int place;
  final String month;
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
            _PairLine(
              place: place,
              month: month,
              round: stage.round,
              pair: pair,
            ),
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

class _PairLine extends ConsumerStatefulWidget {
  const _PairLine({
    required this.place,
    required this.month,
    required this.round,
    required this.pair,
  });

  final int place;
  final String month;
  final String round;
  final H2hCupPairDto pair;

  @override
  ConsumerState<_PairLine> createState() => _PairLineState();
}

class _PairLineState extends ConsumerState<_PairLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final int place = widget.place;
    final String round = widget.round;
    final H2hCupPairDto pair = widget.pair;
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
          // NK317_03
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: Key('owner.h2h.pair.$place.$round.${pair.slot}.toggle'),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _open ? _ownerPicksClose : _ownerPicksOpen,
                        style: context.text.labelMedium?.copyWith(
                          color: t.gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: t.gold,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            _PairPicks(
              place: place,
              month: widget.month,
              round: round,
              pair: pair,
            ),
        ],
      ),
    );
  }
}

/// A pair's fixtures with both players' picks, read from the owner picks
/// route. Read only: nothing here writes, and the owner sees the picks of
/// fixtures that have not kicked off, which no player does.
class _PairPicks extends ConsumerWidget {
  const _PairPicks({
    required this.place,
    required this.month,
    required this.round,
    required this.pair,
  });

  final int place;
  final String month;
  final String round;
  final H2hCupPairDto pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final String prefix = 'owner.h2h.picks.$place.$round.${pair.slot}';
    final AsyncValue<H2hCupBoardDto> board = ref.watch(
      ownerH2hCupPicksProvider(month),
    );
    return Container(
      key: Key(prefix),
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.visibility_rounded, size: 16, color: t.gold),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  _ownerPicksNotice,
                  key: Key('$prefix.notice'),
                  style: context.text.labelMedium?.copyWith(
                    color: t.gold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          board.when(
            loading: () => Padding(
              key: Key('$prefix.loading'),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: const Center(child: CircularProgressIndicator()),
            ),
            error: (Object e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  ErrorPresenter.messageOf(e),
                  key: Key('$prefix.error'),
                  style: TextStyle(color: t.errorText),
                ),
                TextButton(
                  key: Key('$prefix.retry'),
                  onPressed: () => ref.invalidate(ownerH2hCupPicksProvider),
                  child: const Text(h2hCupBoardRetry),
                ),
              ],
            ),
            data: (H2hCupBoardDto data) {
              final List<H2hCupBoardFixtureDto>? fixtures = _ownerPairFixtures(
                data,
                place,
                round,
                pair,
              );
              if (fixtures == null || fixtures.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _ownerPicksNone,
                    key: Key('$prefix.empty'),
                    style: context.text.bodySmall?.copyWith(color: t.textMuted),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final H2hCupBoardFixtureDto fixture in fixtures)
                    _PickFixture(
                      keyPrefix: '$prefix.fixture.${fixture.fixtureId}',
                      pair: pair,
                      fixture: fixture,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One fixture: the match, its state, then the two players' picks.
class _PickFixture extends StatelessWidget {
  const _PickFixture({
    required this.keyPrefix,
    required this.pair,
    required this.fixture,
  });

  final String keyPrefix;
  final H2hCupPairDto pair;
  final H2hCupBoardFixtureDto fixture;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupBoardFixtureDto f = fixture;
    final bool scored = f.homeGoals != null && f.awayGoals != null;
    final String middle = scored
        ? h2hScoreline(f.homeGoals!, f.awayGoals!)
        : h2hCupKickoffLabel(f.kickoffAt);
    final TextStyle? team = context.text.bodyMedium?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      key: Key(keyPrefix),
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  teamDisplayName(f.homeTeam),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: team,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  middle,
                  key: Key('$keyPrefix.middle'),
                  style: context.text.titleSmall?.copyWith(
                    color: scored ? t.textPrimary : t.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  teamDisplayName(f.awayTeam),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: team,
                ),
              ),
            ],
          ),
          Text(
            h2hFixtureStateLabel(f.state),
            key: Key('$keyPrefix.state'),
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          _PickRow(
            keyPrefix: '$keyPrefix.home',
            player: pair.home,
            side: f.homeSide,
          ),
          _PickRow(
            keyPrefix: '$keyPrefix.away',
            player: pair.away,
            side: f.awaySide,
          ),
          if (f.state == 'void')
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                h2hCupBoardVoidNote,
                key: Key('$keyPrefix.void'),
                style: context.text.bodySmall?.copyWith(color: t.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// One player's line of a fixture: his name, then his pick, or that it is
/// withheld, or that he did not predict. The owner route never withholds,
/// but the contract allows it, so a withheld side is never read as "did
/// not predict".
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.keyPrefix,
    required this.player,
    required this.side,
  });

  final String keyPrefix;
  final H2hCupPlayerDto player;
  final H2hCupBoardSideDto side;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hPickDto? pick = side.pick;
    final Widget body;
    if (!side.revealed) {
      body = Text(
        h2hCupPickHidden,
        key: Key('$keyPrefix.hidden'),
        style: context.text.labelMedium?.copyWith(color: t.textSecondary),
      );
    } else if (pick == null) {
      body = Text(
        h2hCupNoPickOther,
        key: Key('$keyPrefix.none'),
        style: context.text.titleSmall?.copyWith(
          color: t.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      );
    } else {
      final String extras = h2hCupPickExtras(pick);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            h2hScoreline(pick.homeGoals, pick.awayGoals),
            key: Key('$keyPrefix.pick'),
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (extras.isNotEmpty)
            Text(
              extras,
              key: Key('$keyPrefix.extras'),
              style: context.text.labelSmall?.copyWith(color: t.textSecondary),
            ),
        ],
      );
    }
    return Padding(
      key: Key(keyPrefix),
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              h2hCupNameOf(player),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(color: t.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: body),
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
