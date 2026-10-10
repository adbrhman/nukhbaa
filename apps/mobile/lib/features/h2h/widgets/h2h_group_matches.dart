/// The fourth section of a seated month: every match of a round in the
/// caller's group (`GET /me/h2h-league/rounds/{n}/matches`), the round
/// chosen from a list, the caller's match first.
///
/// Only names, pictures and stored points are shown -- nobody's prediction.
/// Who is ahead is the server's word: by points alone while a round is
/// live, the league's result once it is settled. Nothing is computed here
/// (Axioms 2/5).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_breakpoints.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/user_avatar.dart';
import '../h2h_providers.dart';
import '../h2h_round_screen.dart';
import '../h2h_texts.dart';
import 'h2h_next_match.dart';
import 'h2h_parts.dart';

/// Every match of the chosen round.
class H2hGroupMatches extends ConsumerStatefulWidget {
  /// Creates the section for [league].
  const H2hGroupMatches({required this.league, super.key});

  /// The month as the server sent it.
  final MyH2hLeagueDto league;

  @override
  ConsumerState<H2hGroupMatches> createState() => _H2hGroupMatchesState();
}

class _H2hGroupMatchesState extends ConsumerState<H2hGroupMatches> {
  int? _chosen;

  /// The round shown: the one chosen, else the one that matters now, else
  /// the last.
  H2hRoundViewDto? get _round {
    final List<H2hRoundViewDto> rounds = widget.league.rounds;
    if (rounds.isEmpty) return null;
    final int? chosen = _chosen;
    if (chosen != null) {
      for (final H2hRoundViewDto r in rounds) {
        if (r.round == chosen) return r;
      }
    }
    return h2hCurrentRound(widget.league) ?? rounds.last;
  }

  Future<void> _choose() async {
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: AppBreakpoints.tablet),
      builder: (BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            key: const Key('h2h.matches.sheet'),
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            children: <Widget>[
              for (final H2hRoundViewDto r in widget.league.rounds.reversed)
                ListTile(
                  key: Key('h2h.matches.pick.${r.round}'),
                  title: Text(
                    'الجولة ${r.round} · ${h2hDayLabel(r.day)}',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.tokens.textPrimary,
                      fontWeight: r.round == _round?.round
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: H2hStatusChip(status: r.status),
                  onTap: () => Navigator.of(context).pop(r.round),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _chosen = picked);
  }

  @override
  Widget build(BuildContext context) {
    final H2hRoundViewDto? round = _round;
    if (round == null) return const H2hNoRounds();
    final AppTokens t = context.tokens;
    final AsyncValue<H2hGroupRoundDto> value = ref.watch(
      myH2hGroupRoundProvider(round.round),
    );
    return Column(
      key: const Key('h2h.matches'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const H2hSectionTitle(
          text: 'مواجهات الجولة',
          key: Key('h2h.matches.title'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Material(
          color: t.surface,
          borderRadius: AppRadius.brMd,
          child: InkWell(
            key: const Key('h2h.matches.round'),
            borderRadius: AppRadius.brMd,
            onTap: _choose,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: AppRadius.brMd,
                border: Border.all(color: t.controlBorder),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'الجولة ${round.round} · ${h2hDayLabel(round.day)}',
                      key: const Key('h2h.matches.round.label'),
                      style: context.text.titleSmall?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  H2hStatusChip(status: round.status),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.expand_more_rounded, color: t.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...value.when(
          skipLoadingOnRefresh: false,
          loading: () => const <Widget>[
            Padding(
              key: Key('h2h.matches.loading'),
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (Object error, StackTrace _) => <Widget>[
            AppCard(
              key: const Key('h2h.matches.error'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'تعذّر تحميل مواجهات الجولة.',
                    style: context.text.bodyMedium?.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const Key('h2h.matches.retry'),
                      onPressed: () =>
                          ref.invalidate(myH2hGroupRoundProvider(round.round)),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          data: (H2hGroupRoundDto group) => <Widget>[
            for (int i = 0; i < group.matches.length; i++) ...<Widget>[
              MergeSemantics(
                child: H2hPairCard(
                  key: Key(
                    group.matches[i].homeIsMe || group.matches[i].awayIsMe
                        ? 'h2h.pair.mine'
                        : 'h2h.pair.$i',
                  ),
                  match: group.matches[i],
                  status: group.status,
                  round: group.round,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              'تظهر النقاط بعد انتهاء المباريات، ولا تظهر هنا توقعات أي لاعب.',
              key: const Key('h2h.matches.note'),
              style: context.text.bodySmall?.copyWith(color: t.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

/// One match of the round: two sides and their points.
///
/// Side by side at normal text; at larger text, or on a narrow screen, one
/// side per line, so a long name never squeezes the points.
class H2hPairCard extends StatelessWidget {
  /// Creates the card.
  const H2hPairCard({
    required this.match,
    required this.status,
    required this.round,
    super.key,
  });

  /// The match as the server sent it.
  final H2hGroupMatchDto match;

  /// The round's phase.
  final String status;

  /// The round's number, to open the caller's own match.
  final int round;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hGroupMatchDto m = match;
    final bool mine = m.homeIsMe || m.awayIsMe;
    final bool average = m.awayUserId == null;
    final String homeName = h2hNameOf(m.homeName);
    final String awayName = average
        ? h2hAverageOpponent
        : h2hNameOf(m.awayName);
    final String homePoints = m.homePoints == null
        ? '–'
        : h2hPointsLabel(m.homePoints!);
    final String awayPoints = m.awayPoints == null
        ? '–'
        : h2hPointsLabel(m.awayPoints!);
    final String state = switch (status) {
      'live' => 'جارية',
      'voided' => 'ملغاة',
      'settled' => switch (m.winner) {
        'home' => 'فوز $homeName',
        'away' => average ? 'فوز المتوسط' : 'فوز $awayName',
        'draw' => 'تعادل',
        'none' => 'خسارة للطرفين',
        _ => 'مكتملة',
      },
      _ => 'لم تبدأ',
    };
    final bool liveLead = status == 'live' && m.winner != null;
    final String liveLine = !liveLead
        ? state
        : switch (m.winner) {
            'home' => 'جارية · يتقدم $homeName',
            'away' => 'جارية · يتقدم $awayName',
            _ => 'جارية · متعادلان',
          };

    final Widget card = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool sideBySide =
            MediaQuery.textScalerOf(context).scale(10) <= 13 &&
            constraints.maxWidth >= 300;
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: mine ? t.surfaceHigh : t.surface,
            borderRadius: AppRadius.brMd,
            border: Border.all(
              color: mine ? t.primary.withValues(alpha: 0.7) : t.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (sideBySide)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Side(
                        name: homeName,
                        avatarUrl: m.homeAvatarUrl,
                        me: m.homeIsMe,
                        lead: m.winner == 'home',
                        average: false,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ScoreBox(
                      key: const Key('h2h.pair.score'),
                      home: homePoints,
                      away: awayPoints,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _Side(
                        name: awayName,
                        avatarUrl: m.awayAvatarUrl,
                        me: m.awayIsMe,
                        lead: m.winner == 'away',
                        average: average,
                        end: true,
                      ),
                    ),
                  ],
                )
              else ...<Widget>[
                _Line(
                  name: homeName,
                  avatarUrl: m.homeAvatarUrl,
                  points: homePoints,
                  me: m.homeIsMe,
                  lead: m.winner == 'home',
                  average: false,
                ),
                const SizedBox(height: AppSpacing.sm),
                _Line(
                  name: awayName,
                  avatarUrl: m.awayAvatarUrl,
                  points: awayPoints,
                  me: m.awayIsMe,
                  lead: m.winner == 'away',
                  average: average,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                liveLine,
                key: const Key('h2h.pair.state'),
                textAlign: TextAlign.center,
                style: context.text.labelMedium?.copyWith(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mine) return card;
    return Semantics(
      button: true,
      hint: 'تفاصيل المواجهة',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openH2hRound(context, round),
        child: card,
      ),
    );
  }
}

/// The two scores, side by side.
class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.home, required this.away, super.key});

  final String home;
  final String away;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextStyle? style = context.text.titleMedium?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: AppRadius.brSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(home, key: const Key('h2h.pair.home'), style: style),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Container(width: 1, height: 18, color: t.border),
          ),
          Text(away, key: const Key('h2h.pair.away'), style: style),
        ],
      ),
    );
  }
}

/// One side of a match side by side: picture over name.
class _Side extends StatelessWidget {
  const _Side({
    required this.name,
    required this.avatarUrl,
    required this.me,
    required this.lead,
    required this.average,
    this.end = false,
  });

  final String name;
  final String? avatarUrl;
  final bool me;
  final bool lead;
  final bool average;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        _Picture(name: name, avatarUrl: avatarUrl, average: average),
        const SizedBox(height: AppSpacing.xs),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: end ? TextAlign.end : TextAlign.start,
          style: context.text.bodyMedium?.copyWith(
            color: t.textPrimary,
            fontWeight: lead || me ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        if (me)
          Text(
            'أنت',
            style: context.text.labelSmall?.copyWith(color: t.primaryText),
          ),
      ],
    );
  }
}

/// One side of a match on its own line: picture, name, points.
class _Line extends StatelessWidget {
  const _Line({
    required this.name,
    required this.avatarUrl,
    required this.points,
    required this.me,
    required this.lead,
    required this.average,
  });

  final String name;
  final String? avatarUrl;
  final String points;
  final bool me;
  final bool lead;
  final bool average;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Row(
      children: <Widget>[
        _Picture(name: name, avatarUrl: avatarUrl, average: average),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            me ? '$name (أنت)' : name,
            style: context.text.bodyMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: lead || me ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          points,
          style: context.text.titleMedium?.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// A member's picture, or the group average as a group.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.name,
    required this.avatarUrl,
    required this.average,
  });

  final String name;
  final String? avatarUrl;
  final bool average;

  @override
  Widget build(BuildContext context) {
    if (!average) {
      return UserAvatar(displayName: name, avatarUrl: avatarUrl, size: 32);
    }
    final AppTokens t = context.tokens;
    return CircleAvatar(
      radius: 16,
      backgroundColor: t.surfaceElevated,
      child: Icon(Icons.groups_rounded, size: 18, color: t.textSecondary),
    );
  }
}
