/// The celebration of a crowned month on top of the leaderboard.
///
/// Drawn in the order the design fixed, back to front:
///
/// 1. [ChampionBackdrop] -- the champion's picture, faint, behind the whole
///    header, fading out before the board begins;
/// 2. the celebration -- the crown, a gold light and a light shower of
///    confetti that falls once and stops;
/// 3. the champion's picture in a gold frame ([ChampionFramedPhoto]);
/// 4. the name, the points and the accuracy.
///
/// The ranking follows underneath, untouched: the screen stays a
/// leaderboard, not a poster. The admin's preview draws these same widgets,
/// with the picture still on the device ([previewPhotos]), so what the admin
/// approves is what the players see.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/avatar_bytes_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../competition/month_label.dart';
import 'champion_crown.dart';

/// The picture to draw for [champion]: the one the admin is previewing, else
/// the celebration picture, else the champion's own profile picture. Null
/// while it loads, when there is none, or when it failed -- the frame then
/// shows the name's first letter.
Uint8List? championPhotoBytes(
  WidgetRef ref,
  MonthChampionDto champion, [
  Map<String, Uint8List> previewPhotos = const <String, Uint8List>{},
]) {
  final Uint8List? local = previewPhotos[champion.userId];
  if (local != null) return local;
  final String? path = champion.photoUrl ?? champion.avatarUrl;
  if (path == null) return null;
  return ref.watch(avatarBytesProvider(path)).value;
}

/// The title over a crowning: `بطل شهر 9`, or its two-champion form.
String championTitle(AppLocalizations l10n, List<MonthChampionDto> champions) {
  final String month = champions.isEmpty
      ? ''
      : monthLabelFromStored(champions.first.seasonLabel);
  return champions.length > 1
      ? l10n.championTitleTwo(month)
      : l10n.championTitleOne(month);
}

/// Layer 1: the champion's picture, faint, behind the leaderboard's header.
///
/// Decoration only: it takes no touch and says nothing to a screen reader.
/// Without any picture it is the gold light alone.
class ChampionBackdrop extends ConsumerWidget {
  /// Creates the backdrop for [champions] (one or two, of one month).
  const ChampionBackdrop({
    required this.champions,
    this.previewPhotos = const <String, Uint8List>{},
    super.key,
  });

  /// The celebrated champions.
  final List<MonthChampionDto> champions;

  /// Pictures still on the admin's device, by user id.
  final Map<String, Uint8List> previewPhotos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    Uint8List? bytes;
    for (final MonthChampionDto c in champions) {
      bytes ??= championPhotoBytes(ref, c, previewPhotos);
    }
    final Uint8List? photo = bytes;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 0.9,
                  colors: <Color>[
                    t.gold.withValues(alpha: 0.22),
                    t.gold.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            if (photo != null)
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (Rect rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.white, Colors.transparent],
                  stops: <double>[0.3, 1],
                ).createShader(rect),
                child: Image.memory(
                  photo,
                  key: const Key('champion.backdrop.photo'),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  opacity: const AlwaysStoppedAnimation<double>(0.16),
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Layers 2 to 4: the crown, the light and the confetti, the framed picture,
/// and the name, points and accuracy of each champion.
///
/// It can fold into a one-line strip, for a small screen or a player who has
/// seen it; the confetti falls once when it first appears and never loops.
class ChampionSpotlight extends ConsumerStatefulWidget {
  /// Creates the spotlight for [champions] (one or two, of one month).
  const ChampionSpotlight({
    required this.champions,
    required this.keyPrefix,
    this.previewPhotos = const <String, Uint8List>{},
    this.onOpenRecord,
    super.key,
  });

  /// The celebrated champions.
  final List<MonthChampionDto> champions;

  /// The widget-test key namespace.
  final String keyPrefix;

  /// Pictures still on the admin's device, by user id.
  final Map<String, Uint8List> previewPhotos;

  /// Opens the champions' record; null hides the link (the admin preview).
  final VoidCallback? onOpenRecord;

  @override
  ConsumerState<ChampionSpotlight> createState() => _ChampionSpotlightState();
}

class _ChampionSpotlightState extends ConsumerState<ChampionSpotlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  bool? _expanded;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A short screen starts folded, so the board keeps most of the room.
    _expanded ??= MediaQuery.sizeOf(context).height >= 600;
    if (!_started) {
      _started = true;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _confetti.forward();
      }
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<MonthChampionDto> champions = widget.champions;
    final bool expanded = _expanded ?? true;
    final String title = championTitle(l10n, champions);
    final String p = widget.keyPrefix;

    final Widget header = Row(
      children: <Widget>[
        ChampionCrown(size: expanded ? 18 : 22),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            expanded
                ? title
                : '$title: ${champions.map((c) => c.displayName).join(l10n.boardListSeparator)}',
            key: Key('$p.title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleSmall?.copyWith(
              color: t.gold,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (widget.onOpenRecord != null)
          TextButton(
            key: Key('$p.record'),
            onPressed: widget.onOpenRecord,
            style: TextButton.styleFrom(
              foregroundColor: t.textSecondary,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(l10n.championsRecordTitle),
          ),
        IconButton(
          key: Key('$p.toggle'),
          tooltip: expanded
              ? l10n.championSpotlightCollapse
              : l10n.championSpotlightExpand,
          visualDensity: VisualDensity.compact,
          color: t.textSecondary,
          icon: Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
          ),
          onPressed: () => setState(() => _expanded = !expanded),
        ),
      ],
    );

    return Container(
      key: Key('$p.spotlight'),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.brLg,
        border: Border.all(color: t.gold.withValues(alpha: 0.45)),
        color: t.surface.withValues(alpha: 0.55),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          // Layer 2: the light and the confetti, behind the faces.
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) => CustomPaint(
                    painter: _ConfettiPainter(
                      progress: _confetti.value,
                      running: _confetti.isAnimating,
                      colors: <Color>[t.gold, t.primary, t.silver, t.success],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  header,
                  if (expanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        0,
                        0,
                        AppSpacing.sm,
                        AppSpacing.sm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final MonthChampionDto c in champions)
                            Expanded(
                              child: _ChampionFace(
                                champion: c,
                                keyPrefix: p,
                                title: title,
                                photoSize: champions.length > 1 ? 72 : 88,
                                bytes: championPhotoBytes(
                                  ref,
                                  c,
                                  widget.previewPhotos,
                                ),
                              ),
                            ),
                        ],
                      ),
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

/// One champion: crown, the gold-framed picture in its light, then the
/// name, the points and the accuracy.
class _ChampionFace extends StatelessWidget {
  const _ChampionFace({
    required this.champion,
    required this.keyPrefix,
    required this.title,
    required this.photoSize,
    required this.bytes,
  });

  final MonthChampionDto champion;
  final String keyPrefix;
  final String title;
  final double photoSize;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int? accuracy = champion.accuracyPercent;
    final String id = champion.userId;
    return Semantics(
      container: true,
      label: <String>[
        title,
        champion.displayName,
        l10n.boardPoints(champion.points),
        if (accuracy != null) l10n.boardAccuracyIs(accuracy),
      ].join(l10n.boardListSeparator),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ChampionCrown(size: photoSize * 0.38),
          const SizedBox(height: 2),
          ChampionFramedPhoto(
            key: Key('$keyPrefix.photo.$id'),
            displayName: champion.displayName,
            bytes: bytes,
            size: photoSize,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            champion.displayName,
            key: Key('$keyPrefix.name.$id'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.text.titleMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: 2,
            children: <Widget>[
              Text(
                l10n.pointsAbbreviated(champion.points),
                key: Key('$keyPrefix.points.$id'),
                style: context.text.labelLarge?.copyWith(
                  color: t.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (accuracy != null)
                Text(
                  l10n.boardAccuracyIs(accuracy),
                  key: Key('$keyPrefix.accuracy.$id'),
                  style: context.text.labelLarge?.copyWith(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Layer 3: a picture in a round gold frame with its own soft light, the
/// name's first letter standing in when there is no picture.
class ChampionFramedPhoto extends StatelessWidget {
  /// Creates the frame, [size] across.
  const ChampionFramedPhoto({
    required this.displayName,
    required this.bytes,
    required this.size,
    super.key,
  });

  /// Whose picture it is (the fallback letter).
  final String displayName;

  /// The picture, or null for the letter.
  final Uint8List? bytes;

  /// The frame's outer diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String trimmed = displayName.trim();
    final Widget letter = Container(
      color: t.surfaceElevated,
      alignment: Alignment.center,
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: t.gold,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
    final Uint8List? picture = bytes;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.05),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: t.goldGradient,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: t.gold.withValues(alpha: 0.45),
            blurRadius: size * 0.35,
            spreadRadius: size * 0.02,
          ),
        ],
      ),
      child: ClipOval(
        child: picture == null
            ? letter
            : Image.memory(
                picture,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => letter,
              ),
      ),
    );
  }
}

/// A light shower of paper pieces, falling once over the spotlight and
/// fading out. The pieces are fixed (a seeded sequence), so a repaint never
/// reshuffles them mid-fall.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.progress,
    required this.running,
    required this.colors,
  });

  static final List<_Piece> _pieces = _Piece.sequence(28);

  final double progress;
  final bool running;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (!running || progress <= 0 || progress >= 1) return;
    final double fade = progress < 0.75 ? 1 : (1 - progress) / 0.25;
    final Paint paint = Paint();
    for (final _Piece piece in _pieces) {
      final double local = ((progress - piece.delay) / (1 - piece.delay)).clamp(
        0.0,
        1.0,
      );
      if (local <= 0) continue;
      final double x =
          (piece.x + math.sin(local * math.pi * 2 * piece.sway) * 0.03) *
          size.width;
      final double y = (-0.1 + local * 1.2) * size.height;
      paint.color = colors[piece.color % colors.length].withValues(
        alpha: 0.85 * fade,
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.spin * local * math.pi * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.width,
            height: piece.width * 0.45,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.running != running;
}

class _Piece {
  const _Piece({
    required this.x,
    required this.delay,
    required this.sway,
    required this.spin,
    required this.width,
    required this.color,
  });

  static List<_Piece> sequence(int count) {
    final math.Random random = math.Random(9);
    return <_Piece>[
      for (int i = 0; i < count; i++)
        _Piece(
          x: random.nextDouble(),
          delay: random.nextDouble() * 0.35,
          sway: 0.5 + random.nextDouble(),
          spin: 0.5 + random.nextDouble() * 1.5,
          width: 5 + random.nextDouble() * 4,
          color: i,
        ),
    ];
  }

  final double x;
  final double delay;
  final double sway;
  final double spin;
  final double width;
  final int color;
}
