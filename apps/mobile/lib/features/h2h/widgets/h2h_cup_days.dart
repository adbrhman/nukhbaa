// NK323_01
/// جدول كأس النخبة حسب الأيام: أيام الكأس بالترتيب، وفي كل يوم مسارات
/// الأوائل ثم الثواني ثم الثوالث التي تُلعب فيه، بمراحلها وأزواجها
/// ونتائجها. كل شيء من لوحة الكأس التي يرسلها الخادم
/// (`GET /me/h2h-cup/board`)؛ هنا لا يُسحب شيء ولا يُحسم شيء ولا تُقرأ الساعة.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../h2h_cup_texts.dart';
import '../h2h_texts.dart';

/// One stage of one path, kept with its path for the cup day it is played.
class _Slot {
  const _Slot(this.path, this.stage);

  final H2hCupBoardPathDto path;
  final H2hCupBoardStageDto stage;
}

/// The cup laid out by day: the first places' path first, then the second
/// places' and the third places' of the same day.
class H2hCupDays extends StatelessWidget {
  /// ينشئ الجدول.
  const H2hCupDays({required this.board, super.key});

  /// The board to lay out by cup day.
  final H2hCupBoardDto board;

  @override
  Widget build(BuildContext context) {
    final Map<int, List<_Slot>> byDay = <int, List<_Slot>>{};
    for (final H2hCupBoardPathDto path in board.paths) {
      for (final H2hCupBoardStageDto stage in path.stages) {
        byDay
            .putIfAbsent(stage.cupDay, () => <_Slot>[])
            .add(_Slot(path, stage));
      }
    }
    for (final List<_Slot> slots in byDay.values) {
      slots.sort((_Slot a, _Slot b) => a.path.place.compareTo(b.path.place));
    }
    final List<int> days = byDay.keys.toList()..sort();
    return Column(
      key: const Key('h2h.cup.days'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final int cupDay in days)
          _DayBlock(cupDay: cupDay, slots: byDay[cupDay]!),
      ],
    );
  }
}

/// One cup day: its heading and the stages played on it.
class _DayBlock extends StatelessWidget {
  const _DayBlock({required this.cupDay, required this.slots});

  final int cupDay;
  final List<_Slot> slots;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    String? date;
    for (final _Slot slot in slots) {
      final String? day = slot.stage.day;
      if (day != null) {
        date = day;
        break;
      }
    }
    final String heading =
        '${h2hCupDayName(cupDay)}'
        '${date == null ? '' : ' · ${h2hDayLabel(date)}'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            heading,
            key: Key('h2h.cup.days.$cupDay'),
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          for (final _Slot slot in slots) _SlotBlock(slot: slot),
        ],
      ),
    );
  }
}

/// One stage of one path on its day: who plays, or why nobody is shown yet.
class _SlotBlock extends StatelessWidget {
  const _SlotBlock({required this.slot});

  final _Slot slot;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupBoardStageDto stage = slot.stage;
    final int place = slot.path.place;
    final H2hCupTitleDto? title = slot.path.title;
    final H2hCupPlayerDto? bye = stage.bye;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${h2hCupPathName(place)} · ${h2hCupRoundName(stage.round)}'
            ' · ${h2hCupPhaseName(stage.phase)}',
            key: Key('h2h.cup.days.${stage.cupDay}.$place'),
            style: context.text.labelLarge?.copyWith(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (stage.pairs.isEmpty && bye == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                h2hCupBoardStageEmpty(stage.phase),
                key: Key('h2h.cup.days.${stage.cupDay}.$place.empty'),
                style: context.text.bodySmall?.copyWith(color: t.textMuted),
              ),
            ),
          for (final H2hCupBoardPairDto pair in stage.pairs)
            _PairLine(place: place, round: stage.round, pair: pair),
          if (bye != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'تأهل مباشرة: ${h2hCupNameOf(bye)}',
                style: context.text.bodySmall?.copyWith(
                  color: bye.isMe ? t.gold : t.textSecondary,
                ),
              ),
            ),
          if (stage.round == 'final' && title != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                h2hCupBoardTitleLine(title),
                key: Key('h2h.cup.days.title.$place'),
                style: context.text.titleSmall?.copyWith(
                  color: t.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One pair: the two players and, once decided, who won.
class _PairLine extends StatelessWidget {
  const _PairLine({
    required this.place,
    required this.round,
    required this.pair,
  });

  final int place;
  final String round;
  final H2hCupBoardPairDto pair;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool homeWon = pair.decided && pair.winnerUserId == pair.home.userId;
    final bool awayWon = pair.decided && pair.winnerUserId == pair.away.userId;
    TextStyle? side(H2hCupPlayerDto p, bool won) =>
        context.text.bodyMedium?.copyWith(
          color: p.isMe ? t.gold : t.textPrimary,
          fontWeight: won || p.isMe ? FontWeight.w800 : FontWeight.w500,
        );
    final String result = h2hCupBoardPairResult(pair);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            key: Key('h2h.cup.days.pair.$place.$round.${pair.slot}'),
            children: <Widget>[
              Expanded(
                child: Text(
                  h2hCupNameOf(pair.home),
                  textAlign: TextAlign.start,
                  overflow: TextOverflow.ellipsis,
                  style: side(pair.home, homeWon),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  'ضد',
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
                  style: side(pair.away, awayWon),
                ),
              ),
            ],
          ),
          if (result.isNotEmpty)
            Text(
              result,
              style: context.text.bodySmall?.copyWith(color: t.textMuted),
            ),
        ],
      ),
    );
  }
}

// NK335_02
/// «جدول الأيام» في تبويب الكأس (سكربت 335): شريط أيام الكأس بتواريخها، وتحته
/// مسارات اليوم المختار بأزواجها ونقاطها. يفتح على اليوم الذي فيه مرحلة جارية،
/// وإلا على أول يوم فيه مرحلة لم تنتهِ، وإلا على الأخير؛ وما اختاره اللاعب يبقى
/// بين لوحتين إن بقي اليوم في اللوحة.
///
/// **كل شيء من لوحة الكأس التي أرسلها الخادم.** الأيام والمراحل والأزواج
/// والنقاط (`homePoints` و`awayPoints`) كما جاءت؛ فإن لم تصل النقاط كُتب «ضد»
/// ولا يُخترع رقم، ولا تُقرأ الساعة. مرحلة بلا أزواج تُرسم مربعاً متقطعاً بما
/// تقوله حالتها. الودجة بجانب `H2hCupDays` القديمة وبلا ربط بها (التركيب في 336).
class H2hCupDaysView extends StatefulWidget {
  /// ينشئ القسم من لوحة الكأس.
  const H2hCupDaysView({required this.board, super.key});

  /// لوحة الكأس كما جاءت من الخادم.
  final H2hCupBoardDto board;

  @override
  State<H2hCupDaysView> createState() => _H2hCupDaysViewState();
}

class _H2hCupDaysViewState extends State<H2hCupDaysView> {
  /// اليوم الذي ضغطه اللاعب، أو null قبل أن يضغط.
  int? _picked;

  /// اليوم المعروض: ما ضغطه اللاعب إن بقي في اللوحة، وإلا يوم الفتح.
  H2hCupDayEntry _selected(List<H2hCupDayEntry> days) {
    for (final H2hCupDayEntry day in days) {
      if (day.cupDay == _picked) return day;
    }
    final int? opening = h2hCupBoardDefaultDay(days);
    return days.firstWhere((H2hCupDayEntry d) => d.cupDay == opening);
  }

  @override
  Widget build(BuildContext context) {
    final List<H2hCupDayEntry> days = h2hCupBoardDays(widget.board);
    if (days.isEmpty) return const SizedBox.shrink();
    final AppTokens t = context.tokens;
    final H2hCupDayEntry selected = _selected(days);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        key: const Key('h2h.cupDays'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              h2hCupDaysTableHeading,
              key: const Key('h2h.cupDays.heading'),
              style: context.text.titleSmall?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // IntrinsicHeight: the strip sits in a scroll view with no height
          // bound, where a stretched row would be asked for an infinite one.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < days.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _DayTab(
                      day: days[i],
                      selected: days[i].cupDay == selected.cupDay,
                      onTap: () => setState(() => _picked = days[i].cupDay),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            h2hCupDayName(selected.cupDay),
            key: const Key('h2h.cupDays.day'),
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          for (final H2hCupDaySlot slot in selected.slots)
            _DaySlotView(slot: slot),
        ],
      ),
    );
  }
}

/// تبويب يوم: رقمه وتاريخه إن كان له تاريخ، والمختار ممتلئ. الاسم المرسوم
/// لا يُقرأ ثانية؛ تقرؤه العلامة.
class _DayTab extends StatelessWidget {
  const _DayTab({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final H2hCupDayEntry day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String? date = day.date;
    final String prefix = 'h2h.cupDays.tab.${day.cupDay}';
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: h2hCupDayTabLabel(day),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? t.primary : t.surfaceHigh,
          borderRadius: AppRadius.brMd,
          child: InkWell(
            key: Key(prefix),
            borderRadius: AppRadius.brMd,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '${day.cupDay}',
                      key: Key('$prefix.number'),
                      style: context.text.titleMedium?.copyWith(
                        color: selected ? t.onPrimary : t.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (date != null)
                      Text(
                        h2hDayLabel(date),
                        key: Key('$prefix.date'),
                        textAlign: TextAlign.center,
                        style: context.text.labelSmall?.copyWith(
                          color: selected ? t.onPrimary : t.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// مرحلة مسار في اليوم المختار: عنوانها، ثم أزواجها، أو مربع متقطع إن لم
/// يكن فيها زوج، وسطر لمن تأهل مباشرة.
class _DaySlotView extends StatelessWidget {
  const _DaySlotView({required this.slot});

  final H2hCupDaySlot slot;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupBoardStageDto stage = slot.stage;
    final int place = slot.path.place;
    final String id = '${stage.cupDay}.$place';
    final H2hCupPlayerDto? bye = stage.bye;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            h2hCupDaySlotTitle(slot),
            key: Key('h2h.cupDays.slot.$id'),
            style: context.text.labelLarge?.copyWith(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (stage.pairs.isEmpty && bye == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _EmptyBox(
                keyName: 'h2h.cupDays.empty.$id',
                text: h2hCupBoardStageEmpty(stage.phase),
              ),
            ),
          for (final H2hCupBoardPairDto pair in stage.pairs)
            _DayPairRow(place: place, stage: stage, pair: pair),
          if (bye != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '$h2hCupTreeByeNote: ${h2hCupNameOf(bye)}',
                key: Key('h2h.cupDays.bye.$id'),
                style: context.text.bodySmall?.copyWith(
                  color: bye.isMe ? t.gold : t.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// صف زوج: صاحب الأرض، ثم نقاط الزوج وحاله، ثم الضيف. حدّه بلون الأساس إن
/// كان فيه اللاعب نفسه. كل رقم في نص مستقل داخل صف فيبقى صاحب الأرض على
/// يمين الضيف في الواجهة العربية.
class _DayPairRow extends StatelessWidget {
  const _DayPairRow({
    required this.place,
    required this.stage,
    required this.pair,
  });

  final int place;
  final H2hCupBoardStageDto stage;
  final H2hCupBoardPairDto pair;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String prefix = 'h2h.cupDays.pair.$place.${stage.round}.${pair.slot}';
    final bool mine = pair.home.isMe || pair.away.isMe;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Semantics(
        container: true,
        label: h2hCupDayPairLabel(stage, pair),
        child: ExcludeSemantics(
          child: Container(
            key: Key(prefix),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: t.backgroundElevated,
              borderRadius: AppRadius.brMd,
              border: Border.all(color: mine ? t.primary : t.border),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _DayPlayerName(
                    keyName: '$prefix.home',
                    player: pair.home,
                    pair: pair,
                    alignEnd: false,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: _DayPairMiddle(
                      prefix: prefix,
                      stage: stage,
                      pair: pair,
                    ),
                  ),
                ),
                Expanded(
                  child: _DayPlayerName(
                    keyName: '$prefix.away',
                    player: pair.away,
                    pair: pair,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// اسم لاعب في صف زوج: الفائز بعد الحسم أثخن، ومن لم يفز في زوج محسوم باهت.
class _DayPlayerName extends StatelessWidget {
  const _DayPlayerName({
    required this.keyName,
    required this.player,
    required this.pair,
    required this.alignEnd,
  });

  final String keyName;
  final H2hCupPlayerDto player;
  final H2hCupBoardPairDto pair;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool won = h2hCupPairWon(pair, player);
    final bool lost = pair.decided && !won;
    return Text(
      h2hCupNameOf(player),
      key: Key(keyName),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: context.text.bodyMedium?.copyWith(
        color: player.isMe ? t.gold : (lost ? t.textSecondary : t.textPrimary),
        fontWeight: won || player.isMe ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }
}

/// وسط الصف: نقاط الزوج من الخادم أو «ضد» حين لا تصل، وتحتها حال الزوج.
class _DayPairMiddle extends StatelessWidget {
  const _DayPairMiddle({
    required this.prefix,
    required this.stage,
    required this.pair,
  });

  final String prefix;
  final H2hCupBoardStageDto stage;
  final H2hCupBoardPairDto pair;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int? home = pair.homePoints;
    final int? away = pair.awayPoints;
    final bool live = !pair.decided && stage.phase == 'live';
    final TextStyle? score = context.text.titleMedium?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (home == null || away == null)
          Text(
            h2hCupVersus,
            key: Key('$prefix.versus'),
            style: context.text.titleSmall?.copyWith(color: t.textSecondary),
          )
        else
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('$home', key: Key('$prefix.homePoints'), style: score),
                Text(' : ', style: score),
                Text('$away', key: Key('$prefix.awayPoints'), style: score),
              ],
            ),
          ),
        Text(
          h2hCupPairStatus(stage, pair),
          key: Key('$prefix.status'),
          textAlign: TextAlign.center,
          style: context.text.labelSmall?.copyWith(
            color: live ? t.primary : t.textSecondary,
            fontWeight: live ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// مربع متقطع لمرحلة بلا أزواج: يقول إنها تنتظر السحب أو لا تُلعب.
class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.keyName, required this.text});

  final String keyName;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return CustomPaint(
      key: Key(keyName),
      painter: _DashedBoxPainter(color: t.controlBorder, radius: AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          text,
          key: Key('$keyName.text'),
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(color: t.textSecondary),
        ),
      ),
    );
  }
}

/// يرسم حدّاً متقطعاً لمستطيل مدوّر الزوايا.
class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const double dash = 5;
    const double gap = 4;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          Radius.circular(radius),
        ),
      );
    for (final ui.PathMetric metric in path.computeMetrics()) {
      double at = 0;
      while (at < metric.length) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + dash, metric.length)),
          paint,
        );
        at += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
