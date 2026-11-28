// NK333_02
/// «مسارك» و«بقية المسارات» أو «المسارات الثلاثة» في تبويب الكأس (سكربت 333):
/// لمن هو في الكأس خط زمني لمراحل مساره ينتهي بالبطل، وتحته صف لكل مسار آخر؛
/// ولمن يشاهد فقط صف لكل مسار من الثلاثة.
///
/// **كل شيء من لوحة الكأس التي أرسلها الخادم.** المرحلة والموعد والخصم
/// والفائز والبطل كما جاءت، فلا يُحسم هنا شيء ولا يُقرأ الوقت. المرحلة التي
/// يقف عندها المسار هي التي يختارها `h2hCupBoardFocusStage`. الودجة بجانب
/// لوحة الكأس القديمة وبلا ربط بها (التركيب في 336).
library;

import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../h2h_cup_texts.dart';

/// قطر نقطة الخط الزمني.
const double _dotSize = 22;

/// القسمان معاً: خط مسار اللاعب ثم بقية المسارات، أو المسارات الثلاثة لمن
/// يشاهد. لا تعرض شيئاً قبل أن يقوم الكأس.
class H2hCupPathsView extends StatelessWidget {
  /// ينشئ القسمين من لوحة الكأس.
  const H2hCupPathsView({required this.board, super.key});

  /// لوحة الكأس كما جاءت من الخادم.
  final H2hCupBoardDto board;

  @override
  Widget build(BuildContext context) {
    final H2hCupBoardPathDto? mine = h2hCupBoardMyPath(board);
    final List<H2hCupBoardPathDto> others = <H2hCupBoardPathDto>[
      for (final H2hCupBoardPathDto path in board.paths)
        if (!identical(path, mine)) path,
    ];
    if (mine == null && others.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        key: const Key('h2h.cupPaths'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (mine != null) ...<Widget>[
            _Heading(
              text: '$h2hCupMyPathHeading · ${h2hCupBoardPathShortName(mine)}',
              keyName: 'h2h.cupPath.heading',
            ),
            _MyPathCard(path: mine),
            if (others.isNotEmpty) const SizedBox(height: AppSpacing.md),
          ],
          if (others.isNotEmpty) ...<Widget>[
            _Heading(
              text: h2hCupPathsHeading(others, mine: mine != null),
              keyName: 'h2h.cupPaths.heading',
            ),
            for (final H2hCupBoardPathDto path in others) _PathRow(path: path),
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

/// حال مرحلة في الخط الزمني.
enum _StepState { done, current, upcoming, skipped }

/// مسار اللاعب: نقطة لكل مرحلة وخط بينها، وتنتهي ببطل المسار.
class _MyPathCard extends StatelessWidget {
  const _MyPathCard({required this.path});

  final H2hCupBoardPathDto path;

  _StepState _stateOf(H2hCupBoardStageDto stage, H2hCupBoardStageDto? focus) {
    if (stage.phase == 'decided') return _StepState.done;
    if (stage.phase == 'skipped') return _StepState.skipped;
    return identical(stage, focus) ? _StepState.current : _StepState.upcoming;
  }

  @override
  Widget build(BuildContext context) {
    final H2hCupBoardStageDto? focus = h2hCupBoardFocusStage(path);
    return AppCard(
      key: const Key('h2h.cupPath.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < path.stages.length; i++)
            _StageStep(
              index: i,
              stage: path.stages[i],
              state: _stateOf(path.stages[i], focus),
            ),
          _ChampionStep(path: path),
        ],
      ),
    );
  }
}

/// صف في الخط الزمني: عمود النقطة والخط، ثم النص. النقطة على حافة البداية
/// فتكون على اليمين في الواجهة العربية.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.dot,
    required this.child,
    required this.showLine,
  });

  final Widget dot;
  final Widget child;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: _dotSize,
            child: Column(
              children: <Widget>[
                dot,
                if (showLine)
                  Expanded(child: Container(width: 2, color: t.controlBorder)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? AppSpacing.md : 0),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// مرحلة من مسار اللاعب: عنوانها وموعدها، وحالها وخصمها.
class _StageStep extends StatelessWidget {
  const _StageStep({
    required this.index,
    required this.stage,
    required this.state,
  });

  final int index;
  final H2hCupBoardStageDto stage;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool live = state == _StepState.current && stage.phase == 'live';
    return _TimelineRow(
      showLine: true,
      dot: _StageDot(key: Key('h2h.cupPath.dot.$index'), state: state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            h2hCupBoardStageTitle(stage),
            key: Key('h2h.cupPath.stage.$index'),
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            h2hCupMyStageLine(stage),
            key: Key('h2h.cupPath.stage.$index.line'),
            style: context.text.labelMedium?.copyWith(
              color: live ? t.successText : t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// نقطة مرحلة: ممتلئة بعلامة صح إن انتهت، وممتلئة بحلقة إن كانت الجارية،
/// ومفرغة إن لم تأتِ بعد أو لا تُلعب.
class _StageDot extends StatelessWidget {
  const _StageDot({required this.state, super.key});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return switch (state) {
      _StepState.done => Container(
        width: _dotSize,
        height: _dotSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.success),
        child: Icon(Icons.check, size: 14, color: t.onSuccess),
      ),
      _StepState.current => Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.primary,
          border: Border.all(color: t.surfaceHigh, width: 4),
        ),
      ),
      _StepState.upcoming => Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.controlBorder, width: 2),
        ),
      ),
      _StepState.skipped => Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.border, width: 2),
        ),
      ),
    };
  }
}

/// آخر الخط: البطل، أو حلقة ذهبية متقطعة تنتظره.
class _ChampionStep extends StatelessWidget {
  const _ChampionStep({required this.path});

  final H2hCupBoardPathDto path;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool crowned = path.title?.champion != null;
    return _TimelineRow(
      showLine: false,
      dot: crowned
          ? Container(
              key: const Key('h2h.cupPath.champion.dot'),
              width: _dotSize,
              height: _dotSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.goldAccent,
              ),
              child: Icon(Icons.emoji_events, size: 14, color: t.onGold),
            )
          : _DashedRing(
              key: const Key('h2h.cupPath.champion.dot'),
              color: t.goldAccent,
            ),
      child: Text(
        h2hCupBoardChampionLine(path),
        key: const Key('h2h.cupPath.champion'),
        style: context.text.titleSmall?.copyWith(
          color: crowned ? t.textPrimary : t.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// حلقة متقطعة بحجم النقطة، لمن لم يُحسم بعد.
class _DashedRing extends StatelessWidget {
  const _DashedRing({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _dotSize,
      height: _dotSize,
      child: CustomPaint(painter: _DashedRingPainter(color)),
    );
  }
}

/// يرسل اثنتي عشرة قوساً قصيراً على دائرة.
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const int dashes = 12;
    const double sweep = 2 * math.pi / dashes;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Rect rect = (Offset.zero & size).deflate(1);
    for (int i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// صف مسار: اسمه وحاله، وشارة «بطل» إن حُسم بطل، وإلا نقاط المراحل.
class _PathRow extends StatelessWidget {
  const _PathRow({required this.path});

  final H2hCupBoardPathDto path;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String prefix = 'h2h.cupPaths.row.${path.place}';
    final H2hCupBoardStageDto? focus = h2hCupBoardFocusStage(path);
    final H2hCupTitleDto? title = path.title;
    final bool live = title == null && focus?.phase == 'live';
    final Widget? trailing;
    if (title?.champion != null) {
      trailing = _ChampionBadge(key: Key('$prefix.badge'));
    } else if (title == null && path.stages.isNotEmpty) {
      trailing = _StepDots(
        key: Key('$prefix.dots'),
        step: h2hCupBoardPathStep(path),
        total: path.stages.length + 1,
      );
    } else {
      trailing = null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key(prefix),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    h2hCupBoardPathShortName(path),
                    key: Key('$prefix.name'),
                    style: context.text.labelLarge?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    h2hCupBoardPathStatus(path),
                    key: Key('$prefix.status'),
                    style: context.text.labelMedium?.copyWith(
                      color: live ? t.successText : t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

/// شارة «بطل».
class _ChampionBadge extends StatelessWidget {
  const _ChampionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: t.goldContainer,
        borderRadius: AppRadius.brXxl,
      ),
      child: Text(
        h2hCupChampionBadge,
        style: context.text.labelSmall?.copyWith(
          color: t.gold,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// نقاط المراحل: الممتلئة منها ما بلغه المسار، وتُقرأ لقارئ الشاشة جملة
/// واحدة («المرحلة الأولى من ثلاث»).
class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.total, super.key});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Semantics(
      label: h2hCupPathStepLabel(step, total),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < total; i++)
              Container(
                width: 10,
                height: 10,
                margin: EdgeInsetsDirectional.only(
                  start: i == 0 ? 0 : AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < step ? t.primary : null,
                  border: i < step
                      ? null
                      : Border.all(color: t.controlBorder, width: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
