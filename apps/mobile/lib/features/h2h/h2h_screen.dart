/// The head-to-head league tab (دوري المواجهات, migration 0100).
///
/// Everything drawn here is the server's: the state of the month, the
/// table's order and numbers, each round's opponent, points and result, and
/// the two zones (`GET /me/h2h-league`). The client names them and nothing
/// else -- it never sorts, sums or decides a result (Axioms 2/5).
///
/// Before the caller holds a seat (the league has not opened, the draw is
/// still to come, or they are outside it) the tab explains why and lists
/// the rules; once seated it shows the division, the match that matters now,
/// the group's table and every round of the month.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_tab_header.dart';
import '../../core/ui/user_avatar.dart';
import '../competition/widgets/async_list_view.dart';
import 'h2h_providers.dart';
import 'h2h_texts.dart';

/// The المواجهات tab.
class H2hScreen extends ConsumerWidget {
  /// Creates the tab.
  const H2hScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // The tab's name at the start, like every tab (UI-20).
      appBar: const AppTabHeader(title: Text(h2hTitle, key: Key('h2h.title'))),
      // The shell's bottom bar floats over the page (`extendBody`), so the
      // list stops above it -- the same SafeArea the other tabs use.
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myH2hLeagueProvider);
            try {
              await ref.read(myH2hLeagueProvider.future);
            } on Object {
              // The failure shows through the page; the pull still ends.
            }
          },
          child: AsyncObjectView<MyH2hLeagueDto>(
            value: ref.watch(myH2hLeagueProvider),
            onRetry: () => ref.invalidate(myH2hLeagueProvider),
            builder: (BuildContext context, MyH2hLeagueDto league) => ListView(
              key: const Key('h2h.list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                104,
              ),
              children: league.state == 'open'
                  ? _openMonth(league)
                  : _waiting(league),
            ),
          ),
        ),
      ),
    );
  }

  /// A month without a seat for the caller: why, then the rules.
  static List<Widget> _waiting(MyH2hLeagueDto league) => <Widget>[
    _StateCard(league: league),
    const SizedBox(height: AppSpacing.lg),
    const _RulesCard(),
  ];

  /// The caller's seated month.
  static List<Widget> _openMonth(MyH2hLeagueDto league) {
    H2hStandingDto? me;
    for (final H2hStandingDto s in league.standings) {
      if (s.isMe) me = s;
    }
    return <Widget>[
      _DivisionBanner(league: league),
      const SizedBox(height: AppSpacing.md),
      _FeaturedMatch(league: league, me: me),
      const SizedBox(height: AppSpacing.xl),
      const _SectionTitle(text: 'جدول المجموعة', key: Key('h2h.table.title')),
      const SizedBox(height: AppSpacing.sm),
      for (final H2hStandingDto s in league.standings) ...<Widget>[
        MergeSemantics(
          child: _StandingRow(
            standing: s,
            promoted: s.rank <= league.promotionZone,
            relegated:
                league.relegationZone > 0 &&
                s.rank > league.standings.length - league.relegationZone,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
      const SizedBox(height: AppSpacing.xl),
      const _SectionTitle(text: 'الجولات', key: Key('h2h.rounds.title')),
      const SizedBox(height: AppSpacing.sm),
      if (league.rounds.isEmpty)
        const _NoRounds()
      else
        for (final H2hRoundViewDto r in league.rounds.reversed) ...<Widget>[
          MergeSemantics(child: _RoundTile(round: r)),
          const SizedBox(height: AppSpacing.sm),
        ],
    ];
  }
}

/// Why the caller has no seat this month.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.league});

  final MyH2hLeagueDto league;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final ({String title, String body}) message = h2hStateMessage(
      league.state,
      league.startsOn,
    );
    return AppCard(
      key: Key('h2h.state.${league.state}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.shield_rounded, color: t.gold, size: 28),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  h2hLeagueName,
                  style: context.text.titleMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message.title,
            key: const Key('h2h.state.title'),
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message.body,
            style: context.text.bodyMedium?.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The rules, numbered.
class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return AppCard(
      key: const Key('h2h.rules'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'كيف يعمل الدوري؟',
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (int i = 0; i < h2hRules.length; i++) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${i + 1}.',
                  style: context.text.bodyMedium?.copyWith(
                    color: t.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    h2hRules[i],
                    style: context.text.bodyMedium?.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The division, the group, the pilot mark and the two zones.
class _DivisionBanner extends StatelessWidget {
  const _DivisionBanner({required this.league});

  final MyH2hLeagueDto league;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int level = league.division ?? 4;
    final Color accent = switch (level) {
      1 => t.gold,
      2 => t.silver,
      3 => t.bronze,
      _ => t.primary,
    };
    final int group = league.groupIndex ?? 0;
    final String name = level >= 4 || group > 0
        ? '${h2hDivisionName(level)} · ${h2hGroupName(group)}'
        : h2hDivisionName(level);
    final TextStyle? zoneStyle = context.text.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Container(
      key: const Key('h2h.banner'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.shield_rounded, color: accent, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  name,
                  key: const Key('h2h.division'),
                  style: context.text.titleMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (league.myRank > 0) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    'ترتيبك ${league.myRank}',
                    key: const Key('h2h.myRank'),
                    textAlign: TextAlign.end,
                    style: context.text.labelLarge?.copyWith(
                      color: t.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            h2hMonthLabel(league.monthStart),
            style: context.text.labelMedium?.copyWith(color: t.textMuted),
          ),
          if (league.isPilot) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppBadge(
                key: Key('h2h.pilot'),
                label: 'شهر تجريبي: نتائجه لا تُحتسب',
                tone: AppBadgeTone.gold,
                icon: Icons.science_outlined,
              ),
            ),
          ],
          if (league.promotionZone > 0 ||
              league.relegationZone > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                if (league.promotionZone > 0)
                  Expanded(
                    child: Text(
                      'يصعد أول ${league.promotionZone}',
                      key: const Key('h2h.zone.up'),
                      style: zoneStyle?.copyWith(color: t.success),
                    ),
                  ),
                if (league.relegationZone > 0)
                  Expanded(
                    child: Text(
                      'يهبط آخر ${league.relegationZone}',
                      key: const Key('h2h.zone.down'),
                      textAlign: TextAlign.end,
                      style: zoneStyle?.copyWith(color: t.error),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The round that matters now: the one being played, else the next one,
/// else the last one played.
class _FeaturedMatch extends StatelessWidget {
  const _FeaturedMatch({required this.league, required this.me});

  final MyH2hLeagueDto league;
  final H2hStandingDto? me;

  H2hRoundViewDto? get _round {
    for (final H2hRoundViewDto r in league.rounds) {
      if (r.status == 'live') return r;
    }
    for (final H2hRoundViewDto r in league.rounds) {
      if (r.status == 'upcoming') return r;
    }
    for (final H2hRoundViewDto r in league.rounds.reversed) {
      if (r.status == 'settled') return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hRoundViewDto? round = _round;
    // With no round yet, the rounds list below says so once.
    if (round == null) return const SizedBox.shrink();
    final String heading = switch (round.status) {
      'live' => 'مواجهة اليوم · جارية',
      'upcoming' => 'المواجهة القادمة · ${h2hDayLabel(round.day)}',
      _ => 'آخر مواجهة · ${h2hDayLabel(round.day)}',
    };
    final String myName = (me?.displayName.trim().isEmpty ?? true)
        ? h2hUnnamed
        : me!.displayName;
    final String opponentName = round.opponentUserId == null
        ? h2hAverageOpponent
        : ((round.opponentName ?? '').trim().isEmpty
              ? h2hUnnamed
              : round.opponentName!);
    final bool scored = round.myPoints != null;
    final TextStyle? scoreStyle = context.text.headlineSmall?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    return AppCard(
      key: const Key('h2h.featured'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'الجولة ${round.round} · $heading',
            key: const Key('h2h.featured.heading'),
            style: context.text.labelLarge?.copyWith(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _Side(
                  name: myName,
                  avatarUrl: me?.avatarUrl,
                  average: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: scored
                    ? Row(
                        key: const Key('h2h.featured.score'),
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            h2hPointsLabel(round.myPoints!),
                            key: const Key('h2h.featured.mine'),
                            style: scoreStyle,
                          ),
                          Text(' - ', style: scoreStyle),
                          Text(
                            h2hPointsLabel(round.opponentPoints ?? 0),
                            key: const Key('h2h.featured.theirs'),
                            style: scoreStyle,
                          ),
                        ],
                      )
                    : Text(
                        'ضد',
                        style: context.text.titleSmall?.copyWith(
                          color: t.textMuted,
                        ),
                      ),
              ),
              Expanded(
                child: _Side(
                  name: opponentName,
                  avatarUrl: round.opponentAvatarUrl,
                  average: round.opponentUserId == null,
                ),
              ),
            ],
          ),
          if (round.result != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: _ResultBadge(
                result: round.result!,
                live: round.status == 'live',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One side of the featured match: picture and name.
class _Side extends StatelessWidget {
  const _Side({
    required this.name,
    required this.avatarUrl,
    required this.average,
  });

  final String name;
  final String? avatarUrl;
  final bool average;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Column(
      children: <Widget>[
        if (average)
          CircleAvatar(
            radius: 24,
            backgroundColor: t.surfaceHigh,
            child: Icon(Icons.groups_rounded, color: t.textSecondary),
          )
        else
          UserAvatar(displayName: name, avatarUrl: avatarUrl, size: 48),
        const SizedBox(height: AppSpacing.xs),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.labelLarge?.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A result in words, coloured; a live one says it is so far.
class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.result, required this.live});

  final String result;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final String label = h2hResultLabel(result);
    return AppBadge(
      label: live ? '$label حتى الآن' : label,
      tone: switch (result) {
        'win' => AppBadgeTone.success,
        'loss' => AppBadgeTone.danger,
        _ => AppBadgeTone.neutral,
      },
    );
  }
}

/// A section's heading.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.text.titleMedium?.copyWith(
      color: context.tokens.textPrimary,
      fontWeight: FontWeight.w800,
    ),
  );
}

/// The month holds no approved round yet.
class _NoRounds extends StatelessWidget {
  const _NoRounds();

  @override
  Widget build(BuildContext context) => AppCard(
    key: const Key('h2h.noRounds'),
    child: Text(
      'لم تُعتمد أي جولة بعد. تُعلن الجولة قبل يوم مبارياتها.',
      style: context.text.bodyMedium?.copyWith(
        color: context.tokens.textSecondary,
      ),
    ),
  );
}

/// One line of the group's table.
class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.standing,
    required this.promoted,
    required this.relegated,
  });

  final H2hStandingDto standing;
  final bool promoted;
  final bool relegated;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hStandingDto s = standing;
    final Color stripe = promoted
        ? t.success
        : (relegated ? t.error : Colors.transparent);
    final String name = s.displayName.trim().isEmpty
        ? h2hUnnamed
        : s.displayName;
    return Container(
      key: Key('h2h.standing.${s.userId}'),
      // The zone is a bar at the start of the line: a border on one side
      // only cannot be drawn with rounded corners.
      decoration: BoxDecoration(
        color: s.isMe ? t.surfaceHigh : t.surface,
        borderRadius: AppRadius.brMd,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Container(
            key: Key('h2h.standing.${s.userId}.zone'),
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: stripe,
              borderRadius: AppRadius.brXs,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 24),
            child: Text(
              '${s.rank}',
              key: Key('h2h.standing.${s.userId}.rank'),
              style: context.text.titleSmall?.copyWith(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          UserAvatar(displayName: name, avatarUrl: s.avatarUrl, size: 32),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: s.isMe ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'لعب ${s.played} · ${s.won}ف ${s.drawn}ت ${s.lost}خ'
                  ' · ${s.pointsFor} ن',
                  key: Key('h2h.standing.${s.userId}.record'),
                  style: context.text.labelSmall?.copyWith(color: t.textMuted),
                ),
                if (s.form.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  _FormStrip(form: s.form),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${s.leaguePoints}',
            key: Key('h2h.standing.${s.userId}.points'),
            style: context.text.titleMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The last results as small coloured dots, oldest first, read aloud as
/// words.
class _FormStrip extends StatelessWidget {
  const _FormStrip({required this.form});

  final List<String> form;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Semantics(
      label: 'آخر النتائج: ${form.map(h2hResultLabel).join('، ')}',
      excludeSemantics: true,
      child: Wrap(
        spacing: 3,
        children: <Widget>[
          for (final String r in form)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (r) {
                  'win' => t.success,
                  'loss' => t.error,
                  _ => t.textMuted,
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// One round of the month as the caller plays it.
class _RoundTile extends StatelessWidget {
  const _RoundTile({required this.round});

  final H2hRoundViewDto round;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String opponent = round.opponentUserId == null
        ? h2hAverageOpponent
        : ((round.opponentName ?? '').trim().isEmpty
              ? h2hUnnamed
              : round.opponentName!);
    final bool scored = round.myPoints != null;
    return Container(
      key: Key('h2h.round.${round.round}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'الجولة ${round.round} · ${h2hDayLabel(round.day)}',
                  style: context.text.labelMedium?.copyWith(color: t.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  'ضد $opponent',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (scored)
                  Text(
                    '${h2hPointsLabel(round.myPoints!)} مقابل '
                    '${h2hPointsLabel(round.opponentPoints ?? 0)}',
                    key: Key('h2h.round.${round.round}.score'),
                    textAlign: TextAlign.end,
                    style: context.text.titleSmall?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                if (round.result != null && round.status == 'settled')
                  _ResultBadge(result: round.result!, live: false)
                else
                  AppBadge(
                    key: Key('h2h.round.${round.round}.status'),
                    label: h2hRoundStatusLabel(round.status),
                    tone: round.status == 'live'
                        ? AppBadgeTone.primary
                        : AppBadgeTone.muted,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
