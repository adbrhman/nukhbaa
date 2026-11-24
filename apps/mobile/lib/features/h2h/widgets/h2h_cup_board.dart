// NK315_03
/// لوحة كأس النخبة لكل لاعب ومشرف (`GET /me/h2h-cup/board`): المسارات
/// الثلاثة، ولكل مسار مراحله وأزواجه ومبارياته، وتوقع اللاعبَين على كل
/// مباراة.
///
/// **توقع الخصم للخادم.** يصل توقع لاعب آخر بعد انطلاق مباراته فقط؛ قبلها
/// يرسل الخادم جانبًا محجوبًا لا يقول حتى هل توقّع صاحبه، فتكتب اللوحة
/// «تظهر بعد انطلاق المباراة» ولا تقرأ الساعة ولا تخمّن شيئًا. جانب لاعب
/// ظاهر بلا توقع يعني أنه لم يتوقع. لا يُحسب هنا نقاط ولا يُحسم زوج.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../competition/team_registry.dart';
import '../h2h_cup_texts.dart';
import '../h2h_providers.dart';
import '../h2h_texts.dart';

/// لوحة الكأس: تحميل، أو رسالة فارغة قبل قيام الكأس، أو المسارات.
class H2hCupBoardView extends ConsumerWidget {
  /// ينشئ اللوحة.
  const H2hCupBoardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<H2hCupBoardDto> board = ref.watch(h2hCupBoardProvider);
    return board.when(
      loading: () => const Padding(
        key: Key('h2h.cupBoard.loading'),
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => _Message(
        key: const Key('h2h.cupBoard.error'),
        text: h2hCupBoardLoadFailed,
        action: TextButton(
          key: const Key('h2h.cupBoard.retry'),
          onPressed: () => ref.invalidate(h2hCupBoardProvider),
          child: const Text(h2hCupBoardRetry),
        ),
      ),
      data: (H2hCupBoardDto data) {
        if (data.paths.isEmpty) {
          return const _Message(
            key: Key('h2h.cupBoard.empty'),
            text: h2hCupBoardEmpty,
          );
        }
        final AppTokens t = context.tokens;
        final String? month = data.monthStart;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppCard(
            key: const Key('h2h.cupBoard'),
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
                        key: const Key('h2h.cupBoard.title'),
                        style: context.text.titleMedium?.copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (month != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      h2hMonthLabel(month),
                      key: const Key('h2h.cupBoard.month'),
                      style: context.text.bodySmall?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                for (final H2hCupBoardPathDto path in data.paths)
                  _PathBlock(path: path),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A short message in a card: the empty state or a failed read.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, super.key});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: t.textSecondary),
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

/// One path of the cup with its stages and, once decided, its title.
class _PathBlock extends StatelessWidget {
  const _PathBlock({required this.path});

  final H2hCupBoardPathDto path;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupTitleDto? title = path.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            h2hCupPathName(path.place),
            key: Key('h2h.cupBoard.path.${path.place}'),
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                h2hCupBoardTitleLine(title),
                key: Key('h2h.cupBoard.title.${path.place}'),
                style: context.text.titleSmall?.copyWith(
                  color: t.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          for (final H2hCupBoardStageDto stage in path.stages)
            _StageBlock(place: path.place, stage: stage),
        ],
      ),
    );
  }
}

/// One stage: its heading, its pairs, and the qualifier left without one.
class _StageBlock extends StatelessWidget {
  const _StageBlock({required this.place, required this.stage});

  final int place;
  final H2hCupBoardStageDto stage;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupPlayerDto? bye = stage.bye;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${h2hCupRoundName(stage.round)} · ${h2hCupPhaseName(stage.phase)}'
            '${stage.day == null ? '' : ' · ${h2hDayLabel(stage.day!)}'}',
            key: Key('h2h.cupBoard.stage.$place.${stage.round}'),
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
                key: Key('h2h.cupBoard.stage.$place.${stage.round}.empty'),
                style: context.text.bodySmall?.copyWith(color: t.textMuted),
              ),
            ),
          for (final H2hCupBoardPairDto pair in stage.pairs)
            _PairBlock(place: place, stage: stage, pair: pair),
          if (bye != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'تأهل مباشرة: ${h2hCupNameOf(bye)}',
                key: Key('h2h.cupBoard.bye.$place.${stage.round}'),
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

/// One pair: the two players, how it ended, and the fixtures they predicted.
class _PairBlock extends StatelessWidget {
  const _PairBlock({
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
    final String prefix =
        'h2h.cupBoard.pair.$place.${stage.round}.${pair.slot}';
    final String result = h2hCupBoardPairResult(pair);
    TextStyle? side(H2hCupPlayerDto p) => context.text.bodyMedium?.copyWith(
      color: p.isMe ? t.gold : t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    return Container(
      key: Key(prefix),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
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
              Expanded(
                child: Text(
                  h2hCupNameOf(pair.home),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: side(pair.home),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: side(pair.away),
                ),
              ),
            ],
          ),
          if (result.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                result,
                key: Key('$prefix.result'),
                style: context.text.bodySmall?.copyWith(color: t.textMuted),
              ),
            ),
          for (final H2hCupBoardFixtureDto fixture in pair.fixtures)
            _FixtureTile(
              keyPrefix: '$prefix.fixture.${fixture.fixtureId}',
              pair: pair,
              fixture: fixture,
            ),
        ],
      ),
    );
  }
}

/// One fixture: the match and its state, then the two players' sides.
class _FixtureTile extends StatelessWidget {
  const _FixtureTile({
    required this.keyPrefix,
    required this.pair,
    required this.fixture,
  });

  final String keyPrefix;
  final H2hCupBoardPairDto pair;
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
    return Container(
      key: Key(keyPrefix),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: t.border),
      ),
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
          const SizedBox(height: AppSpacing.xs),
          Text(
            h2hFixtureStateLabel(f.state),
            key: Key('$keyPrefix.state'),
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _SideBox(
                  keyPrefix: '$keyPrefix.home',
                  player: pair.home,
                  side: f.homeSide,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SideBox(
                  keyPrefix: '$keyPrefix.away',
                  player: pair.away,
                  side: f.awaySide,
                ),
              ),
            ],
          ),
          if (f.state == 'void') ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              h2hCupBoardVoidNote,
              key: Key('$keyPrefix.void'),
              style: context.text.bodySmall?.copyWith(color: t.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One player's side of a fixture: his name, then his pick, or that it is
/// withheld until kickoff, or that he did not predict.
class _SideBox extends StatelessWidget {
  const _SideBox({
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
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.lock_outline_rounded, size: 16, color: t.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              h2hCupPickHidden,
              key: Key('$keyPrefix.hidden'),
              style: context.text.labelMedium?.copyWith(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    } else if (pick == null) {
      body = Text(
        player.isMe ? h2hCupNoPickMine : h2hCupNoPickOther,
        key: Key('$keyPrefix.none'),
        style: context.text.titleSmall?.copyWith(
          color: t.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      );
    } else {
      final String extras = h2hCupPickExtras(pick);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
    return Container(
      key: Key(keyPrefix),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: AppRadius.brSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            player.isMe
                ? '${h2hCupNameOf(player)} (أنت)'
                : h2hCupNameOf(player),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: player.isMe ? t.gold : t.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          body,
        ],
      ),
    );
  }
}
