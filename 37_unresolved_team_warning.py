#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""37_unresolved_team_warning — دفعة 4/4: اسم فريق لا يُطابق الكتالوج يُرى."""
import os, json, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
M = os.path.join(ROOT, "apps/mobile")
assert os.path.isdir(M), "apps/mobile not found under %s" % ROOT


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def patch(rel, old, new, count=1):
    p = os.path.join(M, rel)
    s = read(p)
    assert s.count(old) == count, "anchor x%d != %d in %s" % (s.count(old), count, rel)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new, count))
    print("patched", rel)


SEC = "lib/features/admin/screens/sections/fixture_schedule_section.dart"

patch(
    SEC,
    """  /// Resolves [text] against [catalog] (the real `football_data.teams`
  /// catalog) by exact, case-insensitive name match — `null` when the typed
  /// text doesn't (yet) name a real team, which is a legitimate state (a
  /// free-text legacy team name, or a league with no seeded catalog).""",
    """  /// Whether [text] names something but resolves to no catalog team — the
  /// state that must be *visible*.
  ///
  /// A fixture stored with a null `home_team_id`/`away_team_id` still works:
  /// the free-text name is the identity of record (Axiom 3), so nothing
  /// fails, nothing is logged, and the admin gets no signal at all. What
  /// silently disappears is everything keyed off the resolved id — the crest
  /// and the team's brand colour — so the fixture card falls back to two
  /// grey letters. That is exactly how "اسبانيول" (catalog: "إسبانيول") and
  /// "مرسيليا" (catalog: "مارسيليا") shipped: one character off, no error,
  /// found only by eye on a screenshot days later.
  ///
  /// This is deliberately a *warning*, not validation: free text stays legal
  /// — a real fixture whose team is genuinely not in the catalog must remain
  /// submittable, and the button stays enabled. It only refuses to let the
  /// mismatch pass unseen.
  bool _isUnresolvedTeam(List<TeamDto> catalog, String text) =>
      text.trim().isNotEmpty && _resolveTeamId(catalog, text) == null;

  /// Resolves [text] against [catalog] (the real `football_data.teams`
  /// catalog) by exact, case-insensitive name match — `null` when the typed
  /// text doesn't (yet) name a real team, which is a legitimate state (a
  /// free-text legacy team name, or a league with no seeded catalog).""",
)

patch(
    SEC,
    """                onChanged: () => setState(() {
                  _homeTeamId = _resolveTeamId(
                    catalog,
                    _homeTeamController.text,
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              _TeamPickerField(
                fieldKey: const Key('admin.fixtures.awayTeamField'),""",
    """                onChanged: () => setState(() {
                  _homeTeamId = _resolveTeamId(
                    catalog,
                    _homeTeamController.text,
                  );
                }),
              ),
              if (_isUnresolvedTeam(catalog, _homeTeamController.text))
                _UnresolvedTeamHint(
                  key: const Key('admin.fixtures.homeTeamUnresolved'),
                  message: l10n.adminTeamNotInCatalogHint,
                ),
              const SizedBox(height: AppSpacing.md),
              _TeamPickerField(
                fieldKey: const Key('admin.fixtures.awayTeamField'),""",
)

patch(
    SEC,
    """                onChanged: () => setState(() {
                  _awayTeamId = _resolveTeamId(
                    catalog,
                    _awayTeamController.text,
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              AdminSecondaryButton(
                key: const Key('admin.fixtures.kickoffPicker'),""",
    """                onChanged: () => setState(() {
                  _awayTeamId = _resolveTeamId(
                    catalog,
                    _awayTeamController.text,
                  );
                }),
              ),
              if (_isUnresolvedTeam(catalog, _awayTeamController.text))
                _UnresolvedTeamHint(
                  key: const Key('admin.fixtures.awayTeamUnresolved'),
                  message: l10n.adminTeamNotInCatalogHint,
                ),
              const SizedBox(height: AppSpacing.md),
              AdminSecondaryButton(
                key: const Key('admin.fixtures.kickoffPicker'),""",
)

# the hint widget, appended before the file's trailing private field widget
patch(
    SEC,
    """/// جدولة المباريات — اختيار المسابقة/الموسم ثم إضافة مباراة.""",
    """/// سطر تحذير تحت حقل فريق لم يُطابق الكتالوج: نبرة تحذير لا خطأ، فالإرسال
/// يبقى ممكنًا عمدًا.
class _UnresolvedTeamHint extends StatelessWidget {
  const _UnresolvedTeamHint({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: tokens.gold),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: tokens.gold),
            ),
          ),
        ],
      ),
    );
  }
}

/// جدولة المباريات — اختيار المسابقة/الموسم ثم إضافة مباراة.""",
)

patch(
    SEC,
    "import '../../../../core/design/app_spacing.dart';",
    "import '../../../../core/design/app_spacing.dart';\n"
    "import '../../../../core/design/app_tokens.dart';",
)

# l10n
patch(
    "lib/l10n/app_ar.arb",
    '  "fixturesLiveLabel": "مباشر"\n}',
    '  "fixturesLiveLabel": "مباشر",\n'
    '  "adminTeamNotInCatalogHint": "هذا الاسم لا يطابق أي فريق في الكتالوج — '
    'ستُحفظ المباراة بلا شعار الفريق ولا ألوانه. اختر اسمًا من القائمة إن كان الفريق موجودًا."\n}',
)
patch(
    "lib/l10n/app_en.arb",
    '  "fixturesLiveLabel": "Live"\n}',
    '  "fixturesLiveLabel": "Live",\n'
    '  "adminTeamNotInCatalogHint": "This name matches no team in the catalog — '
    'the fixture will be saved without that team\'s crest or colours. Pick a name from the list if the team exists."\n}',
)
patch(
    "lib/l10n/app_localizations.dart",
    "  String get fixturesLiveLabel;\n}",
    "  String get fixturesLiveLabel;\n\n"
    "  /// No description provided for @adminTeamNotInCatalogHint.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'This name matches no team in the catalog — the fixture will be "
    "saved without that team\\'s crest or colours. Pick a name from the list "
    "if the team exists.'**\n"
    "  String get adminTeamNotInCatalogHint;\n}",
)
patch(
    "lib/l10n/app_localizations_ar.dart",
    "  String get fixturesLiveLabel => 'مباشر';\n}",
    "  String get fixturesLiveLabel => 'مباشر';\n\n"
    "  @override\n  String get adminTeamNotInCatalogHint =>\n"
    "      'هذا الاسم لا يطابق أي فريق في الكتالوج — ستُحفظ المباراة بلا شعار "
    "الفريق ولا ألوانه. اختر اسمًا من القائمة إن كان الفريق موجودًا.';\n}",
)
patch(
    "lib/l10n/app_localizations_en.dart",
    "  String get fixturesLiveLabel => 'Live';\n}",
    "  String get fixturesLiveLabel => 'Live';\n\n"
    "  @override\n  String get adminTeamNotInCatalogHint =>\n"
    "      'This name matches no team in the catalog — the fixture will be "
    "saved without that team\\'s crest or colours. Pick a name from the list "
    "if the team exists.';\n}",
)

for arb in ("lib/l10n/app_ar.arb", "lib/l10n/app_en.arb"):
    json.loads(read(os.path.join(M, arb)))
print("ARB files still parse as JSON")

for rel in (SEC, "lib/l10n/app_localizations.dart",
            "lib/l10n/app_localizations_ar.dart",
            "lib/l10n/app_localizations_en.dart"):
    subprocess.run(["dart", "format", os.path.join(M, rel)], check=True)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 37_unresolved_team_warning (4/4): نموذج إضافة المباراة "
    "في لوحة المشرف يحلّ اسم الفريق المكتوب إلى معرّف في الكتالوج بمطابقة "
    "اسم تامّة، وإن لم يطابق أرجع null بلا أي إشارة — والمباراة تُحفظ "
    "بنجاح لأن النصّ الحرّ هو هوية السجل (Axiom 3). ما يختفي صامتًا هو كل "
    "ما يُشتقّ من المعرّف: الشعار ولون النادي، فتظهر البطاقة بحرفين "
    "رماديين. هكذا شُحنت «اسبانيول» (الكتالوج: «إسبانيول») و«مرسيليا» "
    "(الكتالوج: «مارسيليا») — حرف واحد، لا خطأ، واكتُشفتا بالعين في لقطة "
    "شاشة بعد أيام. أُضيف سطر تحذير تحت كل حقل فريق حين يكون النصّ غير "
    "فارغ ولا يُحلّ. تحذير لا تحقّق عمدًا: النصّ الحرّ يبقى مشروعًا وزرّ "
    "الإرسال يبقى مفعَّلًا، فمباراة لفريق خارج الكتالوج فعلًا يجب أن تبقى "
    "قابلة للإرسال؛ المطلوب ألّا يمرّ الخلل دون أن يُرى. مفتاح ARB واحد. "
    "لم تُضف قائمة اختيار الدوري في هذه الدفعة: المباريات الـ21 مُلئت "
    "بـSQL، ولا مباراة جديدة قبل أكتوبر، فالأولوية للحارس الذي يمنع تكرار "
    "الخلل الصامت — "
    "apps/mobile/lib/features/admin/screens/sections/fixture_schedule_section.dart, "
    "apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, "
    "apps/mobile/lib/l10n/app_localizations.dart, "
    "apps/mobile/lib/l10n/app_localizations_ar.dart, "
    "apps/mobile/lib/l10n/app_localizations_en.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = [
    "apps/mobile/lib/features/admin/screens/sections/fixture_schedule_section.dart",
    "apps/mobile/lib/l10n/app_ar.arb",
    "apps/mobile/lib/l10n/app_en.arb",
    "apps/mobile/lib/l10n/app_localizations.dart",
    "apps/mobile/lib/l10n/app_localizations_ar.dart",
    "apps/mobile/lib/l10n/app_localizations_en.dart",
    "docs/checkpoints/session-log.md",
]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "feat(admin): warn when a typed team name resolves to no catalog team"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
