library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../branding/team_branding.dart';
import '../crests/club_crests.dart';
import '../design/app_stroke.dart';
import '../design/app_tokens.dart';

/// A team's mark: the club's crest when the owner's list has it (script
/// 266, read through [ClubCrestScope]), the country's flag shipped with the
/// app ([assetPath]), or else a disc in the team's colour with the first two
/// letters of its name -- never an empty circle.
///
/// The club crests are their owners' marks: none ships inside the app, none
/// is read from a provider's or a third party's address, and a crest the
/// owner hid is gone from the next frame. The caller resolves the team
/// (`resolveTeamIdentity`) and passes [crestSlug], [assetPath] and
/// [brandColor] as data, so `core/ui` imports no feature.
class TeamLogo extends StatelessWidget {
  /// Creates a team mark.
  const TeamLogo({
    required this.displayName,
    required this.size,
    this.assetPath,
    this.crestSlug,
    this.brandColor,
    super.key,
  });

  /// A country's flag shipped with the app (`assets/flags/<slug>.png`).
  final String? assetPath;

  /// The club's slug in the owner's crest list (`GET /crests`), drawn when
  /// this device holds its file.
  final String? crestSlug;

  /// The best display name (`teamDisplayName`), for the disc's letters.
  final String displayName;

  /// The team's colour (`TeamBrand.c1`) for the disc, or the neutral token.
  final Color? brandColor;

  /// The diameter, chosen by the caller for where it is drawn.
  final double size;

  /// The least contrast (WCAG) a crest's own colour may have with the card
  /// under it in the dark theme before it gets a plate: 3:1, what an image
  /// needs (script 214, Accessibility Scanner, 2026-11-05: a black crest on
  /// the dark card read 1.31:1 and a navy one 1.06:1).
  static const double minCrestContrast = 3;

  /// The soft light disc behind a dark crest in the dark theme.
  static const Color crestPlate = Color(0xFFEAF0F8);

  /// A flag's height to its width: every file under `assets/flags/` is
  /// 4:3 (script 271), drawn as one rounded card.
  static const double flagAspect = 0.75;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final Widget fallback = _InitialsCircle(
      diameter: size,
      tint: brandColor ?? tokens.surfaceHigh,
      initials: teamInitials(displayName),
    );
    final ImageProvider? crest = ClubCrestScope.imageOf(context, crestSlug);
    final String asset = assetPath?.trim() ?? '';
    if (crest == null && asset.isEmpty) return fallback;

    // Downscale the decode on native only. On web, a resized decode goes
    // through a createImageBitmap path that loses the alpha channel for
    // some PNGs, which turns a transparent crest into the opaque plate
    // hidden in its fully-transparent pixels. At the device's own density:
    // 4x was above any shipping density.
    final double density = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    final int? decodeSize = kIsWeb ? null : (size * density).ceil();
    // A country's flag: one rounded 4:3 card for every flag, in both
    // themes, never on the crests' plate (script 271).
    if (crest == null) {
      return _FlagMark(
        asset: asset,
        size: size,
        decodeWidth: decodeSize,
        fallback: fallback,
      );
    }
    final Widget image = Image(
      key: ValueKey<String>('teamLogo.crest.$crestSlug'),
      image: decodeSize == null
          ? crest
          : ResizeImage(
              crest,
              width: decodeSize,
              height: decodeSize,
              policy: ResizeImagePolicy.fit,
            ),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => fallback,
    );

    final Color? brand = brandColor;
    if (tokens.isDark) {
      // A crest whose colour is lost on the dark card (Juventus black, navy
      // clubs) sits on a plate; the other crests are drawn as they are.
      final bool plated =
          brand != null &&
          _contrastOf(brand, tokens.surface) < minCrestContrast;
      return plated
          ? _CrestPlate(size: size, child: image)
          : SizedBox(width: size, height: size, child: image);
    }
    // In the light theme every crest sits on one soft plate with a hairline
    // rim (UI-10); a flag draws its own rim (_FlagMark).
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tokens.surfaceHigh,
        border: Border.all(color: tokens.border, width: AppStroke.hairline),
      ),
      child: image,
    );
  }
}

/// A country's flag (script 271): one rounded 4:3 card for every flag, in
/// both themes, with a hairline rim so a white field still has an edge
/// (UI-10: Finland's cross floated on a white card). The files are 4:3
/// (flag-icons, MIT, `docs/licenses/flag-icons.txt`). A flag never sits on
/// the crests' plate: the plate is for a club crest lost on the dark card.
class _FlagMark extends StatelessWidget {
  const _FlagMark({
    required this.asset,
    required this.size,
    required this.decodeWidth,
    required this.fallback,
  });

  final String asset;
  final double size;
  final int? decodeWidth;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final double height = size * TeamLogo.flagAspect;
    final BorderRadius radius = BorderRadius.circular(size * 0.12);
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          key: const Key('teamLogo.flag'),
          width: size,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surfaceHigh,
            borderRadius: radius,
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: tokens.border, width: AppStroke.hairline),
          ),
          child: Image.asset(
            asset,
            key: ValueKey<String>('teamLogo.asset.$asset'),
            width: size,
            height: height,
            cacheWidth: decodeWidth,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => fallback,
          ),
        ),
      ),
    );
  }
}

/// WCAG contrast ratio of two opaque colours.
double _contrastOf(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The light disc a dark crest sits on in the dark theme.
class _CrestPlate extends StatelessWidget {
  const _CrestPlate({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('teamLogo.plate'),
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: TeamLogo.crestPlate,
      ),
      child: child,
    );
  }
}

/// الدائرة الاحتياطية: تهيّئة لونية + الحرفان الأولان من اسم الفريق،
/// بحجم خط يتكيّف تلقائيًا مع [diameter] عبر `FittedBox` كي يبقى النص
/// مقروءًا في كل الأحجام المستخدمة فعليًا في التطبيق (من 22 إلى
/// `AppSizes.iconLg`).
class _InitialsCircle extends StatelessWidget {
  const _InitialsCircle({
    required this.diameter,
    required this.tint,
    required this.initials,
  });

  final double diameter;
  final Color tint;
  final String initials;

  @override
  Widget build(BuildContext context) {
    // The initials take whichever text colour reads on the team's own
    // colour: the theme's text colour was white even on a yellow (UI-11).
    final Color ink =
        ThemeData.estimateBrightnessForColor(tint) == Brightness.dark
        ? AppTokens.dark.textPrimary
        : AppTokens.light.textPrimary;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      padding: EdgeInsets.all(diameter * 0.16),
      decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          initials,
          maxLines: 1,
          style: TextStyle(color: ink, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
