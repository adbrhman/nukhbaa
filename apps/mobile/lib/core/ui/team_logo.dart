library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../branding/team_branding.dart';
import '../design/app_stroke.dart';
import '../design/app_tokens.dart';

/// شعار فريق موحّد يستبدل النمط المكرر ثلاث مرات (في
/// current_month_fixtures_screen.dart، شاشة المباراة التي حُذفت لاحقًا،
/// وprediction_history_screen.dart): صورة شبكة (crestUrl) عند توفرها، وإلا
/// دائرة مموّهة بأول حرفين من اسم الفريق — لا دائرة فارغة بلا نص إطلاقًا،
/// سواء لفريق غير معروف أو لفشل تحميل شعار فريق معروف.
///
/// هذا المكوّن لا يستورد أي شيء من `features/` (لا `team_registry.dart`
/// ولا أي حزمة feature أخرى): الطرف المستدعي (شاشة feature تعرف بالفعل
/// `lookupTeam`/`teamDisplayName`) يحلّل هوية الفريق بنفسه ويمرّر
/// [displayName]/[crestUrl]/[brandColor] كبيانات جاهزة، فيبقى `core/ui`
/// بلا أي اعتماد على حزمة feature.
class TeamLogo extends StatelessWidget {
  /// ينشئ شعار فريق.
  const TeamLogo({
    required this.displayName,
    required this.size,
    this.assetPath,
    this.crestUrl,
    this.brandColor,
    super.key,
  });

  /// مسار شعار مرفق داخل التطبيق (مثلاً `assets/team_logos/arsenal.png`).
  /// يسبق [crestUrl] لأنه لا يحتاج شبكة إطلاقًا؛ عند فشله ينتقل العرض
  /// إلى [crestUrl] ثم إلى الحروف الاحتياطية.
  final String? assetPath;

  /// أفضل اسم عرض متاح (مُحلَّل مسبقًا من الطرف المستدعي عبر
  /// `teamDisplayName`) — يُستخدم فقط لاشتقاق حروف fallback عبر
  /// `teamInitials`.
  final String displayName;

  /// رابط شعار مُحلَّل (مثلاً `TeamBrand.logoUrl`)، أو `null` للانتقال
  /// مباشرة إلى حالة الحروف الاحتياطية.
  final String? crestUrl;

  /// لون العلامة التجارية المُحلَّل (مثلاً `TeamBrand.c1`) لتلوين الدائرة
  /// الاحتياطية؛ يُستخدم لون محايد من التوكنز عند غيابه.
  final Color? brandColor;

  /// قطر الدائرة بالبكسل — يحدَّد من الطرف المستدعي حسب موضع الاستخدام
  /// (بطاقة مباراة مصغّرة، رأس شاشة توقع، إلخ) بدل حجم ثابت مفروض هنا.
  final double size;

  /// The least contrast (WCAG) a crest's own colour may have with the card
  /// under it in the dark theme before it gets a plate: 3:1, what an image
  /// needs (script 214, Accessibility Scanner, 2026-11-05: a black crest on
  /// the dark card read 1.31:1 and a navy one 1.06:1).
  static const double minCrestContrast = 3;

  /// The soft light disc behind a dark crest in the dark theme.
  static const Color crestPlate = Color(0xFFEAF0F8);

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final Color? brand = brandColor;
    // A team whose colour is lost on the dark card (Juventus black, navy
    // clubs) sits on a plate; the other crests are drawn as before.
    final bool plated =
        tokens.isDark &&
        brand != null &&
        _contrastOf(brand, tokens.surface) < minCrestContrast;
    // Downscale the decode on native only. On web, cacheWidth/cacheHeight
    // send the image through a resizing createImageBitmap path that loses
    // the alpha channel for some PNGs, which turns a transparent crest into
    // the opaque plate hidden in its fully-transparent pixels.
    //
    // PERF: decode at the device's own density instead of a blanket 4x. On a
    // 3x phone that is a quarter less image memory for every crest on the
    // screen, and 4x was already above any shipping density anyway.
    final double density = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    final int? decodeSize = kIsWeb ? null : (size * density).ceil();
    final String url = crestUrl?.trim() ?? '';
    final Widget fallback = _InitialsCircle(
      diameter: size,
      tint: brandColor ?? tokens.surfaceHigh,
      initials: teamInitials(displayName),
    );
    final Widget networkOrFallback = url.isEmpty
        ? fallback
        : ClipOval(
            child: Image.network(
              url,
              key: ValueKey<String>('teamLogo.$url'),
              width: size,
              height: size,
              cacheWidth: decodeSize,
              cacheHeight: decodeSize,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => fallback,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : fallback,
            ),
          );

    final String asset = assetPath?.trim() ?? '';
    if (asset.isNotEmpty) {
      final Widget image = Image.asset(
        asset,
        key: ValueKey<String>('teamLogo.asset.$asset'),
        width: size,
        height: size,
        cacheWidth: decodeSize,
        cacheHeight: decodeSize,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => networkOrFallback,
      );
      if (tokens.isDark) {
        return plated
            ? _CrestPlate(size: size, child: image)
            : SizedBox(width: size, height: size, child: image);
      }
      // On a white card a flag's white field had no edge (Finland showed a
      // floating cross, England a bare red one): in the light theme every
      // crest sits on one soft plate with a hairline rim (UI-10).
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
    if (url.isEmpty) return fallback;
    final Widget network = ClipOval(
      child: Image.network(
        url,
        key: ValueKey<String>('teamLogo.$url'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
    return plated ? _CrestPlate(size: size, child: network) : network;
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
