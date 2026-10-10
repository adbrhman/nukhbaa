/// Everyone's predictions for one day, as a table (decided 2026-09-28):
/// one row per player, one column per match of that day that has already
/// kicked off, each cell the player's predicted score with its verdict.
///
/// Visibility is the server's: the whole day is one read,
/// `GET /seasons/{id}/predictions-board?fixtures=` (2026-10-11, instead
/// of three requests per match), which passes every match through the
/// same kickoff gate as `GET .../fixtures/{fixtureId}/predictions`; only
/// started matches are asked for at all. The verdict comes from the
/// server's scores in that read; nothing is graded here. A column that
/// could not be read shows a red mark that says why and, tapped, asks
/// again.
///
/// Marks: points earned -> ✅ (⚡🔥 on a double); graded with no points ->
/// ❌; not graded yet -> no mark (⚡ alone on a double).
///
/// Tapping a prediction opens its reactions (migration 0094): anyone
/// else's can be reacted to; the viewer's own shows what it received.
/// Another player's prediction with none yet carries a faint reaction icon,
/// and a line above the table says so until the viewer's first reaction of
/// the day.
///
/// Admins also see each match's hero of the day (decided 2026-10-07): the
/// one player who alone called its exact score, named above the table and
/// marked in the cell, with a card to share from that prediction.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/screen_views.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/time/riyadh_day_turnover.dart';
import '../../../l10n/app_localizations.dart';
import '../../competition/team_catalog_index.dart';
import '../../competition/team_identity.dart';
import '../../history/prediction_lookup_providers.dart';
import '../current_month_fixtures_providers.dart';
import '../prediction_reactions_providers.dart';
import '../predictions_board_providers.dart';
import '../../auth/session_controller.dart';
import '../../auth/session_state.dart';
import 'day_hero_card.dart';
import 'fixtures_date_bar.dart';
import 'prediction_reaction_sheet.dart';

const double _nameWidth = 128;
const double _cellWidth = 116;
const double _headerHeight = 64;
const double _rowHeight = 46;

/// The table for the device-local day of [kickoffAt] (the day of the card
/// the viewer came from).
class FixturePredictionsBoardPage extends ConsumerStatefulWidget
    implements NamedScreen {
  @override
  String get screenName => ScreenNames.predictionsBoard;

  /// Creates the page for the day of [kickoffAt] (ISO-8601).
  const FixturePredictionsBoardPage({required this.kickoffAt, super.key});

  /// Kickoff of the card that opened the page; only its local day is used.
  final String? kickoffAt;

  @override
  ConsumerState<FixturePredictionsBoardPage> createState() =>
      _FixturePredictionsBoardPageState();
}

/// One column: a started match of the day.
final class _Column {
  const _Column({
    required this.fixture,
    required this.homeName,
    required this.awayName,
    required this.predictions,
    required this.scores,
    required this.loading,
    required this.failed,
    required this.errorText,
    required this.reactions,
    required this.onRetry,
    required this.onTouch,
  });

  final SeasonFixtureCardDto fixture;
  final String homeName;
  final String awayName;
  final Map<String, FixturePredictionDto> predictions;
  final Map<String, ParticipantFixtureScoreDto> scores;
  final bool loading;
  final bool failed;

  /// Why the column could not be read, in Arabic; null unless [failed].
  final String? errorText;

  /// The reactions each prediction received (migration 0094); null
  /// until read, or when the read failed.
  final PredictionReactionsDto? reactions;

  /// Reads the day's board again (the red mark's tap).
  final VoidCallback onRetry;

  /// A prediction of this match was tapped: its reactions follow the
  /// sheet's live read from now on.
  final VoidCallback onTouch;
}

/// One row: a player who predicted at least one of the day's started matches.
final class _Player {
  _Player(this.participantId, this.name);

  final String participantId;
  final String name;
  bool isMine = false;
  int points = 0;
}

class _FixturePredictionsBoardPageState
    extends ConsumerState<FixturePredictionsBoardPage> {
  String _query = '';

  /// Matches with a tapped prediction (see [_Column.onTouch]).
  final Set<String> _touched = <String>{};

  DateTime? get _day {
    final DateTime? kickoff = DateTime.tryParse(widget.kickoffAt ?? '');
    return kickoff == null ? null : RiyadhDayTurnover.dayKeyOf(kickoff);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final DateTime now = DateTime.now().toUtc();
    final DateTime? day = _day;

    final List<CurrentMonthFixtureItemDto> feed =
        ref.watch(currentMonthFixturesProvider).value ??
        const <CurrentMonthFixtureItemDto>[];
    final List<SeasonFixtureCardDto> started = <SeasonFixtureCardDto>[
      for (final CurrentMonthFixtureItemDto item in feed)
        if (_startedOnDay(item.fixture, day, now)) item.fixture,
    ]..sort((a, b) => (a.kickoffAt ?? '').compareTo(b.kickoffAt ?? ''));

    final Map<String, TeamDto>? catalogById = ref.watch(
      teamCatalogByIdProvider,
    );
    final Set<String> myParticipantIds = <String>{
      for (final FixturePredictionDto p
          in (ref.watch(myFixturePredictionsByFixtureProvider).value ??
                  const <String, FixturePredictionDto>{})
              .values)
        p.participantId,
    };

    // The whole day in one read per season (2026-10-11): the board used to
    // ask three routes per started match, 63 for a day of 21.
    final Map<String, PredictionsBoardKey> boardKeys = predictionsBoardKeys(
      started,
    );
    final List<_Column> columns = <_Column>[];
    for (final SeasonFixtureCardDto fixture in started) {
      final PredictionsBoardKey? key =
          boardKeys['${fixture.seasonId}/${fixture.fixtureId}'];
      if (key == null) continue;
      final AsyncValue<PredictionsBoardDto> board = ref.watch(
        predictionsBoardProvider(key),
      );
      final PredictionsBoardColumnDto? served = board.value?.of(
        fixture.fixtureId,
      );
      final bool refused = served?.errorCode != null;
      final bool loading = board.isLoading && (!board.hasValue || refused);
      final bool failed =
          !loading &&
          ((board.hasError && !board.hasValue) ||
              refused ||
              (board.hasValue && served == null));
      // Once a prediction of this match is tapped, its reactions are the
      // sheet's own live read, so a new reaction shows at once.
      final PredictionReactionsDto? reactions =
          _touched.contains(fixture.fixtureId)
          ? ref
                    .watch(
                      predictionReactionsProvider((
                        seasonId: fixture.seasonId,
                        fixtureId: fixture.fixtureId,
                      )),
                    )
                    .value ??
                served?.reactions
          : served?.reactions;
      columns.add(
        _Column(
          fixture: fixture,
          homeName: resolveTeamIdentity(
            catalog: null,
            catalogById: catalogById,
            teamId: fixture.homeTeamId,
            teamName: fixture.homeTeam,
          ).displayName,
          awayName: resolveTeamIdentity(
            catalog: null,
            catalogById: catalogById,
            teamId: fixture.awayTeamId,
            teamName: fixture.awayTeam,
          ).displayName,
          predictions: <String, FixturePredictionDto>{
            for (final FixturePredictionDto p
                in served?.predictions ?? const <FixturePredictionDto>[])
              p.participantId: p,
          },
          scores: <String, ParticipantFixtureScoreDto>{
            for (final ParticipantFixtureScoreDto s
                in served?.scores?.scores ??
                    const <ParticipantFixtureScoreDto>[])
              s.participantId: s,
          },
          loading: loading,
          failed: failed,
          errorText: failed
              ? predictionsBoardErrorText(
                  board.hasValue ? null : board.error,
                  served?.errorCode,
                )
              : null,
          reactions: reactions,
          onRetry: () => ref.invalidate(predictionsBoardProvider(key)),
          onTouch: () {
            if (!_touched.contains(fixture.fixtureId)) {
              setState(() => _touched.add(fixture.fixtureId));
            }
          },
        ),
      );
    }

    final Map<String, _Player> byId = <String, _Player>{};
    for (final _Column column in columns) {
      for (final FixturePredictionDto p in column.predictions.values) {
        final _Player player = byId.putIfAbsent(
          p.participantId,
          () => _Player(
            p.participantId,
            p.displayName.isEmpty
                ? l10n.fixturePredictionsUnnamed
                : p.displayName,
          ),
        );
        player.isMine = myParticipantIds.contains(p.participantId);
        player.points += column.scores[p.participantId]?.points ?? 0;
      }
    }
    final List<_Player> players =
        byId.values
            .where(
              (p) => _query.isEmpty || p.name.toLowerCase().contains(_query),
            )
            .toList()
          ..sort((a, b) {
            // The viewer first, then the most points today, then by name.
            if (a.isMine != b.isMine) return a.isMine ? -1 : 1;
            final int byPoints = b.points.compareTo(a.points);
            if (byPoints != 0) return byPoints;
            return a.name.compareTo(b.name);
          });

    // Admins only: the one player who alone called a match's exact score,
    // by the server's grade, is that match's hero of the day.
    final SessionState? session = ref.watch(sessionControllerProvider).value;
    final bool isAdmin =
        session is SessionAuthenticated && session.user.role == 'admin';
    final Map<String, DayHero> heroes = <String, DayHero>{};
    if (isAdmin) {
      for (final _Column column in columns) {
        final String? heroId = soloExactParticipant(column.scores.values);
        final FixturePredictionDto? call = heroId == null
            ? null
            : column.predictions[heroId];
        if (call == null) continue;
        heroes[column.fixture.fixtureId] = DayHero(
          fixtureId: column.fixture.fixtureId,
          participantId: call.participantId,
          playerName: call.displayName.isEmpty
              ? l10n.fixturePredictionsUnnamed
              : call.displayName,
          home: resolveTeamIdentity(
            catalog: null,
            catalogById: catalogById,
            teamId: column.fixture.homeTeamId,
            teamName: column.fixture.homeTeam,
          ),
          away: resolveTeamIdentity(
            catalog: null,
            catalogById: catalogById,
            teamId: column.fixture.awayTeamId,
            teamName: column.fixture.awayTeam,
          ),
          homeGoals: call.homeGoals,
          awayGoals: call.awayGoals,
          leagueName: column.fixture.leagueName,
        );
      }
    }

    // Until the viewer gives a first reaction on this day's matches, a line
    // says the predictions can be reacted to. Read from the server's own
    // tallies, so nothing is kept on the device; unknown while any read is
    // pending or failed, and then not shown.
    final bool showReactHint =
        byId.values.any((p) => !p.isMine) &&
        columns.every((c) => c.reactions != null) &&
        !columns.any((c) => c.reactions!.reactions.any((t) => t.mine != null));

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Text(l10n.fixturePredictionsTitle),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              key: const Key('fixturePredictions.search'),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.fixturePredictionsSearchHint,
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: AppSizes.iconMd,
                ),
                border: const OutlineInputBorder(
                  borderRadius: AppRadius.brButton,
                ),
              ),
            ),
          ),
          if (showReactHint)
            Padding(
              key: const Key('fixturePredictions.reactHint'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.add_reaction_outlined,
                    size: AppSizes.iconXs,
                    color: tokens.primaryText,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'اضغط على توقع أي لاعب لتتفاعل معه.',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: AppFontSize.s12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final DayHero hero in heroes.values) DayHeroBanner(hero: hero),
          Expanded(
            child: columns.isEmpty
                ? _Message(
                    key: const Key('fixturePredictions.noStarted'),
                    text: l10n.fixturePredictionsNoStarted,
                  )
                : byId.isEmpty && columns.every((c) => !c.loading)
                ? _Message(
                    key: const Key('fixturePredictions.empty'),
                    text: l10n.fixturePredictionsEmpty,
                  )
                : players.isEmpty && byId.isNotEmpty
                ? _Message(
                    key: const Key('fixturePredictions.noMatch'),
                    text: l10n.fixturePredictionsNoMatch,
                  )
                : _Board(columns: columns, players: players, heroes: heroes),
          ),
        ],
      ),
    );
  }

  static bool _startedOnDay(
    SeasonFixtureCardDto fixture,
    DateTime? day,
    DateTime nowUtc,
  ) {
    final DateTime? kickoff = DateTime.tryParse(fixture.kickoffAt ?? '');
    if (kickoff == null || day == null) return false;
    return !kickoff.toUtc().isAfter(nowUtc) &&
        isSameFixtureDay(RiyadhDayTurnover.dayKeyOf(kickoff), day);
  }
}

/// The table: player names stay put on the reading side while the match
/// columns scroll sideways; the whole table scrolls down.
class _Board extends StatelessWidget {
  const _Board({
    required this.columns,
    required this.players,
    required this.heroes,
  });

  final List<_Column> columns;
  final List<_Player> players;

  /// Each match's hero of the day, by fixture id; empty but for admins.
  final Map<String, DayHero> heroes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return SingleChildScrollView(
      key: const Key('fixturePredictions.board'),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _nameWidth,
            child: Column(
              children: <Widget>[
                _HeaderBox(
                  child: Text(
                    l10n.fixturePredictionsPlayerHeader,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.s13,
                    ),
                  ),
                ),
                for (final _Player player in players) _NameCell(player: player),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('fixturePredictions.columns'),
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      for (final _Column column in columns)
                        _MatchHeader(column: column),
                    ],
                  ),
                  for (final _Player player in players)
                    Row(
                      children: <Widget>[
                        for (final _Column column in columns)
                          _PredictionCell(
                            column: column,
                            player: player,
                            hero:
                                heroes[column.fixture.fixtureId]
                                        ?.participantId ==
                                    player.participantId
                                ? heroes[column.fixture.fixtureId]
                                : null,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBox extends StatelessWidget {
  const _HeaderBox({required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      width: width,
      height: _headerHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: child,
    );
  }
}

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.column});

  final _Column column;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextStyle style = TextStyle(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w700,
      fontSize: AppFontSize.s12,
    );
    return _HeaderBox(
      width: _cellWidth,
      child: Column(
        key: Key('fixturePredictions.header.${column.fixture.fixtureId}'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Home on the reading side, as on the card and in each cell.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  column.homeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              Text(' × ', style: style.copyWith(color: tokens.textMuted)),
              Flexible(
                child: Text(
                  column.awayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
          if (column.loading)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (column.failed)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Tooltip(
                message: column.errorText ?? '',
                child: InkWell(
                  key: Key(
                    'fixturePredictions.retry.${column.fixture.fixtureId}',
                  ),
                  onTap: column.onRetry,
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: AppSizes.iconXs,
                    color: tokens.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.player});

  final _Player player;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return Container(
      key: Key('fixturePredictions.row.${player.participantId}'),
      height: _rowHeight,
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: player.isMine ? tokens.primary.withValues(alpha: 0.12) : null,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Text(
        player.isMine ? l10n.fixturePredictionsMine(player.name) : player.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tokens.textPrimary,
          fontWeight: player.isMine ? FontWeight.w700 : FontWeight.w500,
          fontSize: AppFontSize.s13,
        ),
      ),
    );
  }
}

class _PredictionCell extends StatelessWidget {
  const _PredictionCell({
    required this.column,
    required this.player,
    this.hero,
  });

  final _Column column;
  final _Player player;

  /// Set for an admin on the hero of the day's cell.
  final DayHero? hero;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final FixturePredictionDto? prediction =
        column.predictions[player.participantId];
    final ParticipantFixtureScoreDto? score =
        column.scores[player.participantId];
    final TextStyle digits = TextStyle(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w800,
      fontSize: AppFontSize.s14,
    );
    final PredictionReactionTallyDto? tally = column.reactions?.of(
      player.participantId,
    );
    final Widget cell = Container(
      key: Key(
        'fixturePredictions.cell.${column.fixture.fixtureId}.${player.participantId}',
      ),
      width: _cellWidth,
      height: _rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: player.isMine ? tokens.primary.withValues(alpha: 0.12) : null,
        border: Border(
          bottom: BorderSide(color: tokens.border),
          left: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
        ),
      ),
      child: prediction == null
          ? Text('—', style: TextStyle(color: tokens.textMuted))
          // Scaled down rather than clipped when large text meets the
          // fixed row height.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // A Row follows the reading direction: the home goals
                      // sit on the home team's side of the header above.
                      Text('${prediction.homeGoals}', style: digits),
                      Text(' - ', style: TextStyle(color: tokens.textMuted)),
                      Text('${prediction.awayGoals}', style: digits),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        verdictMark(
                          isDouble: prediction.isDouble,
                          score: score,
                        ),
                        key: Key(
                          'fixturePredictions.mark.${column.fixture.fixtureId}.${player.participantId}',
                        ),
                        style: const TextStyle(fontSize: AppFontSize.s13),
                      ),
                      if (hero != null)
                        Icon(
                          Icons.emoji_events_rounded,
                          key: Key(
                            'fixturePredictions.heroMark.${column.fixture.fixtureId}.${player.participantId}',
                          ),
                          size: AppSizes.iconInline,
                          color: tokens.goldAccent,
                        ),
                    ],
                  ),
                  if (tally != null && tally.total > 0)
                    _ReactionSummary(
                      key: Key(
                        'fixturePredictions.reactions.${column.fixture.fixtureId}.${player.participantId}',
                      ),
                      tally: tally,
                    )
                  // Shows that the cell can be tapped to react.
                  else if (!player.isMine)
                    Icon(
                      Icons.add_reaction_outlined,
                      key: Key(
                        'fixturePredictions.reactable.${column.fixture.fixtureId}.${player.participantId}',
                      ),
                      size: AppSizes.iconInline,
                      color: tokens.textMuted,
                    ),
                ],
              ),
            ),
    );
    if (prediction == null) return cell;
    // Every prediction on the board can be reacted to (migration 0094);
    // the viewer's own shows what it received.
    return InkWell(
      onTap: () {
        column.onTouch();
        unawaited(
          showPredictionReactionSheet(
            context: context,
            seasonId: column.fixture.seasonId,
            fixtureId: column.fixture.fixtureId,
            participantId: player.participantId,
            playerName: player.name,
            homeName: column.homeName,
            awayName: column.awayName,
            homeGoals: prediction.homeGoals,
            awayGoals: prediction.awayGoals,
            isMine: player.isMine,
            hero: hero,
          ),
        );
      },
      child: cell,
    );
  }
}

/// What a prediction received, under its score: the kind given most, in
/// its own colour, and how many reactions in all, in blue when the viewer
/// gave one of them.
class _ReactionSummary extends StatelessWidget {
  const _ReactionSummary({required this.tally, super.key});

  final PredictionReactionTallyDto tally;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final Color color = tally.mine == null
        ? tokens.textSecondary
        : tokens.primaryText;
    final String? kind = leadingReactionKind(tally);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (kind != null)
          PredictionReactionGlyph(kind: kind, size: AppSizes.iconInline),
        const SizedBox(width: 2),
        Text(
          '${tally.total}',
          style: TextStyle(
            color: color,
            fontSize: AppFontSize.s11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The verdict beside a predicted score, from the server's grade alone:
/// points earned -> ✅ (⚡🔥 on a double); graded with no points -> ❌;
/// not graded yet -> nothing (⚡ alone on a double).
String verdictMark({
  required bool isDouble,
  required ParticipantFixtureScoreDto? score,
}) {
  if (score == null) return isDouble ? '⚡' : '';
  if (score.points > 0) return isDouble ? '⚡🔥' : '✅';
  return '❌';
}

class _Message extends StatelessWidget {
  const _Message({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: tokens.textSecondary),
        ),
      ),
    );
  }
}
