// NK323_01
/// جدول كأس النخبة حسب الأيام: أيام الكأس بالترتيب، وفي كل يوم مسارات
/// الأوائل ثم الثواني ثم الثوالث التي تُلعب فيه، بمراحلها وأزواجها
/// ونتائجها. كل شيء من لوحة الكأس التي يرسلها الخادم
/// (`GET /me/h2h-cup/board`)؛ هنا لا يُسحب شيء ولا يُحسم شيء ولا تُقرأ الساعة.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

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
