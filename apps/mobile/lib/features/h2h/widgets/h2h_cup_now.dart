// NK332_02
/// «مواجهتك الآن» و«مباريات المواجهة» في تبويب الكأس (سكربت 332): بطاقة
/// زوج اللاعب في أول مرحلة غير محسومة من مساره، ثم شبكة مبارياته.
///
/// **كل رقم وكل توقع من الخادم.** نقاط الزوج من حقلَي الخادم `homePoints`
/// و`awayPoints`، فإن لم يصلا كُتب «ضد» ولا يُخترع رقم. وتوقع الخصم لمباراة
/// لم تبدأ يصل محجوباً فيُكتب «تظهر بعد انطلاق المباراة»؛ لا يُحسب شيء من
/// توقع محجوب، فلا يظهر شريط المسافة إلا حين يظهر التوقعان معاً. الودجة لا
/// تقرأ الساعة، وشارة «مباشر الآن» من حالة المباراة التي أرسلها الخادم.
///
/// الأرقام تُرسم كل رقم في نص مستقل داخل صف، فيبقى صاحب الأرض على يمين
/// الضيف في الواجهة العربية؛ نص واحد «2 - 1» يعرض الرقم الأول على اليسار.
/// الودجة بجانب لوحة الكأس القديمة وبلا ربط بها (التركيب في 336).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../competition/team_registry.dart';
import '../h2h_cup_texts.dart';
import '../h2h_texts.dart';

/// القسمان معاً لمن هو في الكأس: بطاقة مواجهته الآن ثم مباريات المواجهة.
/// لا تعرض شيئاً لمن يشاهد فقط، ولا لمن لا زوج له في مرحلته (تأهل مباشرة،
/// أو لم تُسحب المرحلة، أو خرج منها، أو انتهى مساره).
class H2hCupNowView extends StatelessWidget {
  /// ينشئ القسمين من لوحة الكأس.
  const H2hCupNowView({required this.board, super.key});

  /// لوحة الكأس كما جاءت من الخادم.
  final H2hCupBoardDto board;

  @override
  Widget build(BuildContext context) {
    final H2hCupNow? now = h2hCupBoardNow(board);
    if (now == null) return const SizedBox.shrink();
    final H2hCupBoardPairDto pair = now.pair;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        key: const Key('h2h.cupNow'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Heading(text: h2hCupNowHeading, keyName: 'h2h.cupNow.heading'),
          _DuelCard(now: now),
          if (pair.fixtures.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            H2hCupFixturesCard(pair: pair),
          ],
        ],
      ),
    );
  }
}

/// عنوان قسم.
class _Heading extends StatelessWidget {
  const _Heading({required this.text, required this.keyName});

  final String text;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        key: Key(keyName),
        style: context.text.titleSmall?.copyWith(
          color: context.tokens.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// بطاقة الزوج: المرحلة والشارة، واللاعبان ونقاطهما، والمباراة التي يقف
/// عندها الزوج.
class _DuelCard extends StatelessWidget {
  const _DuelCard({required this.now});

  final H2hCupNow now;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupBoardPairDto pair = now.pair;
    final H2hCupBoardFixtureDto? fixture = h2hCupBoardCurrentFixture(pair);
    final String? badge = fixture == null
        ? null
        : h2hCupBoardLiveBadge(fixture);
    return AppCard(
      key: const Key('h2h.cupNow.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (badge != null) ...<Widget>[
                _LiveBadge(text: badge),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  '${h2hCupRoundName(now.stage.round)} · '
                  '${h2hCupBoardPathName(now.path)}',
                  key: const Key('h2h.cupNow.stage'),
                  textAlign: badge == null ? TextAlign.start : TextAlign.end,
                  style: context.text.labelMedium?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: _Player(keyPrefix: 'h2h.cupNow.home', player: pair.home),
              ),
              Expanded(flex: 4, child: _Points(pair: pair)),
              Expanded(
                flex: 3,
                child: _Player(keyPrefix: 'h2h.cupNow.away', player: pair.away),
              ),
            ],
          ),
          if (fixture != null) _FixtureStrip(pair: pair, fixture: fixture),
        ],
      ),
    );
  }
}

/// شارة «مباشر الآن».
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      key: const Key('h2h.cupNow.badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: t.successContainer,
        borderRadius: AppRadius.brXxl,
      ),
      child: Text(
        text,
        style: context.text.labelSmall?.copyWith(
          color: t.successText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// لاعب في البطاقة: حرف اسمه، واسمه، و«أنت» تحت اسم المشاهِد نفسه.
class _Player extends StatelessWidget {
  const _Player({required this.keyPrefix, required this.player});

  final String keyPrefix;
  final H2hCupPlayerDto player;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String name = h2hCupNameOf(player);
    final String initial = String.fromCharCodes(name.runes.take(1));
    return Column(
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: player.isMe ? t.primary : t.surfaceHigh,
            ),
            child: Text(
              initial,
              textScaler: TextScaler.noScaling,
              style: context.text.titleMedium?.copyWith(
                color: player.isMe ? t.onPrimary : t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          name,
          key: Key('$keyPrefix.name'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: context.text.labelLarge?.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (player.isMe)
          Text(
            h2hCupYouLabel,
            key: const Key('h2h.cupNow.you'),
            style: context.text.labelSmall?.copyWith(color: t.primaryText),
          ),
      ],
    );
  }
}

/// نقاط الزوج من الخادم، أو «ضد» حين لا تصل.
class _Points extends StatelessWidget {
  const _Points({required this.pair});

  final H2hCupBoardPairDto pair;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int? home = pair.homePoints;
    final int? away = pair.awayPoints;
    if (home == null || away == null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          h2hCupVersus,
          key: const Key('h2h.cupNow.versus'),
          textAlign: TextAlign.center,
          style: context.text.titleMedium?.copyWith(color: t.textSecondary),
        ),
      );
    }
    final TextStyle? style = context.text.headlineSmall?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    return Column(
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$home',
                key: const Key('h2h.cupNow.homePoints'),
                style: style,
              ),
              Text(' : ', style: style),
              Text(
                '$away',
                key: const Key('h2h.cupNow.awayPoints'),
                style: style,
              ),
            ],
          ),
        ),
        Text(
          h2hCupDuelPointsLabel,
          key: const Key('h2h.cupNow.pointsLabel'),
          textAlign: TextAlign.center,
          style: context.text.labelSmall?.copyWith(color: t.textSecondary),
        ),
      ],
    );
  }
}

/// المباراة التي يقف عندها الزوج: فريقاها وموعدها، وتوقع كل لاعب، وشريط
/// المسافة بين التوقعين حين يظهران معاً.
class _FixtureStrip extends StatelessWidget {
  const _FixtureStrip({required this.pair, required this.fixture});

  final H2hCupBoardPairDto pair;
  final H2hCupBoardFixtureDto fixture;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupBoardFixtureDto f = fixture;
    final H2hPickDto? homePick = f.homeSide.pick;
    final H2hPickDto? awayPick = f.awaySide.pick;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: _Teams(
              key: const Key('h2h.cupNow.fixture.teams'),
              fixture: f,
              style: context.text.titleSmall?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${h2hCupKickoffLabel(f.kickoffAt)} · '
            '${h2hFixtureStateLabel(f.state)}',
            key: const Key('h2h.cupNow.fixture.when'),
            textAlign: TextAlign.center,
            style: context.text.labelMedium?.copyWith(
              color: f.state == 'live' ? t.successText : t.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _PickLine(
                  keyPrefix: 'h2h.cupNow.fixture.home',
                  player: pair.home,
                  side: f.homeSide,
                  alignEnd: false,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _PickLine(
                  keyPrefix: 'h2h.cupNow.fixture.away',
                  player: pair.away,
                  side: f.awaySide,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          if (homePick != null && awayPick != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              key: const Key('h2h.cupNow.fixture.bar'),
              children: <Widget>[
                Expanded(
                  child: _Segment(
                    color: pair.home.isMe ? t.primary : t.surfaceHigh,
                    first: true,
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: _Segment(
                    color: pair.away.isMe ? t.primary : t.surfaceHigh,
                    first: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${h2hCupPickGapLine(h2hCupPickGap(homePick, awayPick))} · '
              '$h2hCupSettlesAtFullTime',
              key: const Key('h2h.cupNow.fixture.distance'),
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(color: t.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// نصف شريط المسافة: يبدأ من حافة البداية أو ينتهي عند حافة النهاية.
class _Segment extends StatelessWidget {
  const _Segment({required this.color, required this.first});

  final Color color;
  final bool first;

  @override
  Widget build(BuildContext context) {
    const Radius round = Radius.circular(AppRadius.xs);
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadiusDirectional.horizontal(
          start: first ? round : Radius.zero,
          end: first ? Radius.zero : round,
        ),
      ),
    );
  }
}

/// فريقا المباراة في صف: صاحب الأرض على يمين الضيف في الواجهة العربية مهما
/// كان حرف الاسم، فلا يقلبهما نص واحد من حروف لاتينية.
class _Teams extends StatelessWidget {
  const _Teams({required this.fixture, this.style, super.key});

  final H2hCupBoardFixtureDto fixture;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            teamDisplayName(fixture.homeTeam),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
        Text(' – ', style: style),
        Flexible(
          child: Text(
            teamDisplayName(fixture.awayTeam),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// نتيجة من رقمين، كل رقم في نص مستقل: الأول على اليمين في العربية.
class _Score extends StatelessWidget {
  const _Score({required this.home, required this.away, this.style, super.key});

  final int home;
  final int away;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // NK332_04: the row shrinks to the cell it is in (a ten-goal pick in a
    // third of a 360px card at text x2 was wider than the cell).
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$home', style: style),
          Text(' - ', style: style),
          Text('$away', style: style),
        ],
      ),
    );
  }
}

/// توقع لاعب في شريط المباراة: «توقعك» أو «توقعه» ثم توقعه، أو أنه محجوب
/// حتى الانطلاق، أو أنه لم يتوقع.
class _PickLine extends StatelessWidget {
  const _PickLine({
    required this.keyPrefix,
    required this.player,
    required this.side,
    required this.alignEnd,
  });

  final String keyPrefix;
  final H2hCupPlayerDto player;
  final H2hCupBoardSideDto side;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hPickDto? pick = side.pick;
    final TextAlign align = alignEnd ? TextAlign.end : TextAlign.start;
    final Widget value;
    if (!side.revealed) {
      value = Text(
        h2hCupPickHidden,
        key: Key('$keyPrefix.hidden'),
        textAlign: align,
        style: context.text.labelMedium?.copyWith(
          color: t.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      );
    } else if (pick == null) {
      value = Text(
        player.isMe ? h2hCupNoPickMine : h2hCupNoPickOther,
        key: Key('$keyPrefix.none'),
        textAlign: align,
        style: context.text.titleSmall?.copyWith(
          color: t.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      );
    } else {
      value = _Score(
        key: Key('$keyPrefix.pick'),
        home: pick.homeGoals,
        away: pick.awayGoals,
        style: context.text.titleMedium?.copyWith(
          color: t.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          player.isMe ? h2hCupMyPickLabel : h2hCupTheirPickLabel,
          key: Key('$keyPrefix.label'),
          style: context.text.labelSmall?.copyWith(color: t.textMuted),
        ),
        value,
      ],
    );
  }
}

// NK334_04
/// مباريات المواجهة: رأس بالاسمين، ثم صف لكل مباراة (توقع، مباراة، توقع).
/// عامة لتفتحها شجرة الأدوار على الزوج المضغوط (سكربت 334): مفاتيحها كلها
/// تبدأ بـ [keyPrefix]، والأصل هو المفتاح القديم، فلا تتعارض مع بطاقة
/// «مواجهتك الآن» إن ظهرتا معاً.
class H2hCupFixturesCard extends StatelessWidget {
  /// ينشئ البطاقة لزوج.
  const H2hCupFixturesCard({
    required this.pair,
    this.keyPrefix = 'h2h.cupFixtures',
    super.key,
  });

  /// الزوج الذي تُعرض مبارياته.
  final H2hCupBoardPairDto pair;

  /// أول كل مفتاح في البطاقة وصفوفها.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextStyle? name = context.text.labelSmall?.copyWith(
      color: t.textSecondary,
    );
    final bool hasVoid = pair.fixtures.any(
      (H2hCupBoardFixtureDto f) => f.state == 'void',
    );
    return AppCard(
      key: Key(keyPrefix),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Text(
                  h2hCupNameOf(pair.home),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: name,
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  h2hCupFixturesHeading,
                  key: Key('$keyPrefix.heading'),
                  textAlign: TextAlign.center,
                  style: context.text.labelMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  h2hCupNameOf(pair.away),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: name,
                ),
              ),
            ],
          ),
          for (final H2hCupBoardFixtureDto f in pair.fixtures)
            _FixtureRow(
              keyPrefix: '$keyPrefix.row.${f.fixtureId}',
              pair: pair,
              fixture: f,
            ),
          if (hasVoid)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                h2hCupBoardVoidNote,
                key: Key('$keyPrefix.void'),
                style: context.text.bodySmall?.copyWith(color: t.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// صف مباراة: توقع صاحب الأرض، فالمباراة، فتوقع الضيف.
class _FixtureRow extends StatelessWidget {
  const _FixtureRow({
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
    return Container(
      key: Key(keyPrefix),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: _PickCell(
              keyPrefix: '$keyPrefix.home',
              player: pair.home,
              side: fixture.homeSide,
            ),
          ),
          Expanded(
            flex: 4,
            child: _MatchCell(keyPrefix: '$keyPrefix.match', fixture: fixture),
          ),
          Expanded(
            flex: 3,
            child: _PickCell(
              keyPrefix: '$keyPrefix.away',
              player: pair.away,
              side: fixture.awaySide,
            ),
          ),
        ],
      ),
    );
  }
}

/// وسط الصف: الفريقان، ثم النتيجة أو الموعد، ثم الحالة.
class _MatchCell extends StatelessWidget {
  const _MatchCell({required this.keyPrefix, required this.fixture});

  final String keyPrefix;
  final H2hCupBoardFixtureDto fixture;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final H2hCupBoardFixtureDto f = fixture;
    final int? homeGoals = f.homeGoals;
    final int? awayGoals = f.awayGoals;
    final TextStyle? line = context.text.labelLarge?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    return Column(
      children: <Widget>[
        _Teams(
          key: Key('$keyPrefix.teams'),
          fixture: f,
          style: context.text.labelMedium?.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        if (homeGoals != null && awayGoals != null)
          _Score(
            key: Key('$keyPrefix.score'),
            home: homeGoals,
            away: awayGoals,
            style: line,
          )
        else
          Text(
            h2hCupKickoffLabel(f.kickoffAt),
            key: Key('$keyPrefix.kickoff'),
            textAlign: TextAlign.center,
            style: line,
          ),
        Text(
          h2hFixtureStateLabel(f.state),
          key: Key('$keyPrefix.state'),
          textAlign: TextAlign.center,
          style: context.text.labelSmall?.copyWith(
            color: f.state == 'live' ? t.successText : t.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// خانة توقع في الصف: التوقع ونقاطه، أو أنه محجوب، أو أنه لم يتوقع.
class _PickCell extends StatelessWidget {
  const _PickCell({
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
    if (!side.revealed) {
      return Text(
        h2hCupPickHidden,
        key: Key('$keyPrefix.hidden'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: context.text.labelSmall?.copyWith(color: t.textSecondary),
      );
    }
    if (pick == null) {
      return Text(
        player.isMe ? h2hCupNoPickMine : h2hCupNoPickOther,
        key: Key('$keyPrefix.none'),
        textAlign: TextAlign.center,
        style: context.text.labelMedium?.copyWith(
          color: t.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    final String extras = h2hCupPickExtras(pick);
    return Column(
      children: <Widget>[
        _Score(
          key: Key('$keyPrefix.pick'),
          home: pick.homeGoals,
          away: pick.awayGoals,
          style: context.text.titleSmall?.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (extras.isNotEmpty)
          Text(
            extras,
            key: Key('$keyPrefix.extras'),
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
      ],
    );
  }
}
