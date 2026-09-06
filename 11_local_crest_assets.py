#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""11 — الشعارات المحلّية تسبق شبكة ESPN.

الدليل: شاشة «شعارات فرق المسابقات الشهرية» تعرض الشعارات كاملة في نفس
المتصفّح ونفس البناء (سجلّ الخادم: كل الطلبات 200 من assets/team_logos/)،
بينما بطاقة المباراة تعرض حرفين. الفارق هو المصدر وحده: تلك الشاشة
تقرأ Image.asset محلّيًا، والبطاقة تمرّ عبر TeamBrand.logoUrl إلى
a.espncdn.com.

الحل بلا تبعيات ولا شبكة:
  1) TeamLogo يقبل assetPath اختياريًا ويرسمه بـImage.asset. الترتيب:
     الأصل المحلّي، ثم الشبكة، ثم الحروف — وأي فشل ينزل للتالي.
  2) resolveTeamIdentity يملأ assetPath من teamLogoAssetPath() الموجودة
     أصلًا في team_logo_assets.dart، وهي تقبل الاسمين العربي والإنجليزي
     عبر _arabicTeamLogoAliases.

المعامل اختياري، فمواضع استدعاء TeamLogo الخمسة تبقى سليمة، وتستفيد
كلها لأن الإصلاح في المُحلِّل لا في كل شاشة.

ملاحظة معمارية: core/ui لا يستورد features/ — assetPath يصل كبيانات
جاهزة من الطرف المستدعي، كما هو حال crestUrl وbrandColor اليوم.
"""
import datetime
import io
import os
import subprocess
import sys

LOGO = "apps/mobile/lib/core/ui/team_logo.dart"
IDENT = "apps/mobile/lib/features/competition/team_identity.dart"

LOGO_EDITS = [
    (
        """  const TeamLogo({
    required this.displayName,
    required this.size,
    this.crestUrl,
    this.brandColor,
    super.key,
  });""",
        """  const TeamLogo({
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
  final String? assetPath;""",
    ),
    (
        """    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(""",
        """    final Widget networkOrFallback = url.isEmpty
        ? fallback
        : ClipOval(
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

    final String asset = assetPath?.trim() ?? '';
    if (asset.isNotEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          asset,
          key: ValueKey<String>('teamLogo.asset.$asset'),
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => networkOrFallback,
        ),
      );
    }
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(""",
    ),
]

IDENT_EDITS = [
    (
        """import 'team_registry.dart';""",
        """import 'team_logo_assets.dart';
import 'team_registry.dart';""",
    ),
    (
        """  /// A crest image URL, or `null` to fall back to the initials circle.
  final String? crestUrl;""",
        """  /// A crest image URL, or `null` to fall back to the initials circle.
  final String? crestUrl;

  /// A bundled crest asset path, when one ships with the app. Preferred
  /// over [crestUrl] because it needs no network at all.
  final String? assetPath;""",
    ),
    (
        """  const ResolvedTeamIdentity({
    required this.displayName,
    this.crestUrl,
    this.brandColor,
  });""",
        """  const ResolvedTeamIdentity({
    required this.displayName,
    this.crestUrl,
    this.assetPath,
    this.brandColor,
  });""",
    ),
    (
        """      if (team.id == teamId) {
        return ResolvedTeamIdentity(
          displayName: team.name,
          crestUrl: team.crestUrl,
        );
      }""",
        """      if (team.id == teamId) {
        return ResolvedTeamIdentity(
          displayName: team.name,
          crestUrl: team.crestUrl,
          assetPath: teamLogoAssetPath(team.name),
        );
      }""",
    ),
    (
        """  final TeamBrand? brand = lookupTeam(teamName);
  return ResolvedTeamIdentity(
    displayName: teamDisplayName(teamName),
    crestUrl: brand?.logoUrl,
    brandColor: brand?.c1,
  );""",
        """  final TeamBrand? brand = lookupTeam(teamName);
  return ResolvedTeamIdentity(
    displayName: teamDisplayName(teamName),
    crestUrl: brand?.logoUrl,
    assetPath: teamLogoAssetPath(teamName),
    brandColor: brand?.c1,
  );""",
    ),
]

LOG = (
    "11_local_crest_assets: شعارات الفرق تظهر في شاشة الشعارات الشهرية "
    "(Image.asset محلّي، كل الطلبات 200) وتختفي في بطاقة المباراة "
    "(TeamBrand.logoUrl عبر a.espncdn.com)؛ أُضيف assetPath اختياري إلى "
    "TeamLogo يُرسم بـImage.asset ويسبق الشبكة، ويملؤه resolveTeamIdentity "
    "من teamLogoAssetPath() القائمة أصلًا (تقبل الاسمين العربي والإنجليزي). "
    "المعامل اختياري فمواضع الاستدعاء الخمسة سليمة، وتستفيد كلها لأن "
    "الإصلاح في المُحلِّل — %s + %s" % (LOGO, IDENT)
)
MSG = "fix(mobile): prefer bundled crest assets over the ESPN network URL"


def apply(root, rel, edits, tag):
    path = os.path.join(root, rel)
    src = io.open(path, encoding="utf-8").read()
    for i, (old, new) in enumerate(edits, 1):
        if src.count(old) != 1:
            sys.exit("[!] %s.%d: المرساة غير موجودة أو متكررة في %s" % (tag, i, rel))
        src = src.replace(old, new, 1)
    io.open(path, "w", encoding="utf-8").write(src)
    print("[ok] patched", rel)


def main():
    root = os.path.abspath(os.environ.get("NUKHBAA_ROOT") or os.getcwd())
    if not os.path.isdir(os.path.join(root, "apps/mobile/lib")):
        sys.exit("[!] ليس جذر المشروع: %s — صدّر NUKHBAA_ROOT" % root)
    who = subprocess.run(["whoami"], capture_output=True, text=True).stdout.strip()
    print("[i] user=%s root=%s" % (who, root))

    apply(root, LOGO, LOGO_EDITS, "11a")
    apply(root, IDENT, IDENT_EDITS, "11b")

    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with io.open(
        os.path.join(root, "docs/checkpoints/session-log.md"), "a", encoding="utf-8"
    ) as f:
        f.write("\n%s — %s\n" % (ts, LOG))

    subprocess.run(
        ["git", "add", LOGO, IDENT, "docs/checkpoints/session-log.md"],
        cwd=root,
        check=True,
    )
    subprocess.run(["git", "commit", "-m", MSG], cwd=root)
    print("[ok] 11 done")


main()
