# تسليم: شعارات دوري أبطال أوروبا 2026-27 + الدوري السعودي 2026-27

## المحتوى
- `ucl-2026-27/` — 36 شعار PNG
- `spl-2026-27/` — 18 شعار PNG
- `LOGOS_MANIFEST.csv` — كل ملف مع اسم فريق **مُستنتَج من اسم الملف فقط** (غير موثوق)

## المطلوب (تنفيذ محلي، لا تخمين)
1. اقرأ docs/project-context.md وحدّد آلية تخزين شعارات الفرق/المسابقات الفعلية
   (Supabase Storage bucket + عمود logo_url/logo_path في أي جدول، أو Assets محلية).
2. طابق كل صف في LOGOS_MANIFEST.csv مع اسم الفريق الحقيقي في القاعدة (عمود
   guessed_team_name تخمين آلي وليس معتمداً).
3. نفّذ الإدخال/الرفع بنفس قيود المشروع: بلا تبعيات جديدة، بلا placeholders،
   احترام import_lint وResult/AppError عند أي كود Dart، بلا تغيير معماري.
4. حدّث docs/checkpoints/session-log.md ثم git add -A و git commit محلي بلا push.
