
## commit (mobile layer) — 2026-08-25
feat(leaderboard): wire mobile layer to FixtureLeaderboard
- api_client, providers, screen tab, l10n (ar/en) — انظر SESSION_STATE.md
- تعديل جذري: pubspec.yaml أضيف apps/mobile لـ workspace
- حذف ملفين: fixture_leaderboard_mobile.patch (untracked)، "h origin main" (شارد من commit سابق)
- flutter analyze: No issues found! / flutter test: +95 All tests passed!
- Phase 6 (FixtureLeaderboard) مكتملة بالكامل الآن. التالي: Phase 7.

## ELITE OBSIDIAN theme — 2026-08-25
- app_colors.dart + app_colors_light.dart: قيم جديدة بالكامل (violet #7C3AED
  primary/action, gold #F5C451 achievement-only, success/warning/info منفصلة
  عن primary/gold — كانت معاد استخدامها سابقًا). لا تغيير بنيوي.
- تحقق: git log بعد الجلسة القادمة لتأكيد commit/push فعليًا حدث.
