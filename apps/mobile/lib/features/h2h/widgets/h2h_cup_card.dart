/// بطاقة كأس النخبة للاعب المتأهل (NK185): مساره، مواجهته القادمة ومن
/// سيواجه، ويوم المرحلة، ونتيجتها، وبقية مواجهات مساره، واللقب إن حُسم.
///
/// كل شيء من الخادم (`GET /me/h2h-cup`): القرعة والأيام والنتائج؛ هنا لا
/// يُسحب شيء ولا يُحسم شيء. من لم يتأهل يرى مسار أوائل المجموعات للمشاهدة
/// فقط (`spectator`)؛ ومن لا كأس مفتوحاً له (أو فشل الطلب) لا يرى البطاقة.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../h2h_cup_texts.dart';
import '../h2h_providers.dart';
import '../h2h_texts.dart';
import 'h2h_cup_days.dart';

/// كأس النخبة: مساره للمتأهل، ومسار أوائل المجموعات لغيره، أو لا شيء.
class H2hCupCard extends ConsumerWidget {
  /// ينشئ البطاقة.
  const H2hCupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MyH2hCupDto? cup = ref.watch(myH2hCupProvider).value;
    if (cup == null || (cup.state != 'qualified' && cup.state != 'spectator')) {
      return const SizedBox.shrink();
    }
    final bool mine = cup.state == 'qualified';
    // NK323_03: a player who only watches reads the whole cup day by day
    // from the board; without it (loading, failed) he keeps the first path.
    final H2hCupBoardDto? board = mine
        ? null
        : ref.watch(h2hCupBoardProvider).value;
    final H2hCupBoardDto? days = board != null && board.paths.isNotEmpty
        ? board
        : null;
    final AppTokens t = context.tokens;
    final H2hCupStageDto? focus = mine ? h2hCupFocusStage(cup) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        key: const Key('h2h.cup'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.emoji_events_rounded, color: t.gold),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    h2hCupTitle,
                    key: const Key('h2h.cup.title'),
                    style: context.text.titleMedium?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${days == null ? h2hCupPathName(cup.place) : h2hCupDaysHeading}'
              '${mine ? ' · مجموعة ${cup.groupNumber}' : ' · مشاهدة'}'
              '${cup.monthStart == null ? '' : ' · ${h2hMonthLabel(cup.monthStart!)}'}',
              key: const Key('h2h.cup.path'),
              style: context.text.bodySmall?.copyWith(color: t.textSecondary),
            ),
            if (days == null && cup.title != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _TitleLine(title: cup.title!),
            ],
            if (focus != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _Focus(stage: focus),
            ],
            const SizedBox(height: AppSpacing.md),
            if (days != null)
              H2hCupDays(board: days)
            else
              for (final H2hCupStageDto stage in cup.stages)
                _StageBlock(stage: stage, mine: mine),
          ],
        ),
      ),
    );
  }
}

/// مواجهة اللاعب في المرحلة التي تهمه الآن.
class _Focus extends StatelessWidget {
  const _Focus({required this.stage});

  final H2hCupStageDto stage;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupPairDto? pair = h2hCupMyPair(stage);
    final String when = stage.day == null
        ? h2hCupWaitingLine(stage)
        : 'يوم ${h2hDayLabel(stage.day!)}';
    final String line;
    if (pair != null) {
      final H2hCupPlayerDto other = pair.home.isMe ? pair.away : pair.home;
      line = 'تواجه ${h2hCupNameOf(other)} (مجموعة ${other.groupNumber})';
    } else if (stage.bye?.isMe ?? false) {
      line = 'تأهلت مباشرة إلى المرحلة التالية';
    } else if (stage.pairs.isEmpty) {
      line = 'تُسحب المواجهات عند جدولة المرحلة';
    } else {
      line = 'لست في هذه المرحلة';
    }
    return Container(
      key: const Key('h2h.cup.focus'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${h2hCupRoundName(stage.round)} · ${h2hCupPhaseName(stage.phase)}',
            key: const Key('h2h.cup.focus.heading'),
            style: context.text.labelLarge?.copyWith(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            line,
            key: const Key('h2h.cup.focus.line'),
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            when,
            key: const Key('h2h.cup.focus.when'),
            style: context.text.bodySmall?.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// مرحلة واحدة من المسار بكل مواجهاتها.
class _StageBlock extends StatelessWidget {
  const _StageBlock({required this.stage, required this.mine});

  final H2hCupStageDto stage;

  /// Whether the path is the caller's own (false: he only watches it).
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${h2hCupRoundName(stage.round)} · ${h2hCupPhaseName(stage.phase)}'
            '${stage.day == null ? '' : ' · ${h2hDayLabel(stage.day!)}'}',
            key: Key('h2h.cup.stage.${stage.round}'),
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
                    ? (mine
                          ? 'لا تُلعب هذه المرحلة في مسارك'
                          : 'لا تُلعب هذه المرحلة في هذا المسار')
                    : h2hCupWaitingLine(stage),
                style: context.text.bodySmall?.copyWith(color: t.textMuted),
              ),
            ),
          for (final H2hCupPairDto pair in stage.pairs)
            _PairRow(stage: stage, pair: pair),
          if (stage.bye != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'تأهل مباشرة: ${h2hCupNameOf(stage.bye!)}',
                key: Key('h2h.cup.bye.${stage.round}'),
                style: context.text.bodySmall?.copyWith(
                  color: stage.bye!.isMe ? t.gold : t.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  const _PairRow({required this.stage, required this.pair});

  final H2hCupStageDto stage;
  final H2hCupPairDto pair;

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
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            key: Key('h2h.cup.pair.${stage.round}.${pair.slot}'),
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
                  pair.decided
                      ? '${pair.homePoints ?? 0} - ${pair.awayPoints ?? 0}'
                      : 'ضد',
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
          if (pair.decided)
            Text(
              pair.winnerUserId == null
                  ? h2hCupOutcomeName(pair.outcome)
                  : '${h2hCupNameOf(homeWon ? pair.home : pair.away)} · '
                        '${h2hCupOutcomeName(pair.outcome)}',
              key: Key('h2h.cup.outcome.${stage.round}.${pair.slot}'),
              style: context.text.bodySmall?.copyWith(color: t.textMuted),
            ),
        ],
      ),
    );
  }
}

class _TitleLine extends StatelessWidget {
  const _TitleLine({required this.title});

  final H2hCupTitleDto title;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupPlayerDto? champion = title.champion;
    return Text(
      champion == null
          ? 'اللقب شاغر في هذا المسار'
          : champion.isMe
          ? 'أنت بطل هذا المسار'
          : 'بطل المسار: ${h2hCupNameOf(champion)}',
      key: const Key('h2h.cup.titleLine'),
      style: context.text.titleSmall?.copyWith(
        color: t.gold,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
