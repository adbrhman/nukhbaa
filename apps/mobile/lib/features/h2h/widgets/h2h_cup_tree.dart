// NK334_02
/// «شجرة الأدوار» في تبويب الكأس (سكربت 334): تبويب لكل مسار، وتحته شجرته؛
/// مربعا نصف النهائي، ثم النهائي، ثم البطل. والضغط على مربع يفتح مباريات
/// زوجه تحت الشجرة.
///
/// **كل شيء من لوحة الكأس التي أرسلها الخادم.** الأزواج والفائز والبطل كما
/// جاءت، فلا يُحسم هنا شيء ولا يُخمَّن من سيتأهل ولا تُقرأ الساعة. مرحلة لم
/// تُسحب بعد تُرسم مربعاً متقطعاً («بانتظار الفائز» للنهائي)، وعلامة الفائز
/// لا تظهر إلا بعد حسم الزوج. المباريات المفتوحة هي بطاقة مباريات المواجهة
/// نفسها (`H2hCupFixturesCard`)، فتوقع الخصم قبل الانطلاق محجوب فيها كما في
/// بقية الكأس. الودجة بجانب لوحة الكأس القديمة وبلا ربط بها (التركيب في 336).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../h2h_cup_texts.dart';
import 'h2h_cup_now.dart' show H2hCupFixturesCard;

/// قطر دائرة البطل.
const double _championSize = 54;

/// القسم: العنوان، وتبويب المسارات، والشجرة، وتحتها تلميح أو مباريات
/// المربع المفتوح. لا يعرض شيئاً قبل أن يقوم الكأس.
class H2hCupTreeView extends StatefulWidget {
  /// ينشئ القسم من لوحة الكأس.
  const H2hCupTreeView({required this.board, super.key});

  /// لوحة الكأس كما جاءت من الخادم.
  final H2hCupBoardDto board;

  @override
  State<H2hCupTreeView> createState() => _H2hCupTreeViewState();
}

class _H2hCupTreeViewState extends State<H2hCupTreeView> {
  /// المسار الذي ضغطه اللاعب، أو null قبل أن يضغط أحداً.
  int? _place;

  /// المربع المفتوح: رقم المرحلة في المسار ورقم الزوج فيها.
  ({int stage, int slot})? _open;

  /// مسار الشجرة: ما ضغطه اللاعب، وإلا مساره هو، وإلا الأول. وما ضغطه إن
  /// غاب عن اللوحة الجديدة يُترك.
  H2hCupBoardPathDto _selected(H2hCupBoardDto board) {
    for (final H2hCupBoardPathDto path in board.paths) {
      if (path.place == _place) return path;
    }
    return h2hCupBoardMyPath(board) ?? board.paths.first;
  }

  /// زوج المربع المفتوح في [path]، أو null إن لم يعد في اللوحة.
  H2hCupBoardPairDto? _openPair(H2hCupBoardPathDto path) {
    final ({int stage, int slot})? open = _open;
    if (open == null || open.stage >= path.stages.length) return null;
    for (final H2hCupBoardPairDto pair in path.stages[open.stage].pairs) {
      if (pair.slot == open.slot) return pair;
    }
    return null;
  }

  void _pick(int place) {
    setState(() {
      _place = place;
      _open = null;
    });
  }

  void _toggle(int stage, int slot) {
    setState(() {
      final ({int stage, int slot})? open = _open;
      final bool same =
          open != null && open.stage == stage && open.slot == slot;
      _open = same ? null : (stage: stage, slot: slot);
    });
  }

  @override
  Widget build(BuildContext context) {
    final H2hCupBoardDto board = widget.board;
    if (board.paths.isEmpty) return const SizedBox.shrink();
    final AppTokens t = context.tokens;
    final H2hCupBoardPathDto path = _selected(board);
    final H2hCupBoardPairDto? open = _openPair(path);
    final bool hasPairs = path.stages.any(
      (H2hCupBoardStageDto s) => s.pairs.isNotEmpty,
    );
    final TextStyle? note = context.text.labelMedium?.copyWith(
      color: t.textSecondary,
    );
    final Widget below;
    if (open != null) {
      below = open.fixtures.isEmpty
          ? Text(
              h2hCupTreeNoFixtures,
              key: const Key('h2h.cupTree.noFixtures'),
              textAlign: TextAlign.center,
              style: note,
            )
          : H2hCupFixturesCard(pair: open, keyPrefix: 'h2h.cupTree.fixtures');
    } else if (hasPairs) {
      below = Text(
        h2hCupTreeTapHint,
        key: const Key('h2h.cupTree.hint'),
        textAlign: TextAlign.center,
        style: note,
      );
    } else {
      below = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        key: const Key('h2h.cupTree'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              h2hCupTreeHeading,
              key: const Key('h2h.cupTree.heading'),
              style: context.text.titleSmall?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final H2hCupBoardPathDto p in board.paths)
                _PathTab(
                  place: p.place,
                  selected: p.place == path.place,
                  onTap: () => _pick(p.place),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _TreeCard(path: path, open: _open, onToggle: _toggle),
          const SizedBox(height: AppSpacing.sm),
          below,
        ],
      ),
    );
  }
}

/// تبويب مسار: اسمه القصير، والمختار ممتلئ. الاسم المرسوم لا يُقرأ ثانية؛
/// تقرؤه العلامة.
class _PathTab extends StatelessWidget {
  const _PathTab({
    required this.place,
    required this.selected,
    required this.onTap,
  });

  final int place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String name = h2hCupPathShortName(place);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: name,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? t.primary : t.surfaceHigh,
          borderRadius: AppRadius.brXxl,
          child: InkWell(
            key: Key('h2h.cupTree.tab.$place'),
            borderRadius: AppRadius.brXxl,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                widthFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text(
                    name,
                    style: context.text.labelLarge?.copyWith(
                      color: selected ? t.onPrimary : t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// الشجرة: عمود لكل مرحلة، ثم عمود البطل، بينها خطوط وصل قصيرة. أول عمود على
/// حافة البداية، فيكون نصف النهائي على اليمين في الواجهة العربية.
class _TreeCard extends StatelessWidget {
  const _TreeCard({
    required this.path,
    required this.open,
    required this.onToggle,
  });

  final H2hCupBoardPathDto path;
  final ({int stage, int slot})? open;
  final void Function(int stage, int slot) onToggle;

  @override
  Widget build(BuildContext context) {
    final List<Widget> columns = <Widget>[];
    for (int i = 0; i < path.stages.length; i++) {
      columns
        ..add(
          Expanded(
            flex: 3,
            child: _StageColumn(
              index: i,
              stage: path.stages[i],
              open: open,
              onToggle: onToggle,
            ),
          ),
        )
        ..add(const _Connector());
    }
    columns.add(Expanded(flex: 2, child: _ChampionColumn(path: path)));
    return AppCard(
      key: const Key('h2h.cupTree.card'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: columns,
      ),
    );
  }
}

/// خط وصل قصير بين عمودين.
class _Connector extends StatelessWidget {
  const _Connector();

  @override
  Widget build(BuildContext context) {
    return Container(width: 10, height: 2, color: context.tokens.controlBorder);
  }
}

/// عمود مرحلة: اسمها، ثم مربع لكل زوج، ثم مربع من تأهل مباشرة، أو مربع
/// متقطع إن لم يكن فيها زوج.
class _StageColumn extends StatelessWidget {
  const _StageColumn({
    required this.index,
    required this.stage,
    required this.open,
    required this.onToggle,
  });

  final int index;
  final H2hCupBoardStageDto stage;
  final ({int stage, int slot})? open;
  final void Function(int stage, int slot) onToggle;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final ({int stage, int slot})? current = open;
    final List<Widget> boxes = <Widget>[];
    for (final H2hCupBoardPairDto pair in stage.pairs) {
      if (boxes.isNotEmpty) boxes.add(const SizedBox(height: AppSpacing.md));
      boxes.add(
        _PairBox(
          index: index,
          pair: pair,
          open:
              current != null &&
              current.stage == index &&
              current.slot == pair.slot,
          onTap: () => onToggle(index, pair.slot),
        ),
      );
    }
    final H2hCupPlayerDto? bye = stage.bye;
    if (bye != null) {
      if (boxes.isNotEmpty) boxes.add(const SizedBox(height: AppSpacing.md));
      boxes.add(_ByeBox(index: index, player: bye));
    }
    if (boxes.isEmpty) boxes.add(_SlotBox(index: index, stage: stage));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          h2hCupRoundName(stage.round),
          key: Key('h2h.cupTree.stage.$index'),
          textAlign: TextAlign.center,
          style: context.text.labelMedium?.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...boxes,
      ],
    );
  }
}

/// حال لاعب في مربع: لم يُحسم الزوج، أو فاز، أو لم يفز.
enum _Standing { pending, won, lost }

/// مربع زوج: صف لكل لاعب، ويُضغط ليفتح مبارياته. حدّه بلون الأساس إن كان
/// فيه اللاعب نفسه، وأثخن إن كان مفتوحاً.
class _PairBox extends StatelessWidget {
  const _PairBox({
    required this.index,
    required this.pair,
    required this.open,
    required this.onTap,
  });

  final int index;
  final H2hCupBoardPairDto pair;
  final bool open;
  final VoidCallback onTap;

  _Standing _standing(H2hCupPlayerDto player) {
    if (!pair.decided) return _Standing.pending;
    return h2hCupPairWon(pair, player) ? _Standing.won : _Standing.lost;
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String prefix = 'h2h.cupTree.box.$index.${pair.slot}';
    final bool mine = pair.home.isMe || pair.away.isMe;
    return Semantics(
      container: true,
      button: true,
      selected: open,
      label: h2hCupTreeBoxLabel(pair),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: t.backgroundElevated,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.brMd,
            side: BorderSide(
              color: open || mine ? t.primary : t.border,
              width: open ? 2 : 1,
            ),
          ),
          child: InkWell(
            key: Key(prefix),
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PlayerRow(
                  keyName: '$prefix.home',
                  player: pair.home,
                  standing: _standing(pair.home),
                ),
                Container(height: 1, color: t.border),
                _PlayerRow(
                  keyName: '$prefix.away',
                  player: pair.away,
                  standing: _standing(pair.away),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// صف لاعب في المربع: اسمه، ونقطة خضراء إن فاز. من لم يفز في زوج محسوم
/// باهت.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.keyName,
    required this.player,
    required this.standing,
  });

  final String keyName;
  final H2hCupPlayerDto player;
  final _Standing standing;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool won = standing == _Standing.won;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              h2hCupNameOf(player),
              key: Key(keyName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: standing == _Standing.lost
                    ? t.textSecondary
                    : t.textPrimary,
                fontWeight: won || player.isMe
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
          ),
          if (won) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Container(
              key: Key('$keyName.winner'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.success,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// مربع من تأهل مباشرة: اسمه وتحته «تأهل مباشرة». لا يُضغط، فلا مباريات له.
class _ByeBox extends StatelessWidget {
  const _ByeBox({required this.index, required this.player});

  final int index;
  final H2hCupPlayerDto player;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String prefix = 'h2h.cupTree.bye.$index';
    return Semantics(
      container: true,
      label: '${h2hCupNameOf(player)} · $h2hCupTreeByeNote',
      child: ExcludeSemantics(
        child: Container(
          key: Key(prefix),
          decoration: BoxDecoration(
            color: t.backgroundElevated,
            borderRadius: AppRadius.brMd,
            border: Border.all(color: player.isMe ? t.primary : t.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PlayerRow(
                keyName: '$prefix.name',
                player: player,
                standing: _Standing.pending,
              ),
              Container(height: 1, color: t.border),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  h2hCupTreeByeNote,
                  key: Key('$prefix.note'),
                  style: context.text.labelSmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مربع متقطع لمرحلة بلا أزواج: صفان بنص واحد («بانتظار الفائز» مثلاً)،
/// وصف واحد لمرحلة لا تُلعب.
class _SlotBox extends StatelessWidget {
  const _SlotBox({required this.index, required this.stage});

  final int index;
  final H2hCupBoardStageDto stage;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String text = h2hCupTreeSlotText(stage);
    final TextStyle? style = context.text.labelSmall?.copyWith(
      color: t.textSecondary,
    );
    final int rows = stage.phase == 'skipped' ? 1 : 2;
    return Semantics(
      container: true,
      label: '${h2hCupRoundName(stage.round)}: $text',
      child: ExcludeSemantics(
        child: CustomPaint(
          key: Key('h2h.cupTree.slot.$index'),
          painter: _DashedPainter(
            color: t.controlBorder,
            circle: false,
            radius: AppRadius.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < rows; i++)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    text,
                    key: Key('h2h.cupTree.slot.$index.$i'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عمود البطل: «البطل» ثم دائرة ذهبية فيها كأس واسمه تحتها إن توّج، وإلا
/// حلقة ذهبية متقطعة فيها «؟» (أو «شاغر» إن انتهى المسار بلا بطل).
class _ChampionColumn extends StatelessWidget {
  const _ChampionColumn({required this.path});

  final H2hCupBoardPathDto path;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool crowned = path.title?.champion != null;
    final String text = h2hCupTreeChampionText(path);
    final Widget circle = crowned
        ? Container(
            key: const Key('h2h.cupTree.champion.circle'),
            width: _championSize,
            height: _championSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.goldAccent,
            ),
            child: Icon(Icons.emoji_events, size: 28, color: t.onGold),
          )
        : CustomPaint(
            key: const Key('h2h.cupTree.champion.circle'),
            size: const Size(_championSize, _championSize),
            painter: _DashedPainter(
              color: t.goldAccent,
              circle: true,
              radius: 0,
            ),
            child: SizedBox(
              width: _championSize,
              height: _championSize,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      key: const Key('h2h.cupTree.champion.text'),
                      style: context.text.titleMedium?.copyWith(
                        color: t.gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
    return Semantics(
      container: true,
      label: h2hCupTreeChampionSemantics(path),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              h2hCupTreeChampionLabel,
              key: const Key('h2h.cupTree.champion.label'),
              textAlign: TextAlign.center,
              style: context.text.labelMedium?.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            circle,
            if (crowned) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                text,
                key: const Key('h2h.cupTree.champion.name'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// يرسم حدّاً متقطعاً: مستطيلاً مدوّر الزوايا، أو دائرة تملأ المساحة.
class _DashedPainter extends CustomPainter {
  const _DashedPainter({
    required this.color,
    required this.circle,
    required this.radius,
  });

  final Color color;
  final bool circle;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const double dash = 5;
    const double gap = 4;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Rect rect = (Offset.zero & size).deflate(1);
    final Path path = Path();
    if (circle) {
      path.addOval(rect);
    } else {
      path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }
    for (final ui.PathMetric metric in path.computeMetrics()) {
      double at = 0;
      while (at < metric.length) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + dash, metric.length)),
          paint,
        );
        at += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.circle != circle ||
      oldDelegate.radius != radius;
}
