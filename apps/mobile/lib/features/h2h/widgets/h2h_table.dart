/// The second section of a seated month: the group's table, in the
/// server's order, with the caller's place pinned above it.
///
/// At normal text on a phone it is a compact table (won, drawn, lost,
/// prediction points, league points in columns). With the text enlarged a
/// column of numbers cannot keep its width, so each member becomes two
/// lines instead: the name, then the record spelled out.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/user_avatar.dart';
import '../h2h_texts.dart';
import 'h2h_parts.dart';

/// The record of [s] in words, as the two-line form shows it and as the
/// compact row reads aloud.
String h2hRecordLabel(H2hStandingDto s) =>
    'لعب ${s.played} · فوز ${s.won} · تعادل ${s.drawn} · خسارة ${s.lost}'
    ' · نقاط التوقع ${s.pointsFor}';

/// The group's table.
class H2hTable extends StatelessWidget {
  /// Creates the table for [league].
  const H2hTable({required this.league, super.key});

  /// The month as the server sent it.
  final MyH2hLeagueDto league;

  /// The narrowest width the compact columns fit at normal text.
  static const double compactMinWidth = 300;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool played = h2hAnyPlayed(league);
    final H2hStandingDto? me = h2hMyStanding(league);
    final int count = league.standings.length;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact =
            MediaQuery.textScalerOf(context).scale(10) <= 10 &&
            constraints.maxWidth >= compactMinWidth;
        return Column(
          key: Key(compact ? 'h2h.table.compact' : 'h2h.table.lines'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (me != null) ...<Widget>[
              _MyPlace(me: me, played: played, count: count),
              const SizedBox(height: AppSpacing.md),
            ],
            const H2hSectionTitle(
              text: 'جدول المجموعة',
              key: Key('h2h.table.title'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _Zones(league: league),
            if (!played) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'لم تُلعب أي جولة بعد: الكل متساوون، ويتحدد الترتيب بعد '
                'الجولة الأولى.',
                key: const Key('h2h.table.notPlayed'),
                style: context.text.bodySmall?.copyWith(color: t.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (compact) ...<Widget>[
              const _CompactHeader(),
              const SizedBox(height: AppSpacing.xs),
            ],
            for (final H2hStandingDto s in league.standings) ...<Widget>[
              MergeSemantics(
                child: _Row(
                  standing: s,
                  played: played,
                  compact: compact,
                  promoted: s.rank <= league.promotionZone,
                  relegated:
                      league.relegationZone > 0 &&
                      s.rank > count - league.relegationZone,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ],
        );
      },
    );
  }
}

/// The caller's place, pinned above the table.
class _MyPlace extends StatelessWidget {
  const _MyPlace({required this.me, required this.played, required this.count});

  final H2hStandingDto me;
  final bool played;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String name = h2hNameOf(me.displayName);
    return Container(
      key: const Key('h2h.table.me'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: t.primary.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: <Widget>[
          UserAvatar(displayName: name, avatarUrl: me.avatarUrl, size: 36),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'موقعك',
                  style: context.text.labelSmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
                Text(
                  played
                      ? 'المركز ${h2hRankLabel(me.rank, count)}'
                      : 'لم يتحدد الترتيب بعد',
                  key: const Key('h2h.table.me.rank'),
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${me.leaguePoints} ن',
            key: const Key('h2h.table.me.points'),
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

/// How many go up and down, as the server counted them.
class _Zones extends StatelessWidget {
  const _Zones({required this.league});

  final MyH2hLeagueDto league;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextStyle? style = context.text.labelMedium?.copyWith(
      color: t.textSecondary,
      fontWeight: FontWeight.w700,
    );
    Widget zone(String text, Color color, Key key) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(text, key: key, style: style),
        ),
      ],
    );
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        if (league.promotionZone > 0)
          zone(
            'يصعد أول ${league.promotionZone}',
            t.success,
            const Key('h2h.zone.up'),
          ),
        if (league.relegationZone > 0)
          zone(
            'يهبط آخر ${league.relegationZone}',
            t.error,
            const Key('h2h.zone.down'),
          ),
      ],
    );
  }
}

/// The compact table's column names.
class _CompactHeader extends StatelessWidget {
  const _CompactHeader();

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = context.text.labelSmall?.copyWith(
      color: context.tokens.textSecondary,
      fontWeight: FontWeight.w700,
    );
    Widget cell(String text, double width) => SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm,
          0,
          AppSpacing.md,
          0,
        ),
        child: Row(
          key: const Key('h2h.table.header'),
          children: <Widget>[
            const SizedBox(width: 4 + AppSpacing.sm),
            cell('#', _Row.rankWidth),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('اللاعب', style: style)),
            cell('ف', _Row.cellWidth),
            cell('ت', _Row.cellWidth),
            cell('خ', _Row.cellWidth),
            cell('ن.ت', _Row.forWidth),
            cell('ن', _Row.pointsWidth),
          ],
        ),
      ),
    );
  }
}

/// One member of the table.
class _Row extends StatelessWidget {
  const _Row({
    required this.standing,
    required this.played,
    required this.compact,
    required this.promoted,
    required this.relegated,
  });

  final H2hStandingDto standing;
  final bool played;
  final bool compact;
  final bool promoted;
  final bool relegated;

  static const double rankWidth = 32;
  static const double cellWidth = 28;
  static const double forWidth = 40;
  static const double pointsWidth = 32;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hStandingDto s = standing;
    final Color stripe = promoted
        ? t.success
        : (relegated ? t.error : Colors.transparent);
    final String name = h2hNameOf(s.displayName);
    final TextStyle? numberStyle = context.text.labelMedium?.copyWith(
      color: t.textSecondary,
      fontWeight: FontWeight.w600,
    );
    final Widget zone = Container(
      key: Key('h2h.standing.${s.userId}.zone'),
      width: 4,
      height: 32,
      decoration: BoxDecoration(color: stripe, borderRadius: AppRadius.brXs),
    );
    final Text rankText = Text(
      played ? '${s.rank}' : '—',
      key: Key('h2h.standing.${s.userId}.rank'),
      textAlign: TextAlign.center,
      style: context.text.titleSmall?.copyWith(
        color: t.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
    // A fixed column in the compact table; at large text it grows instead.
    final Widget rank = compact
        ? SizedBox(width: rankWidth, child: rankText)
        : ConstrainedBox(
            constraints: const BoxConstraints(minWidth: rankWidth),
            child: rankText,
          );
    final Widget points = Text(
      '${s.leaguePoints}',
      key: Key('h2h.standing.${s.userId}.points'),
      textAlign: TextAlign.center,
      style: context.text.titleMedium?.copyWith(
        color: t.textPrimary,
        fontWeight: FontWeight.w800,
      ),
    );
    final TextStyle? nameStyle = context.text.bodyMedium?.copyWith(
      color: t.textPrimary,
      fontWeight: s.isMe ? FontWeight.w800 : FontWeight.w600,
    );

    final Widget body;
    if (compact) {
      Widget cell(String text, double width) => SizedBox(
        width: width,
        child: Text(text, textAlign: TextAlign.center, style: numberStyle),
      );
      body = Row(
        children: <Widget>[
          zone,
          const SizedBox(width: AppSpacing.sm),
          rank,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              label: h2hRecordLabel(s),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
          ),
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                cell('${s.won}', cellWidth),
                cell('${s.drawn}', cellWidth),
                cell('${s.lost}', cellWidth),
                cell('${s.pointsFor}', forWidth),
              ],
            ),
          ),
          SizedBox(width: pointsWidth, child: points),
        ],
      );
    } else {
      body = Row(
        children: <Widget>[
          zone,
          const SizedBox(width: AppSpacing.sm),
          rank,
          const SizedBox(width: AppSpacing.sm),
          UserAvatar(displayName: name, avatarUrl: s.avatarUrl, size: 32),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  h2hRecordLabel(s),
                  key: Key('h2h.standing.${s.userId}.record'),
                  style: context.text.labelSmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
                if (s.form.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  _FormStrip(form: s.form),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          points,
        ],
      );
    }
    return Container(
      key: Key('h2h.standing.${s.userId}'),
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
      child: body,
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
