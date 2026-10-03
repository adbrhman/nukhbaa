/// The celebration of a crowned month at the top of the leaderboard.
///
/// Drawn in the order the design fixed, back to front:
///
/// 1. [ChampionBackdrop] -- the champion's picture, faint, behind the whole
///    header, fading out before the board begins;
/// 2. the celebration -- gold light and ribbons, the crown, and a light
///    shower of confetti that falls once and stops;
/// 3. the champion's picture in a gold frame inside a laurel wreath
///    ([ChampionFramedPhoto]), the place "1" under it;
/// 4. "بطل شهر سبتمبر 2026", the name, the points and the accuracy, the
///    congratulations and the prize.
///
/// The ranking follows underneath, untouched: the screen stays a
/// leaderboard, not a poster. The hero keeps the brand's own navy and gold
/// whatever theme the viewer runs -- it is the same picture the champion
/// shares ([ChampionShareCard]). The admin's preview draws these same
/// widgets, with the picture still on the device ([previewPhotos]).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/avatar_bytes_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/sign_in_screen.dart' show kBrandLogoAsset;
import '../../gamification/invite_friends_screen.dart';
import 'champion_crown.dart';

// The hero is a picture that can leave the app (the champion shares it), so
// it keeps the brand's own colours whatever theme the viewer runs: the dark
// palette, read from AppColors rather than copied (UI-33).
const Color _navy = AppColors.background;
const Color _navyRaised = AppColors.surface;
const Color _gold = AppColors.gold;
const Color _goldDeep = AppColors.goldDark;
const Color _white = AppColors.textPrimary;
const Color _muted = AppColors.textMuted;

const List<String> _monthsAr = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

const List<String> _monthsEn = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A stored month label (`09/2026`) by name in [locale]'s language:
/// `سبتمبر 2026`, or `سبتمبر` without the year. A label in another shape is
/// returned as it is.
String championMonthName(String label, Locale locale, {bool withYear = true}) {
  final List<String> parts = label.split('/');
  if (parts.length != 2) return label;
  final int? month = int.tryParse(parts.first);
  final int? year = int.tryParse(parts.last);
  if (month == null || year == null || month < 1 || month > 12) return label;
  final String name = (locale.languageCode == 'ar'
      ? _monthsAr
      : _monthsEn)[month - 1];
  return withYear ? '$name $year' : name;
}

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

/// The title over a crowning: `بطل شهر سبتمبر 2026`, or its two-champion
/// form.
String championTitle(
  AppLocalizations l10n,
  List<MonthChampionDto> champions, [
  Locale locale = const Locale('ar'),
]) {
  final String month = champions.isEmpty
      ? ''
      : championMonthName(champions.first.seasonLabel, locale);
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
                    _gold.withValues(alpha: 0.22),
                    _gold.withValues(alpha: 0),
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
                  colors: <Color>[_white, Colors.transparent],
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

/// Layers 2 to 4: the hero of the leaderboard while a crowning is being
/// celebrated -- the design of 2026-09-29, one hero per champion.
///
/// It can fold into a one-line strip, for a small screen or a player who has
/// seen it; the confetti falls once when it first appears and never loops.
/// The champion sees "شارك تتويجك" under their own hero ([viewerUserId]).
class ChampionSpotlight extends ConsumerStatefulWidget {
  /// Creates the spotlight for [champions] (one or two, of one month).
  const ChampionSpotlight({
    required this.champions,
    required this.keyPrefix,
    this.previewPhotos = const <String, Uint8List>{},
    this.onOpenRecord,
    this.viewerUserId,
    this.margin = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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

  /// The signed-in player: a champion sees the share button on their hero.
  final String? viewerUserId;

  /// Space around the hero.
  final EdgeInsetsGeometry margin;

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

  void _share(MonthChampionDto champion) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => ChampionShareDialog(
          champion: champion,
          previewPhotos: widget.previewPhotos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale locale = Localizations.localeOf(context);
    final List<MonthChampionDto> champions = widget.champions;
    final bool expanded = _expanded ?? true;
    final String title = championTitle(l10n, champions, locale);
    final String p = widget.keyPrefix;

    final Widget controls = Row(
      children: <Widget>[
        if (!expanded) ...<Widget>[
          const ChampionCrown(size: 22),
          const SizedBox(width: AppSpacing.xs),
        ],
        Expanded(
          child: expanded
              ? const SizedBox.shrink()
              : Text(
                  '$title: ${champions.map((c) => c.displayName).join(l10n.boardListSeparator)}',
                  key: Key('$p.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        if (widget.onOpenRecord != null)
          TextButton(
            key: Key('$p.record'),
            onPressed: widget.onOpenRecord,
            style: TextButton.styleFrom(
              foregroundColor: _muted,
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
          color: _muted,
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
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: AppRadius.brLg,
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_navyRaised, _navy],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          // Layer 2: the gold light and ribbons, then the confetti.
          const Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(painter: _RibbonsPainter()),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) => CustomPaint(
                    painter: _ConfettiPainter(
                      progress: _confetti.value,
                      running: _confetti.isAnimating,
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
                  controls,
                  if (expanded)
                    for (final MonthChampionDto c in champions)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: AppSpacing.sm,
                          bottom: AppSpacing.md,
                        ),
                        child: ChampionHeroBody(
                          champion: c,
                          title: title,
                          keyPrefix: p,
                          titleKeyed: c == champions.first,
                          bytes: championPhotoBytes(
                            ref,
                            c,
                            widget.previewPhotos,
                          ),
                          onShare: c.userId == widget.viewerUserId
                              ? () => _share(c)
                              : null,
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

/// One champion's hero: the words on the reading side, the picture in its
/// wreath on the other -- the layout of the design.
class ChampionHeroBody extends StatelessWidget {
  /// Creates the hero of [champion].
  const ChampionHeroBody({
    required this.champion,
    required this.title,
    required this.keyPrefix,
    required this.bytes,
    this.titleKeyed = true,
    this.onShare,
    super.key,
  });

  /// The champion.
  final MonthChampionDto champion;

  /// `بطل شهر سبتمبر 2026`.
  final String title;

  /// The widget-test key namespace.
  final String keyPrefix;

  /// The picture, or null for the first letter.
  final Uint8List? bytes;

  /// Whether the title carries the `.title` key (the first hero only).
  final bool titleKeyed;

  /// Shares the crowning; null hides the button.
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale locale = Localizations.localeOf(context);
    final int? accuracy = champion.accuracyPercent;
    final String id = champion.userId;
    final String? prize = champion.prize;
    final String month = championMonthName(
      champion.seasonLabel,
      locale,
      withYear: false,
    );

    final Widget words = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: const BoxDecoration(
            borderRadius: AppRadius.brXl,
            gradient: LinearGradient(colors: <Color>[_gold, _goldDeep]),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ChampionCrown(size: 16, light: _navyRaised, dark: _navy),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  title,
                  key: titleKeyed ? Key('$keyPrefix.title') : null,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          champion.displayName,
          key: Key('$keyPrefix.name.$id'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: context.text.titleLarge?.copyWith(
            color: _white,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        IntrinsicHeight(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _Stat(
                label: l10n.boardColPoints,
                value: '${champion.points}',
                valueKey: Key('$keyPrefix.points.$id'),
                color: _white,
              ),
              if (accuracy != null) ...<Widget>[
                VerticalDivider(
                  color: _muted.withValues(alpha: 0.4),
                  width: AppSpacing.xl,
                ),
                _Stat(
                  label: l10n.boardColAccuracy,
                  value: '$accuracy%',
                  valueKey: Key('$keyPrefix.accuracy.$id'),
                  color: _gold,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ChampionCrown(size: 14),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                l10n.championCongrats,
                style: context.text.titleSmall?.copyWith(
                  color: _gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const ChampionCrown(size: 14),
          ],
        ),
        Text(
          l10n.championCongratsLine(month),
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(
            color: _white,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (prize != null && prize.trim().isNotEmpty)
          Text(
            l10n.championPrize(prize),
            key: Key('$keyPrefix.prize.$id'),
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(
              color: _gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (onShare != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            key: Key('$keyPrefix.share.$id'),
            onPressed: onShare,
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _navy,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(l10n.championShareButton),
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      label: <String>[
        title,
        champion.displayName,
        l10n.boardPoints(champion.points),
        if (accuracy != null) l10n.boardAccuracyIs(accuracy),
        if (prize != null && prize.trim().isNotEmpty) l10n.championPrize(prize),
      ].join(l10n.boardListSeparator),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double photo = (constraints.maxWidth * 0.3).clamp(84.0, 150.0);
          return Row(
            children: <Widget>[
              Expanded(child: ExcludeSemantics(child: words)),
              const SizedBox(width: AppSpacing.xs),
              ExcludeSemantics(
                child: _Medallion(
                  key: Key('$keyPrefix.photo.$id'),
                  displayName: champion.displayName,
                  bytes: bytes,
                  size: photo,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.color,
  });

  final String label;
  final String value;
  final Key valueKey;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: context.text.labelMedium?.copyWith(color: _muted)),
        Text(
          value,
          key: valueKey,
          textDirection: TextDirection.ltr,
          style: context.text.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

/// The picture in its gold frame, a laurel wreath around it, the crown on
/// top and the place "1" underneath.
class _Medallion extends StatelessWidget {
  const _Medallion({
    required this.displayName,
    required this.bytes,
    required this.size,
    super.key,
  });

  final String displayName;
  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final double badge = size * 0.26;
    return SizedBox(
      width: size * 1.3,
      height: size * 1.55,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            top: size * 0.3,
            child: const CustomPaint(painter: _LaurelPainter()),
          ),
          Positioned(
            top: size * 0.33,
            child: ChampionFramedPhoto(
              displayName: displayName,
              bytes: bytes,
              size: size,
            ),
          ),
          Positioned(top: 0, child: ChampionCrown(size: size * 0.52)),
          Positioned(
            bottom: 0,
            child: Container(
              width: badge,
              height: badge,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[_gold, _goldDeep],
                ),
                border: Border.all(color: _navy, width: 2),
              ),
              child: Text(
                '1',
                style: TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w900,
                  fontSize: badge * 0.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A picture in a round gold frame with its own soft light, the name's first
/// letter standing in when there is no picture.
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
    final String trimmed = displayName.trim();
    final Widget letter = Container(
      color: _navyRaised,
      alignment: Alignment.center,
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: _gold,
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_gold, _goldDeep, _gold],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _gold.withValues(alpha: 0.45),
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

/// The picture the champion shares: the same hero, fixed at a card's width,
/// with the brand's name under it.
class ChampionShareCard extends ConsumerWidget {
  /// Creates the card for [champion].
  const ChampionShareCard({
    required this.champion,
    this.previewPhotos = const <String, Uint8List>{},
    super.key,
  });

  /// The champion.
  final MonthChampionDto champion;

  /// Pictures still on the admin's device, by user id.
  final Map<String, Uint8List> previewPhotos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale locale = Localizations.localeOf(context);
    return Container(
      key: const Key('championShare.card'),
      width: 340,
      decoration: const BoxDecoration(
        borderRadius: AppRadius.brCardLarge,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_navyRaised, _navy],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: CustomPaint(painter: _RibbonsPainter())),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ChampionHeroBody(
                  champion: champion,
                  title: championTitle(l10n, <MonthChampionDto>[
                    champion,
                  ], locale),
                  keyPrefix: 'championShare',
                  bytes: championPhotoBytes(ref, champion, previewPhotos),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: AppRadius.brSm,
                      child: Image.asset(
                        kBrandLogoAsset,
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // Flexible: the card is a fixed 340 wide, and a long
                    // tagline must shorten rather than overflow it.
                    Flexible(
                      child: Text(
                        '${l10n.appTitle} · ${l10n.tagline}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelMedium?.copyWith(
                          color: _muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The share preview: the card as it will be sent, share and close.
class ChampionShareDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for [champion].
  const ChampionShareDialog({
    required this.champion,
    this.previewPhotos = const <String, Uint8List>{},
    super.key,
  });

  /// The champion sharing their crowning.
  final MonthChampionDto champion;

  /// Pictures still on the admin's device, by user id.
  final Map<String, Uint8List> previewPhotos;

  @override
  ConsumerState<ChampionShareDialog> createState() =>
      _ChampionShareDialogState();
}

class _ChampionShareDialogState extends ConsumerState<ChampionShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? code = ref.watch(myReferralProvider).value?.code;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FittedBox(
              child: RepaintBoundary(
                key: _cardKey,
                child: ChampionShareCard(
                  champion: widget.champion,
                  previewPhotos: widget.previewPhotos,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('championShare.share'),
                    onPressed: _sharing ? null : () => unawaited(_send(code)),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(l10n.shareHitShareButton),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  key: const Key('championShare.close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.shareHitCloseButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(String? code) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale locale = Localizations.localeOf(context);
    setState(() => _sharing = true);
    try {
      final RenderObject? object = _cardKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;
      final ui.Image image = await object.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      final String message = l10n.championShareMessage(
        championMonthName(widget.champion.seasonLabel, locale),
      );
      final String text = code == null || code.isEmpty
          ? message
          : '$message\n${l10n.shareHitJoin(inviteLinkFor(code))}';
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: <XFile>[
            XFile.fromData(
              data.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'nukhba-champion.png',
            ),
          ],
          fileNameOverrides: const <String>['nukhba-champion.png'],
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// Gold light from the top and two ribbons sweeping across, with sparkles.
class _RibbonsPainter extends CustomPainter {
  const _RibbonsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Rect all = Offset.zero & size;

    canvas.drawRect(
      all,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.2),
          radius: 0.8,
          colors: <Color>[
            _gold.withValues(alpha: 0.18),
            _gold.withValues(alpha: 0),
          ],
        ).createShader(all),
    );

    final Paint ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (double y0, double y1, double width, double alpha)
        in <(double, double, double, double)>[
          (0.05, 0.35, 0.05, 0.35),
          (0.85, 0.6, 0.04, 0.28),
        ]) {
      ribbon
        ..strokeWidth = h * width
        ..shader = LinearGradient(
          colors: <Color>[
            _goldDeep.withValues(alpha: 0),
            _gold.withValues(alpha: alpha),
            _goldDeep.withValues(alpha: 0),
          ],
        ).createShader(all);
      final Path path = Path()
        ..moveTo(-w * 0.05, h * y0)
        ..cubicTo(
          w * 0.3,
          h * (y0 + 0.25),
          w * 0.6,
          h * (y1 - 0.25),
          w * 1.05,
          h * y1,
        );
      canvas.drawPath(path, ribbon);
    }

    final math.Random random = math.Random(3);
    final Paint sparkle = Paint();
    for (int i = 0; i < 26; i++) {
      final Offset at = Offset(
        random.nextDouble() * w,
        random.nextDouble() * h,
      );
      sparkle.color = _gold.withValues(alpha: 0.25 + random.nextDouble() * 0.5);
      canvas.drawCircle(at, 0.8 + random.nextDouble() * 1.6, sparkle);
    }
  }

  @override
  bool shouldRepaint(_RibbonsPainter oldDelegate) => false;
}

/// Two laurel branches curving up either side of the picture.
class _LaurelPainter extends CustomPainter {
  const _LaurelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height * 0.42);
    final double r = size.width * 0.47;
    final Paint leaf = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[_gold, _goldDeep],
      ).createShader(Offset.zero & size);
    final Paint stem = Paint()
      ..color = _goldDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.012;

    // Screen angles (y down): 90 degrees is straight down. The left branch
    // climbs from just left of the bottom to the upper left; the right one
    // mirrors it.
    const double from = 100 * math.pi / 180;
    const double to = 220 * math.pi / 180;
    for (final bool left in <bool>[true, false]) {
      Offset at(double a) {
        final double angle = left ? a : math.pi - a;
        return center + Offset(math.cos(angle), math.sin(angle)) * r;
      }

      final Path branch = Path()..moveTo(at(from).dx, at(from).dy);
      for (int i = 1; i <= 24; i++) {
        final Offset p = at(from + (to - from) * i / 24);
        branch.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(branch, stem);

      const int leaves = 7;
      for (int i = 0; i < leaves; i++) {
        final double a = from + (to - from) * (i + 0.5) / leaves;
        final double angle = left ? a : math.pi - a;
        final Offset p = at(a);
        for (final double out in <double>[-1, 1]) {
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(angle + out * 0.5);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(out * r * 0.06, 0),
              width: r * 0.09,
              height: r * 0.2,
            ),
            leaf,
          );
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LaurelPainter oldDelegate) => false;
}

/// A light shower of paper pieces, falling once over the hero and fading
/// out. The pieces are fixed (a seeded sequence), so a repaint never
/// reshuffles them mid-fall.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.running});

  static final List<_Piece> _pieces = _Piece.sequence(28);
  static const List<Color> _colors = <Color>[
    _gold,
    _white,
    _goldDeep,
    AppColors.primaryLight,
  ];

  final double progress;
  final bool running;

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
      paint.color = _colors[piece.color % _colors.length].withValues(
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
