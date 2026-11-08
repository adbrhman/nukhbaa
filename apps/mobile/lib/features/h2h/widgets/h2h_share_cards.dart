/// صور دوري المواجهات التي تخرج من التطبيق إلى القروب والقناة (طلب المالك
/// 2026-11-08): نتائج مباريات يوم الجولة في صورة واحدة، ومواجهات اللاعبين في
/// الجولة (مجموعة أو المجموعات الأربع)، وترتيب مجموعة أو المجموعات الأربع.
///
/// كل بطاقة تُرسم على الشاشة أولاً ثم تُلتقط كما رُئيت وتُسلَّم لقائمة
/// المشاركة (`share_plus`) عبر `sharePicture`، كبطاقة بطل اليوم. وتبقى بألوان
/// العلامة الداكنة أياً كان ثيم المشرف.
///
/// لا يُحسب هنا شيء ولا يُرتَّب: الأسماء والنقاط والمراكز والنتائج كما
/// وصلت من الخادم. ومواجهات جولة لم تُكشف بعد (سرّية) لا تُرسم أبداً.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/web_links.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/time/riyadh_day_turnover.dart';
import '../../../core/ui/share_picture.dart';
import '../../../core/ui/team_logo.dart';
import '../../auth/sign_in_screen.dart' show kBrandLogoAsset;
import '../../competition/team_identity.dart';
import '../h2h_texts.dart';
import 'h2h_parts.dart' show h2hNameOf;

// الصورة تخرج من التطبيق فتحتفظ بألوان العلامة الداكنة أياً كان الثيم،
// مقروءة من AppColors كي لا تنحرف عنه.
const Color _navy = AppColors.background;
const Color _navyRaised = AppColors.surface;
const Color _navyHigh = AppColors.surfaceHigh;
const Color _gold = AppColors.gold;
const Color _white = AppColors.textPrimary;
const Color _muted = AppColors.textMuted;
const Color _line = AppColors.border;
const Color _up = AppColors.success;
const Color _down = AppColors.error;

/// قائمة المشاركة؛ الاختبار يمرّر قائمته. والهاتف يستعمل قائمته عند null.
final Provider<ShareSheet?> h2hShareSheetProvider = Provider<ShareSheet?>(
  (ref) => null,
);

/// ترتيب مجموعة واحدة على البطاقة.
final class H2hShareStandings {
  /// ينشئ بيانات [title] بجدولها ومنطقتيها.
  const H2hShareStandings({
    required this.title,
    required this.standings,
    required this.promotionZone,
    required this.relegationZone,
    required this.eliteDraw,
  });

  /// اسم المجموعة: «المجموعة 3».
  final String title;

  /// اللاعبون بترتيب الخادم.
  final List<H2hStandingDto> standings;

  /// مراكز القمة.
  final int promotionZone;

  /// مراكز القاع.
  final int relegationZone;

  /// شهر قرعة النخبة: القمة كأس لا صعود.
  final bool eliteDraw;
}

/// مواجهات جولة واحدة في مجموعة واحدة على البطاقة.
final class H2hShareMatches {
  /// ينشئ بيانات [title] بمواجهاتها.
  const H2hShareMatches({
    required this.title,
    required this.status,
    required this.matches,
  });

  /// اسم المجموعة.
  final String title;

  /// طور الجولة كما أرسله الخادم: `settled` أو `live` أو غيرهما.
  final String status;

  /// المواجهات كما أرسلها الخادم.
  final List<H2hGroupMatchDto> matches;
}

/// مباراة حقيقية من يوم الجولة على البطاقة.
final class H2hShareFixture {
  /// ينشئ سطراً لمباراة.
  const H2hShareFixture({
    required this.league,
    required this.home,
    required this.away,
    required this.state,
    this.homeGoals,
    this.awayGoals,
    this.timeLabel,
  });

  /// اسم البطولة.
  final String league;

  /// المضيف باسمه وشعاره.
  final ResolvedTeamIdentity home;

  /// الضيف باسمه وشعاره.
  final ResolvedTeamIdentity away;

  /// `final` انتهت، `live` جارية، `upcoming` لم تبدأ.
  final String state;

  /// أهداف المضيف إن عُرفت.
  final int? homeGoals;

  /// أهداف الضيف إن عُرفت.
  final int? awayGoals;

  /// موعد المباراة، لمن لم تبدأ.
  final String? timeLabel;
}

/// مجموعات النخبة الأربع من قراءة المشرف: الدرجة الأولى في شهر قرعة النخبة،
/// وفارغة في غيره.
List<H2hAdminGroupDto> h2hEliteGroupsOf(H2hAdminGroupsDto data) =>
    <H2hAdminGroupDto>[
      if (h2hUsesEliteDraw(data.monthStart))
        for (final H2hAdminGroupDto g in data.groups)
          if (g.division <= 1) g,
    ];

/// ترتيب [group] لبطاقة الصورة.
H2hShareStandings h2hShareStandingsOf(
  String monthStart,
  H2hAdminGroupDto group,
) => H2hShareStandings(
  title: h2hGroupTitle(monthStart, group.division, group.groupIndex),
  standings: group.standings,
  promotionZone: group.promotionZone,
  relegationZone: group.relegationZone,
  eliteDraw: h2hUsesEliteDraw(monthStart),
);

/// يوم الرياض لموعد [kickoffAt] مكتوباً `YYYY-MM-DD`، أو null.
String? _riyadhIsoDay(String? kickoffAt) {
  if (kickoffAt == null) return null;
  final DateTime? parsed = DateTime.tryParse(kickoffAt);
  if (parsed == null) return null;
  final DateTime day = RiyadhDayTurnover.riyadhDayOf(parsed);
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// مباريات يوم [day] (يوم الرياض `YYYY-MM-DD`) من قائمة الشهر، بترتيب
/// المواعيد: دون المخفية والتجريبية. النتيجة المسجَّلة أولاً، ثم النتيجة
/// الحية؛ ومن لم تبدأ بموعدها من [timeLabel].
List<H2hShareFixture> h2hShareFixturesOf({
  required List<CurrentMonthFixtureItemDto> items,
  required String day,
  required Map<String, TeamDto>? catalogById,
  required String Function(String iso) timeLabel,
}) {
  final List<CurrentMonthFixtureItemDto> ofDay = <CurrentMonthFixtureItemDto>[
    for (final CurrentMonthFixtureItemDto item in items)
      if (!item.fixture.hidden &&
          !item.fixture.isTest &&
          _riyadhIsoDay(item.fixture.kickoffAt) == day)
        item,
  ];
  ofDay.sort((CurrentMonthFixtureItemDto a, CurrentMonthFixtureItemDto b) {
    final DateTime x = DateTime.parse(a.fixture.kickoffAt!);
    final DateTime y = DateTime.parse(b.fixture.kickoffAt!);
    return x.compareTo(y);
  });
  return <H2hShareFixture>[
    for (final CurrentMonthFixtureItemDto item in ofDay)
      _fixtureRow(item, catalogById, timeLabel),
  ];
}

H2hShareFixture _fixtureRow(
  CurrentMonthFixtureItemDto item,
  Map<String, TeamDto>? catalogById,
  String Function(String iso) timeLabel,
) {
  final bool graded =
      item.resultHomeGoals != null && item.resultAwayGoals != null;
  final bool hasLive = item.liveHomeGoals != null && item.liveAwayGoals != null;
  final String state = graded || (hasLive && item.liveFinished == true)
      ? 'final'
      : (hasLive ? 'live' : 'upcoming');
  final String? kickoff = item.fixture.kickoffAt;
  return H2hShareFixture(
    league: item.fixture.leagueName ?? item.competitionName,
    home: resolveTeamIdentity(
      catalog: null,
      catalogById: catalogById,
      teamId: item.fixture.homeTeamId,
      teamName: item.fixture.homeTeam,
    ),
    away: resolveTeamIdentity(
      catalog: null,
      catalogById: catalogById,
      teamId: item.fixture.awayTeamId,
      teamName: item.fixture.awayTeam,
    ),
    state: state,
    homeGoals: graded ? item.resultHomeGoals : item.liveHomeGoals,
    awayGoals: graded ? item.resultAwayGoals : item.liveAwayGoals,
    timeLabel: kickoff == null ? null : timeLabel(kickoff),
  );
}

// ---------------------------------------------------------------------------
// الإطار المشترك

class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.width,
    required this.heading,
    required this.subheading,
    required this.child,
    super.key,
  });

  final double width;
  final String heading;
  final String subheading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: _navy,
          borderRadius: AppRadius.brCardLarge,
          border: Border.all(color: _gold.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: AppRadius.brMd,
                  child: Image.asset(
                    kBrandLogoAsset,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        heading,
                        style: const TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.s20,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subheading,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: AppFontSize.s13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
            const SizedBox(height: AppSpacing.md),
            const Text(
              'تطبيق توقعات النخبة | شاركنا الآن!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _gold,
                fontWeight: FontWeight.w700,
                fontSize: AppFontSize.s13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// إطار كتلة داخل البطاقة: مجموعة أو بطولة.
class _Block extends StatelessWidget {
  const _Block({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: _navyRaised,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

/// عرض الكتلة في بطاقات المجموعات: كتلتان جنباً إلى جنب عند الأربع.
const double _blockWidth = 340;

double _cardWidthFor(int blocks) => blocks > 1
    ? _blockWidth * 2 + AppSpacing.md + AppSpacing.lg * 2 + 2
    : _blockWidth + AppSpacing.lg * 2;

// ---------------------------------------------------------------------------
// الترتيب

/// بطاقة ترتيب مجموعة، أو المجموعات الأربع معاً.
class H2hStandingsShareCard extends StatelessWidget {
  /// ينشئ البطاقة لـ[groups].
  const H2hStandingsShareCard({
    required this.heading,
    required this.subheading,
    required this.groups,
    super.key,
  });

  /// عنوان الصورة.
  final String heading;

  /// سطر تحت العنوان: المجموعة والشهر.
  final String subheading;

  /// المجموعات، واحدة أو أكثر.
  final List<H2hShareStandings> groups;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      key: const Key('h2h.share.standings.card'),
      width: _cardWidthFor(groups.length),
      heading: heading,
      subheading: subheading,
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: <Widget>[
          for (final H2hShareStandings g in groups)
            SizedBox(
              width: _blockWidth,
              child: _StandingsBlock(group: g),
            ),
        ],
      ),
    );
  }
}

class _StandingsBlock extends StatelessWidget {
  const _StandingsBlock({required this.group});

  final H2hShareStandings group;

  static const double _rankWidth = 24;
  static const double _winWidth = 26;
  static const double _drawWidth = 32;
  static const double _lossWidth = 32;
  static const double _forWidth = 36;
  static const double _pointsWidth = 38;

  String get _zones {
    final List<String> parts = <String>[
      if (group.promotionZone > 0)
        group.eliteDraw
            ? h2hCupLegend(group.promotionZone)
            : 'يصعد أول ${group.promotionZone}',
      if (group.relegationZone > 0) 'يهبط آخر ${group.relegationZone}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final int count = group.standings.length;
    final bool played = group.standings.any((H2hStandingDto s) => s.played > 0);
    const TextStyle head = TextStyle(
      color: _muted,
      fontSize: AppFontSize.s11,
      fontWeight: FontWeight.w700,
    );
    Widget cell(String text, double width, TextStyle style) => SizedBox(
      width: width,
      child: Text(text, maxLines: 1, textAlign: TextAlign.center, style: style),
    );
    return _Block(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            group.title,
            style: const TextStyle(
              color: _gold,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.s16,
            ),
          ),
          if (_zones.isNotEmpty)
            Text(
              _zones,
              style: const TextStyle(color: _muted, fontSize: AppFontSize.s11),
            ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 4 + 6),
                cell('#', _rankWidth, head),
                const SizedBox(width: 6),
                const Expanded(child: Text('اللاعب', style: head)),
                cell('فوز', _winWidth, head),
                cell('تعادل', _drawWidth, head),
                cell('خسارة', _lossWidth, head),
                cell('التوقع', _forWidth, head),
                cell('النقاط', _pointsWidth, head),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (int i = 0; i < group.standings.length; i++)
            _row(group.standings[i], i, count, played),
        ],
      ),
    );
  }

  Widget _row(H2hStandingDto s, int index, int count, bool played) {
    final bool promoted = s.rank <= group.promotionZone;
    final bool relegated =
        group.relegationZone > 0 && s.rank > count - group.relegationZone;
    const TextStyle number = TextStyle(
      color: _muted,
      fontSize: AppFontSize.s12,
      fontWeight: FontWeight.w600,
    );
    Widget cell(String text, double width) => SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.center, style: number),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.transparent : _navyHigh,
        borderRadius: AppRadius.brSm,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: promoted ? _up : (relegated ? _down : Colors.transparent),
              borderRadius: AppRadius.brXs,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: _rankWidth,
            child: Text(
              played ? '${s.rank}' : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: promoted ? _gold : _white,
                fontWeight: FontWeight.w800,
                fontSize: AppFontSize.s13,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              h2hNameOf(s.displayName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _white,
                fontWeight: FontWeight.w700,
                fontSize: AppFontSize.s13,
              ),
            ),
          ),
          cell('${s.won}', _winWidth),
          cell('${s.drawn}', _drawWidth),
          cell('${s.lost}', _lossWidth),
          cell('${s.pointsFor}', _forWidth),
          SizedBox(
            width: _pointsWidth,
            child: Text(
              '${s.leaguePoints}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _white,
                fontWeight: FontWeight.w900,
                fontSize: AppFontSize.s14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// مواجهات اللاعبين

/// بطاقة مواجهات جولة: مجموعة، أو المجموعات الأربع معاً.
class H2hMatchesShareCard extends StatelessWidget {
  /// ينشئ البطاقة لـ[groups].
  const H2hMatchesShareCard({
    required this.heading,
    required this.subheading,
    required this.groups,
    super.key,
  });

  /// عنوان الصورة.
  final String heading;

  /// سطر تحت العنوان: اليوم والمجموعة.
  final String subheading;

  /// مواجهات كل مجموعة.
  final List<H2hShareMatches> groups;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      key: const Key('h2h.share.matches.card'),
      width: _cardWidthFor(groups.length),
      heading: heading,
      subheading: subheading,
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: <Widget>[
          for (final H2hShareMatches g in groups)
            SizedBox(
              width: _blockWidth,
              child: _MatchesBlock(group: g),
            ),
        ],
      ),
    );
  }
}

class _MatchesBlock extends StatelessWidget {
  const _MatchesBlock({required this.group});

  final H2hShareMatches group;

  @override
  Widget build(BuildContext context) {
    return _Block(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  group.title,
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                    fontSize: AppFontSize.s16,
                  ),
                ),
              ),
              Text(
                h2hRoundStatusLabel(group.status),
                style: const TextStyle(
                  color: _muted,
                  fontSize: AppFontSize.s12,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (int i = 0; i < group.matches.length; i++)
            _matchRow(group.matches[i], i),
        ],
      ),
    );
  }

  Widget _matchRow(H2hGroupMatchDto m, int index) {
    final bool average = m.awayUserId == null;
    final String home = h2hNameOf(m.homeName);
    final String away = average
        ? h2hAverageOpponent
        : '${h2hNameOf(m.awayName)}${m.awayAbsent ? ' (غائب)' : ''}';
    final String homePoints = m.homePoints == null
        ? '–'
        : h2hPointsLabel(m.homePoints!);
    final String awayPoints = m.awayPoints == null
        ? '–'
        : h2hPointsLabel(m.awayPoints!);
    final bool homeLead = m.winner == 'home' || m.winner == 'home_point';
    final bool awayLead = m.winner == 'away' || m.winner == 'away_point';
    TextStyle name(bool lead) => TextStyle(
      color: lead ? _gold : _white,
      fontWeight: lead ? FontWeight.w800 : FontWeight.w600,
      fontSize: AppFontSize.s13,
    );
    const TextStyle score = TextStyle(
      color: _white,
      fontWeight: FontWeight.w900,
      fontSize: AppFontSize.s14,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.transparent : _navyHigh,
        borderRadius: AppRadius.brSm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              home,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: name(homeLead),
            ),
          ),
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: AppRadius.brSm,
              border: Border.all(color: _line),
            ),
            // A long score (a half point, two digits) shrinks to fit the box
            // instead of overflowing it.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(homePoints, style: score),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(width: 1, height: 14, color: _line),
                  ),
                  Text(awayPoints, style: score),
                ],
              ),
            ),
          ),
          Expanded(
            child: Text(
              away,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: name(awayLead),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// نتائج المباريات الحقيقية

/// بطاقة نتائج مباريات يوم الجولة، مجمّعة بحسب البطولة.
class H2hFixturesShareCard extends StatelessWidget {
  /// ينشئ البطاقة لـ[fixtures].
  const H2hFixturesShareCard({
    required this.heading,
    required this.subheading,
    required this.fixtures,
    super.key,
  });

  /// عنوان الصورة.
  final String heading;

  /// سطر تحت العنوان: اليوم وكم انتهت.
  final String subheading;

  /// مباريات اليوم بترتيب المواعيد.
  final List<H2hShareFixture> fixtures;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<H2hShareFixture>> byLeague =
        <String, List<H2hShareFixture>>{};
    for (final H2hShareFixture f in fixtures) {
      byLeague.putIfAbsent(f.league, () => <H2hShareFixture>[]).add(f);
    }
    return _CardFrame(
      key: const Key('h2h.share.fixtures.card'),
      width: _blockWidth + AppSpacing.lg * 2 + 20,
      heading: heading,
      subheading: subheading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final MapEntry<String, List<H2hShareFixture>> e
              in byLeague.entries) ...<Widget>[
            _Block(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    e.key,
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w800,
                      fontSize: AppFontSize.s14,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (int i = 0; i < e.value.length; i++)
                    _FixtureRow(fixture: e.value[i], index: i),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FixtureRow extends StatelessWidget {
  const _FixtureRow({required this.fixture, required this.index});

  final H2hShareFixture fixture;
  final int index;

  @override
  Widget build(BuildContext context) {
    final H2hShareFixture f = fixture;
    const TextStyle score = TextStyle(
      color: _white,
      fontWeight: FontWeight.w900,
      fontSize: AppFontSize.s16,
    );
    final bool played = f.state != 'upcoming' && f.homeGoals != null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.transparent : _navyHigh,
        borderRadius: AppRadius.brSm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: _team(f.home, home: true)),
          SizedBox(
            width: 76,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (played)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text('${f.homeGoals}', style: score),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '-',
                          // NK219: the type scale, not a bare 14.
                          style: TextStyle(
                            color: _muted,
                            fontSize: AppFontSize.s14,
                          ),
                        ),
                      ),
                      Text('${f.awayGoals}', style: score),
                    ],
                  )
                else
                  Text(
                    f.timeLabel ?? '–',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.s12,
                    ),
                  ),
                if (f.state == 'live')
                  const Text(
                    'جارية',
                    style: TextStyle(
                      color: _up,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.s10,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _team(f.away, home: false)),
        ],
      ),
    );
  }

  /// فريق: الاسم على الطرف الخارجي والشعار بجانب النتيجة.
  Widget _team(ResolvedTeamIdentity team, {required bool home}) {
    final Widget name = Expanded(
      child: Text(
        team.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: home ? TextAlign.start : TextAlign.end,
        style: const TextStyle(
          color: _white,
          fontWeight: FontWeight.w700,
          fontSize: AppFontSize.s12,
        ),
      ),
    );
    final Widget logo = TeamLogo(
      displayName: team.displayName,
      size: 24,
      assetPath: team.assetPath,
      crestUrl: team.crestUrl,
      brandColor: team.brandColor,
    );
    return Row(
      children: home
          ? <Widget>[name, const SizedBox(width: 6), logo]
          : <Widget>[logo, const SizedBox(width: 6), name],
    );
  }
}

// ---------------------------------------------------------------------------
// المعاينة والمشاركة

/// معاينة البطاقة مع زرّي المشاركة والإغلاق.
class H2hShareDialog extends ConsumerStatefulWidget {
  /// ينشئ المعاينة لـ[card].
  const H2hShareDialog({
    required this.card,
    required this.shareText,
    required this.fileName,
    required this.keyPrefix,
    this.pixelRatio = 3,
    super.key,
  });

  /// البطاقة.
  final Widget card;

  /// النص المرافق للصورة.
  final String shareText;

  /// اسم ملف الصورة.
  final String fileName;

  /// بادئة مفاتيح الأزرار.
  final String keyPrefix;

  /// دقة الالتقاط: بطاقة المجموعات الأربع أطول فتُلتقط بدقة أقل كي لا
  /// تتجاوز حدّ الصورة في هواتف قديمة.
  final double pixelRatio;

  @override
  ConsumerState<H2hShareDialog> createState() => _H2hShareDialogState();
}

class _H2hShareDialogState extends ConsumerState<H2hShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;
  bool _shareFailed = false;

  Future<void> _share() async {
    setState(() {
      _sharing = true;
      _shareFailed = false;
    });
    try {
      final bool shared = await sharePicture(
        boundaryKey: _cardKey,
        text: widget.shareText,
        fileName: widget.fileName,
        pixelRatio: widget.pixelRatio,
        share: ref.read(h2hShareSheetProvider),
      );
      if (mounted && !shared) setState(() => _shareFailed = true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // البطاقة العريضة تُصغَّر في المعاينة فقط؛ الالتقاط بحجمها الكامل.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RepaintBoundary(key: _cardKey, child: widget.card),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    key: Key('${widget.keyPrefix}.share'),
                    onPressed: _sharing ? null : () => unawaited(_share()),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('مشاركة الصورة'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  key: Key('${widget.keyPrefix}.close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
            if (_shareFailed) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                sharePictureFailedText,
                key: Key('${widget.keyPrefix}.failed'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.errorText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _shareText(String heading, String subheading) =>
    '$heading · $subheading\nشاركنا في نُخبة: ${appSiteLink()}';

/// يفتح معاينة صورة ترتيب [groups] للمشاركة.
Future<void> showH2hStandingsShare(
  BuildContext context, {
  required String heading,
  required String subheading,
  required List<H2hShareStandings> groups,
}) => showDialog<void>(
  context: context,
  builder: (_) => H2hShareDialog(
    keyPrefix: 'h2h.share.standings',
    fileName: 'nukhba-h2h-standings.png',
    shareText: _shareText(heading, subheading),
    pixelRatio: groups.length > 2 ? 2 : 3,
    card: H2hStandingsShareCard(
      heading: heading,
      subheading: subheading,
      groups: groups,
    ),
  ),
);

/// يفتح معاينة صورة مواجهات [groups] للمشاركة.
Future<void> showH2hMatchesShare(
  BuildContext context, {
  required String heading,
  required String subheading,
  required List<H2hShareMatches> groups,
}) => showDialog<void>(
  context: context,
  builder: (_) => H2hShareDialog(
    keyPrefix: 'h2h.share.matches',
    fileName: 'nukhba-h2h-matches.png',
    shareText: _shareText(heading, subheading),
    pixelRatio: groups.length > 2 ? 2 : 3,
    card: H2hMatchesShareCard(
      heading: heading,
      subheading: subheading,
      groups: groups,
    ),
  ),
);

/// يفتح معاينة صورة نتائج [fixtures] للمشاركة.
Future<void> showH2hFixturesShare(
  BuildContext context, {
  required String heading,
  required String subheading,
  required List<H2hShareFixture> fixtures,
}) => showDialog<void>(
  context: context,
  builder: (_) => H2hShareDialog(
    keyPrefix: 'h2h.share.fixtures',
    fileName: 'nukhba-round-results.png',
    shareText: _shareText(heading, subheading),
    card: H2hFixturesShareCard(
      heading: heading,
      subheading: subheading,
      fixtures: fixtures,
    ),
  ),
);
