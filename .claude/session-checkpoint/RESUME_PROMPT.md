أنا عبود، متابعة مباشرة على nukhbaa. اقرأ SESSION_STATE.md وCHANGES.md كاملين
قبل أي رد. لا تبدأ من الصفر ولا تُعِد عملًا مكتملًا.

الجذر: /home/dev/nukhbaa-backup-1787537565 (GitHub adbrhman/nukhbaa, main).

Phase 6 (FixtureLeaderboard) مكتملة 100% — backend + mobile، مدفوعة،
مختبرة (flutter analyze نظيف، flutter test +95 كلها ناجحة).

الخطوة التالية: بدء Phase 7 — حذف Round/RoundId/RoundStatus/RoundFixture
بالكامل من الكود + مراجعة hexagonal architecture. لم يبدأ أي شيء فيها بعد.

قواعد ثابتة: لا Placeholders، تحقّق من الإصدارات، لا تعديل معماري دون
موافقة صريحة، Result/AppError فقط، النقاط تُحسب في السيرفر فقط، احترم
import_lint. Termux: استخدم base64 heredoc لأي سكربت Python فيه نص عربي.
بعد كل خطوة: احفظ فعليًا، تحقّق git status/diff، حدّث ملفات checkpoint،
لا تدّعِ نجاحًا دون مخرجات فعلية.
