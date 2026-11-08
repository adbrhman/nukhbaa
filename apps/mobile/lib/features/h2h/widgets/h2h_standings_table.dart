/// جدول ترتيب مجموعة في دوري المواجهات، كما تعرضه لوحة المشرف وعرض
/// مجموعات النخبة: عناوين الأعمدة بالكلمات (فوز، تعادل، خسارة، التوقع،
/// النقاط)، وصف لكل لاعب بترتيب الخادم، وشريط يبيّن منطقة الكأس أو الصعود
/// أو الهبوط، وسطر تحت الجدول يقول ما معنى الأرقام.
///
/// كل رقم وكل مركز من الخادم: هنا لا يُرتَّب شيء ولا يُجمع. مع تكبير الخط
/// أو في عرض ضيق يصير كل لاعب سطرين (الاسم ثم سجلّه بالكلمات) بدل أعمدة
/// لا تتسع.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../h2h_texts.dart';
import 'h2h_parts.dart' show h2hNameOf;
import 'h2h_table.dart' show h2hRecordLabel;

/// ما معنى الأرقام، تحت كل جدول.
const String h2hTableNote =
    'النقاط: فوز 3 وتعادل 1. التوقع: مجموع نقاط توقّعات اللاعب في '
    'الجولات المنتهية.';

/// جدول المجموعة.
class H2hStandingsTable extends StatelessWidget {
  /// ينشئ الجدول لـ[standings] بمنطقتي [promotionZone] و[relegationZone].
  const H2hStandingsTable({
    required this.standings,
    required this.promotionZone,
    required this.relegationZone,
    required this.eliteDraw,
    this.keyPrefix = 'h2h.standings',
    super.key,
  });

  /// اللاعبون بترتيب الخادم.
  final List<H2hStandingDto> standings;

  /// كم مركزاً من القمة (كأس النخبة أو الصعود).
  final int promotionZone;

  /// كم مركزاً من القاع يهبط.
  final int relegationZone;

  /// شهر قرعة النخبة: منطقة القمة كأس لا صعود.
  final bool eliteDraw;

  /// بادئة مفاتيح عناصر الجدول.
  final String keyPrefix;

  /// أضيق عرض يتسع للأعمدة بالخط العادي.
  static const double compactMinWidth = 270;

  static const double _rankWidth = 24;
  static const double _winWidth = 28;
  static const double _drawWidth = 34;
  static const double _lossWidth = 34;
  static const double _forWidth = 38;
  static const double _pointsWidth = 40;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    if (standings.isEmpty) {
      return Text(
        'لا لاعبين في هذه المجموعة',
        key: Key('$keyPrefix.empty'),
        style: context.text.bodySmall?.copyWith(color: t.textSecondary),
      );
    }
    final int count = standings.length;
    final bool played = standings.any((H2hStandingDto s) => s.played > 0);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact =
            MediaQuery.textScalerOf(context).scale(10) <= 11 &&
            constraints.maxWidth >= compactMinWidth;
        return Column(
          key: Key('$keyPrefix.${compact ? 'compact' : 'lines'}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _legend(context),
            if (compact) ...<Widget>[_header(context)],
            for (final H2hStandingDto s in standings)
              MergeSemantics(
                child: _row(
                  context,
                  s,
                  played: played,
                  compact: compact,
                  promoted: s.rank <= promotionZone,
                  relegated:
                      relegationZone > 0 && s.rank > count - relegationZone,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              h2hTableNote,
              key: Key('$keyPrefix.note'),
              style: context.text.labelSmall?.copyWith(color: t.textSecondary),
            ),
          ],
        );
      },
    );
  }

  /// أي لون يعني ماذا.
  Widget _legend(BuildContext context) {
    if (promotionZone <= 0 && relegationZone <= 0) {
      return const SizedBox.shrink();
    }
    final AppTokens t = context.tokens;
    final TextStyle? style = context.text.labelMedium?.copyWith(
      color: t.textSecondary,
      fontWeight: FontWeight.w700,
    );
    Widget zone(String text, Color color, String key) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(text, key: Key(key), style: style),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          if (promotionZone > 0)
            zone(
              eliteDraw
                  ? h2hCupLegend(promotionZone)
                  : 'يصعد أول $promotionZone',
              t.success,
              '$keyPrefix.zone.up',
            ),
          if (relegationZone > 0)
            zone('يهبط آخر $relegationZone', t.error, '$keyPrefix.zone.down'),
        ],
      ),
    );
  }

  /// أسماء الأعمدة بالكلمات.
  Widget _header(BuildContext context) {
    final TextStyle? style = context.text.labelSmall?.copyWith(
      color: context.tokens.textSecondary,
      fontWeight: FontWeight.w700,
    );
    Widget cell(String text, double width) => SizedBox(
      width: width,
      child: Text(text, maxLines: 1, textAlign: TextAlign.center, style: style),
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm,
          0,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Row(
          key: Key('$keyPrefix.header'),
          children: <Widget>[
            const SizedBox(width: 4 + AppSpacing.sm),
            cell('#', _rankWidth),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('اللاعب', style: style)),
            cell('فوز', _winWidth),
            cell('تعادل', _drawWidth),
            cell('خسارة', _lossWidth),
            cell('التوقع', _forWidth),
            cell('النقاط', _pointsWidth),
          ],
        ),
      ),
    );
  }

  /// لاعب واحد.
  Widget _row(
    BuildContext context,
    H2hStandingDto s, {
    required bool played,
    required bool compact,
    required bool promoted,
    required bool relegated,
  }) {
    final AppTokens t = context.tokens;
    final String name = h2hNameOf(s.displayName);
    final Color stripe = promoted
        ? t.success
        : (relegated ? t.error : Colors.transparent);
    final TextStyle? nameStyle = context.text.bodyMedium?.copyWith(
      color: t.textPrimary,
      fontWeight: s.isMe ? FontWeight.w800 : FontWeight.w600,
    );
    final TextStyle? numberStyle = context.text.labelMedium?.copyWith(
      color: t.textSecondary,
      fontWeight: FontWeight.w600,
    );
    final Widget zone = Container(
      width: 4,
      height: 32,
      decoration: BoxDecoration(color: stripe, borderRadius: AppRadius.brXs),
    );
    final Text rankText = Text(
      played ? '${s.rank}' : '—',
      key: Key('$keyPrefix.${s.userId}.rank'),
      textAlign: TextAlign.center,
      style: context.text.titleSmall?.copyWith(
        color: t.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
    final Widget rank = compact
        ? SizedBox(width: _rankWidth, child: rankText)
        : ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _rankWidth),
            child: rankText,
          );
    final Widget points = Text(
      '${s.leaguePoints}',
      key: Key('$keyPrefix.${s.userId}.points'),
      textAlign: TextAlign.center,
      style: context.text.titleMedium?.copyWith(
        color: t.textPrimary,
        fontWeight: FontWeight.w800,
      ),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
          ),
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                cell('${s.won}', _winWidth),
                cell('${s.drawn}', _drawWidth),
                cell('${s.lost}', _lossWidth),
                cell('${s.pointsFor}', _forWidth),
              ],
            ),
          ),
          SizedBox(width: _pointsWidth, child: points),
        ],
      );
    } else {
      body = Row(
        children: <Widget>[
          zone,
          const SizedBox(width: AppSpacing.sm),
          rank,
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
                  key: Key('$keyPrefix.${s.userId}.record'),
                  style: context.text.labelSmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          points,
        ],
      );
    }
    return Container(
      key: Key('$keyPrefix.${s.userId}'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: s.isMe ? t.surfaceHigh : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: t.border.withValues(alpha: 0.5)),
        ),
      ),
      child: body,
    );
  }
}
