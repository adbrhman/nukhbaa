library;

import 'package:flutter/material.dart';

import '../branding/team_branding.dart';
import '../design/app_tokens.dart';

/// شعار فريق موحّد يستبدل النمط المكرر ثلاث مرات (في
/// current_month_fixtures_screen.dart، fixture_prediction_screen.dart،
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
    this.crestUrl,
    this.brandColor,
    super.key,
  });

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

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String url = crestUrl?.trim() ?? '';
    final Widget fallback = _InitialsCircle(
      diameter: size,
      tint: brandColor ?? tokens.surfaceHigh,
      initials: teamInitials(displayName),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
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
    final AppTokens tokens = context.tokens;
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
          style: TextStyle(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
