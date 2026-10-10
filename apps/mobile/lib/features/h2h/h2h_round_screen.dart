/// One round of the caller's head-to-head month in detail (تفاصيل
/// المواجهة, `GET /me/h2h-league/rounds/{n}`): the match, both sides'
/// counts, and the round's fixtures (مباريات الجولة) with both picks.
///
/// **The opponent's pick of a fixture is the server's to show.** It arrives
/// only once that fixture has kicked off by the server clock; until then
/// the server sends `theirs_hidden` and this page says "hidden until
/// kickoff". Nothing here reads the device clock to decide it, and nothing
/// is computed: points, counts and results are the server's (Axioms 2/5).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_card.dart';
import '../competition/widgets/async_list_view.dart';
import 'h2h_providers.dart';
import 'h2h_texts.dart';
import 'widgets/h2h_parts.dart';

/// Opens round [round] of the caller's month.
Future<void> openH2hRound(BuildContext context, int round) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => H2hRoundScreen(round: round)),
    );

/// Makes [child] open round [round] when tapped.
class H2hOpenRound extends StatelessWidget {
  /// Wraps [child].
  const H2hOpenRound({required this.round, required this.child, super.key});

  /// The round to open.
  final int round;

  /// What is tapped.
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    hint: 'تفاصيل المواجهة',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openH2hRound(context, round),
      child: child,
    ),
  );
}

/// The round's page.
class H2hRoundScreen extends ConsumerWidget {
  /// Creates the page for round [round].
  const H2hRoundScreen({required this.round, super.key});

  /// The round's number in the month.
  final int round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('تفاصيل المواجهة', key: Key('h2h.detail.title')),
      ),
      body: SafeArea(
        top: false,
        child: AsyncObjectView<MyH2hRoundDto>(
          value: ref.watch(myH2hRoundProvider(round)),
          onRetry: () => ref.invalidate(myH2hRoundProvider(round)),
          builder: (BuildContext context, MyH2hRoundDto detail) {
            final bool anyHidden = detail.fixtures.any(
              (H2hRoundFixtureDto f) => f.theirsHidden,
            );
            final bool anyVoid = detail.fixtures.any(
              (H2hRoundFixtureDto f) => f.state == 'void',
            );
            return ListView(
              key: const Key('h2h.detail.list'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                _MatchCard(detail: detail),
                const SizedBox(height: AppSpacing.md),
                _Totals(detail: detail),
                const SizedBox(height: AppSpacing.xl),
                H2hSectionTitle(
                  text: 'مباريات الجولة (${detail.fixtures.length})',
                  key: const Key('h2h.detail.fixtures.title'),
                ),
                if (anyHidden) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'توقّع خصمك في كل مباراة يظهر عند انطلاقها.',
                    key: const Key('h2h.detail.hiddenNote'),
                    style: context.text.bodySmall?.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                if (detail.fixtures.isEmpty)
                  AppCard(
                    key: const Key('h2h.detail.noFixtures'),
                    child: Text(
                      'لا مباريات في هذه الجولة.',
                      style: context.text.bodyMedium?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                for (final H2hRoundFixtureDto f in detail.fixtures) ...<Widget>[
                  MergeSemantics(
                    child: _FixtureTile(
                      fixture: f,
                      average: detail.opponentUserId == null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (anyVoid) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'المباراة المؤجلة أو التي خرجت من يوم الجولة لا تُحتسب '
                    'لأيٍّ من الطرفين.',
                    key: const Key('h2h.detail.voidNote'),
                    style: context.text.bodySmall?.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The two sides, the points and the result.
class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.detail});

  final MyH2hRoundDto detail;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool average = detail.opponentUserId == null;
    final TextStyle? scoreStyle = context.text.headlineSmall?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    return AppCard(
      key: const Key('h2h.detail.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  'الجولة ${detail.round} · ${h2hDayLabel(detail.day)}',
                  key: const Key('h2h.detail.heading'),
                  style: context.text.labelLarge?.copyWith(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              H2hStatusChip(
                key: const Key('h2h.detail.status'),
                status: detail.status,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Expanded(
                child: H2hSide(name: 'أنت', avatarUrl: null, average: false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Center(
                    child: detail.myPoints == null
                        ? Text(
                            'ضد',
                            style: context.text.titleSmall?.copyWith(
                              color: t.textSecondary,
                            ),
                          )
                        : Wrap(
                            key: const Key('h2h.detail.score'),
                            alignment: WrapAlignment.center,
                            children: <Widget>[
                              Text(
                                h2hPointsLabel(detail.myPoints!),
                                key: const Key('h2h.detail.mine'),
                                style: scoreStyle,
                              ),
                              Text(' - ', style: scoreStyle),
                              Text(
                                h2hPointsLabel(detail.opponentPoints ?? 0),
                                key: const Key('h2h.detail.theirs'),
                                style: scoreStyle,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              Expanded(
                child: H2hSide(
                  name: average
                      ? h2hAverageOpponent
                      : h2hNameOf(detail.opponentName),
                  avatarUrl: detail.opponentAvatarUrl,
                  average: average,
                ),
              ),
            ],
          ),
          if (detail.result != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: H2hResultBadge(
                result: detail.result!,
                live: detail.status == 'live',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Both sides' counts. The opponent's cover only kicked-off fixtures; the
/// group average has none.
class _Totals extends StatelessWidget {
  const _Totals({required this.detail});

  final MyH2hRoundDto detail;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hSideTotalsDto? theirs = detail.theirs;
    final TextStyle? head = context.text.labelMedium?.copyWith(
      color: t.textSecondary,
      fontWeight: FontWeight.w700,
    );
    final TextStyle? value = context.text.titleSmall?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    TableRow row(String label, String key, int mine, int? other) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(label, style: head),
        ),
        Text(
          '$mine',
          key: Key('h2h.detail.totals.$key.mine'),
          textAlign: TextAlign.center,
          style: value,
        ),
        Text(
          other == null ? '—' : '$other',
          key: Key('h2h.detail.totals.$key.theirs'),
          textAlign: TextAlign.center,
          style: value,
        ),
      ],
    );
    return AppCard(
      key: const Key('h2h.detail.totals'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  const SizedBox.shrink(),
                  Text('أنت', textAlign: TextAlign.center, style: head),
                  Text(
                    detail.opponentUserId == null
                        ? h2hAverageOpponent
                        : h2hNameOf(detail.opponentName),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: head,
                  ),
                ],
              ),
              row(
                'توقعات',
                'predicted',
                detail.mine.predicted,
                theirs?.predicted,
              ),
              row('نتائج دقيقة', 'exact', detail.mine.exact, theirs?.exact),
              row('مضاعفات', 'doubles', detail.mine.doubles, theirs?.doubles),
            ],
          ),
          if (theirs != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'أرقام الخصم للمباريات التي انطلقت فقط.',
              style: context.text.bodySmall?.copyWith(color: t.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One fixture of the round: the match, then both picks.
class _FixtureTile extends StatelessWidget {
  const _FixtureTile({required this.fixture, required this.average});

  final H2hRoundFixtureDto fixture;
  final bool average;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hRoundFixtureDto f = fixture;
    final bool scored = f.homeGoals != null && f.awayGoals != null;
    final bool voided = f.state == 'void';
    final String middle = scored
        ? h2hScoreline(f.homeGoals!, f.awayGoals!)
        : h2hKickoffTime(f.kickoffAt);
    final TextStyle? team = context.text.bodyMedium?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w700,
    );
    return Container(
      key: Key('h2h.fixture.${f.fixtureId}'),
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
                  f.homeTeam,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: team,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  middle,
                  key: Key('h2h.fixture.${f.fixtureId}.middle'),
                  style: context.text.titleSmall?.copyWith(
                    color: scored ? t.textPrimary : t.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  f.awayTeam,
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
            key: Key('h2h.fixture.${f.fixtureId}.state'),
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _PickBox(
                key: Key('h2h.fixture.${f.fixtureId}.mine'),
                label: 'توقعك',
                pick: f.mine,
                none: 'لم تتوقع',
              ),
              if (!average)
                f.theirsHidden
                    ? _HiddenBox(key: Key('h2h.fixture.${f.fixtureId}.hidden'))
                    : _PickBox(
                        key: Key('h2h.fixture.${f.fixtureId}.theirs'),
                        label: 'توقع الخصم',
                        pick: f.theirs,
                        none: 'لم يتوقع',
                      ),
            ],
          ),
          if (voided) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'لا تُحتسب: أُجّلت أو خرجت من يوم الجولة.',
              key: Key('h2h.fixture.${f.fixtureId}.void'),
              style: context.text.bodySmall?.copyWith(color: t.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One side's pick of a fixture: the scoreline, the double, the points.
class _PickBox extends StatelessWidget {
  const _PickBox({
    required this.label,
    required this.pick,
    required this.none,
    super.key,
  });

  final String label;
  final H2hPickDto? pick;
  final String none;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hPickDto? p = pick;
    final List<String> extras = <String>[
      if (p != null && p.isDouble) 'مضاعفة',
      if (p != null && p.exact) 'دقيقة',
      if (p?.points != null) '+${p!.points} ن',
    ];
    return _Box(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            p == null ? none : h2hScoreline(p.homeGoals, p.awayGoals),
            style: context.text.titleSmall?.copyWith(
              color: p == null ? t.textSecondary : t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (extras.isNotEmpty)
            Text(
              extras.join(' · '),
              style: context.text.labelSmall?.copyWith(color: t.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// The opponent's pick of a fixture that has not kicked off.
class _HiddenBox extends StatelessWidget {
  const _HiddenBox({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return _Box(
      label: 'توقع الخصم',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.lock_outline_rounded, size: 16, color: t.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              h2hHiddenPick,
              style: context.text.labelMedium?.copyWith(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small framed box under a label.
class _Box extends StatelessWidget {
  const _Box({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
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
            label,
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}
