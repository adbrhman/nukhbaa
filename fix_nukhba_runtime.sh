#!/usr/bin/env bash
# fix_nukhba_runtime.sh
#
# تشخيص: كود المسارات/AdminApi/CompositionRoot/CORS صحيح ومطابق تمامًا لما
# ذكرته (لا يوجد باغ برمجي ثابت يمكن إثباته من static code وحده). النتيجة
# المعروضة "We could not reach the server..." هي رسالة ErrorPresenter
# الافتراضية لأي AppError.kind == transient — وهي تظهر بنفس الصياغة سواء كان
# السبب api_client.network_unreachable/timeout (فشل شبكة/CORS حقيقي) أو 503
# قادم من السيرفر بكود عمل مختلف (مثل scoring.*) لأن ذلك الكود غير مُدرج في
# جدول ErrorPresenter الخاص، فيسقط لنفس الرسالة العامة. هذا الغموض لا يُحل من
# الكود الساكن؛ يحتاج تشخيصًا وقت التشغيل (هذا السكربت).
# اكتشاف إضافي مهم من فحص .github/workflows: يوجد workflow واحد فقط
# (deploy-pages.yml) ينشر الواجهة الأمامية الثابتة على GitHub Pages، ولا يوجد
# أي workflow في هذا المستودع ينشر apps/server (لا Dockerfile مربوط بأي نشر
# آلي). أي تعديل يُدفع على السيرفر لا ينعكس تلقائيًا على النسخة المنشورة على
# أي مضيف — هذا احتمال جدّي لكون الخادم يشغّل نسخة قديمة أو غير مستجيب أصلًا،
# ولا يمكن نفيه أو إثباته من الكود وحده.
# لذلك: لا تعديل معماري. الإصلاح الوحيد على الكود هو تشخيص مؤقت آمن (بدون أي
# توكن) يعرض AppError.code + AppError.kind تحت رسالة الخطأ في القسم المتأثر
# فقط (احتساب/عرض نقاط الجولة + تقرير الجولة)، بالإضافة لفحوصات شبكة حقيقية
# قابلة للتنفيذ من Termux تحدد أين ينكسر المسار فعليًا.

set -uo pipefail

REPO_ROOT="$(pwd)"
FAIL=0

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; }
err()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$1"; FAIL=1; }

# ----------------------------------------------------------------------------
# 0) تحقق من الموقع + docs/project-context.md + git status
# ----------------------------------------------------------------------------
log "التحقق من جذر المونوريبو والوثائق"
if [ ! -f "pubspec.yaml" ] || [ ! -d "apps/mobile" ] || [ ! -d "apps/server" ]; then
  err "لست في جذر المونوريبو (لا يوجد pubspec.yaml + apps/mobile + apps/server). شغّل السكربت من جذر nukhbaa."
  exit 1
fi
ok "جذر المونوريبو صحيح: $REPO_ROOT"

if [ -f "docs/project-context.md" ]; then
  ok "docs/project-context.md موجود"
else
  warn "docs/project-context.md غير موجود — تابع بحذر"
fi

log "git status (بدون أي تعديل/حذف)"
git status --short || true
git status --short | grep -q . && warn "يوجد تعديلات غير محفوظة في شجرة العمل — لن يتم لمسها أو عمل reset/clean لها."

# ----------------------------------------------------------------------------
# 1) فحص ثابت (تأكيد فقط — لا شيء من هذا يُعدَّل)
# ----------------------------------------------------------------------------
log "تأكيد تطابق مسارات AdminApi مع routes السيرفر"
grep -q "/admin/rounds/\$roundId/scores" packages/api_client/lib/src/admin_api.dart \
  && ok "AdminApi.adminGetRoundScores -> /admin/rounds/{id}/scores مطابق" \
  || err "المسار في AdminApi.adminGetRoundScores غير مطابق للمتوقع"
grep -q "/admin/rounds/\$roundId/report" packages/api_client/lib/src/admin_api.dart \
  && ok "AdminApi.adminGetRoundReport -> /admin/rounds/{id}/report مطابق" \
  || err "المسار في AdminApi.adminGetRoundReport غير مطابق للمتوقع"

[ -f "apps/server/routes/admin/rounds/[id]/scores/index.dart" ] \
  && ok "route السيرفر لـ scores موجود في المصدر" \
  || err "route السيرفر لـ scores غير موجود"
[ -f "apps/server/routes/admin/rounds/[id]/report/index.dart" ] \
  && ok "route السيرفر لـ report موجود في المصدر" \
  || err "route السيرفر لـ report غير موجود"

log "التحقق من عدم وجود workflow ينشر apps/server"
if grep -rl "apps/server" .github/workflows/ >/dev/null 2>&1; then
  ok "يوجد workflow يشير إلى apps/server"
else
  warn "لا يوجد أي GitHub Actions workflow ينشر apps/server في هذا المستودع."
  warn "النشر الوحيد الآلي الموجود هو deploy-pages.yml (الواجهة الثابتة فقط)."
  warn "هذا يعني: لا ضمانة أن الخادم المنشور فعليًا يطابق آخر كود في هذا الفرع."
fi

# ----------------------------------------------------------------------------
# 2) تشخيص شبكي حقيقي من Termux — هنا يُحسم السؤال network vs server-side
# ----------------------------------------------------------------------------
log "تشخيص الشبكة الفعلي (Termux)"
if ! command -v curl >/dev/null 2>&1; then
  warn "curl غير مثبت. ثبّته: pkg install curl"
else
  PAGES_URL="${PAGES_URL:-https://adbrhman.github.io/nukhbaa/main.dart.js}"
  log "جلب حزمة الويب المنشورة فعليًا لاستخراج الـ API base URL المخبوز فيها"
  echo "  URL: $PAGES_URL  (override: PAGES_URL=... )"
  JS_BODY="$(curl -sL --max-time 15 "$PAGES_URL" || true)"
  if [ -z "$JS_BODY" ]; then
    err "تعذّر جلب $PAGES_URL — تأكد من اسم المستودع الصحيح في base-href (مرّر PAGES_URL يدويًا إن اختلف)."
  else
    ok "تم جلب الحزمة ($(echo "$JS_BODY" | wc -c) بايت)"
    echo "  مرشحو API base URL المستخرجون من الحزمة:"
    echo "$JS_BODY" | grep -oE 'https?://[a-zA-Z0-9_.-]+(\.[a-zA-Z]{2,})(:[0-9]+)?' \
      | grep -viE 'gstatic|googleapis|google-analytics|fonts\.|w3\.org|schema\.org|github\.io|localhost' \
      | sort -u | sed 's/^/    - /' | tee /tmp/nukhba_candidate_hosts.txt
    if [ ! -s /tmp/nukhba_candidate_hosts.txt ]; then
      warn "لم يتم استخراج أي مرشح تلقائيًا. مرّر API_BASE_URL يدويًا:"
      echo "    API_BASE_URL=https://your-server-host bash fix_nukhba_runtime.sh"
    fi
  fi

  API_BASE_URL="${API_BASE_URL:-}"
  if [ -z "$API_BASE_URL" ] && [ -s /tmp/nukhba_candidate_hosts.txt ]; then
    API_BASE_URL="$(head -n1 /tmp/nukhba_candidate_hosts.txt)"
    warn "لم يُمرَّر API_BASE_URL — سيُستخدم أول مرشح تلقائيًا: $API_BASE_URL"
    warn "إن كان خاطئًا، أعد التشغيل مع: API_BASE_URL=https://الصحيح"
  fi

  if [ -n "$API_BASE_URL" ]; then
    log "1) فحص /health (بدون auth — يثبت أصل الوصول للخادم)"
    HEALTH_CODE="$(curl -s -o /tmp/nukhba_health_body.txt -w '%{http_code}' --max-time 15 "${API_BASE_URL%/}/health" || echo "curl_error")"
    echo "  HTTP status: $HEALTH_CODE"
    echo "  body: $(cat /tmp/nukhba_health_body.txt 2>/dev/null | head -c 300)"
    if [ "$HEALTH_CODE" = "200" ]; then
      ok "الخادم يستجيب فعليًا على /health -> السبب على الأرجح ليس network_unreachable عام، بل شيء في مسار /admin تحديدًا (auth/CORS/DB)."
    elif [ "$HEALTH_CODE" = "curl_error" ] || [ "$HEALTH_CODE" = "000" ]; then
      err "تعذّر الوصول للخادم إطلاقًا (DNS/اتصال/رفض) -> هذا يطابق api_client.network_unreachable. الخادم غير منشور أو الرابط خاطئ أو DNS/TLS معطّل."
    else
      warn "استجابة غير متوقعة من /health (status=$HEALTH_CODE) -> افحص body أعلاه."
    fi

    log "2) فحص CORS preflight تحديدًا لمسار /admin/rounds/{id}/scores من أصل GitHub Pages"
    CORS_HEADERS="$(curl -s -D - -o /dev/null --max-time 15 \
      -H "Origin: https://adbrhman.github.io" \
      -H "Access-Control-Request-Method: GET" \
      -H "Access-Control-Request-Headers: authorization" \
      -X OPTIONS "${API_BASE_URL%/}/admin/rounds/00000000-0000-0000-0000-000000000000/scores" || true)"
    echo "$CORS_HEADERS" | grep -i "^HTTP\|access-control" || warn "لا رؤوس CORS في الرد — إما preflight لم يصل أو الخادم لا يعيدها لهذا الأصل."
    if echo "$CORS_HEADERS" | grep -qi "access-control-allow-origin: https://adbrhman.github.io"; then
      ok "الخادم يسمح بأصل adbrhman.github.io فعليًا (يطابق routes/_middleware.dart)."
    else
      err "الخادم لا يعيد Access-Control-Allow-Origin للأصل adbrhman.github.io -> هذا سيظهر للمتصفح كفشل شبكة (network_unreachable) رغم أن الخادم حيّ. تحقق من NUKHBA_CORS_ALLOWED_ORIGINS / NUKHBA_ENV في بيئة النشر الفعلية للخادم (قد تكون مضبوطة بقيمة مختلفة عن الكود المحلي)."
    fi

    log "3) اختبار حقيقي للـ endpoint المتأثر (اختياري — يتطلب توكن admin ومعرّف جولة فعلي)"
    if [ -n "${ADMIN_BEARER_TOKEN:-}" ] && [ -n "${ROUND_ID:-}" ]; then
      SCORES_CODE="$(curl -s -o /tmp/nukhba_scores_body.txt -w '%{http_code}' --max-time 20 \
        -H "Authorization: Bearer ${ADMIN_BEARER_TOKEN}" \
        -H "Origin: https://adbrhman.github.io" \
        "${API_BASE_URL%/}/admin/rounds/${ROUND_ID}/scores" || echo "curl_error")"
      echo "  GET /admin/rounds/${ROUND_ID}/scores -> HTTP $SCORES_CODE"
      echo "  body (بدون أي توكن، الرد فقط): $(cat /tmp/nukhba_scores_body.txt 2>/dev/null | head -c 500)"
      case "$SCORES_CODE" in
        200) ok "الـendpoint يعمل فعليًا بالتوكن والمعرّف المعطى — المشكلة كانت بيئة/توكن الجلسة في التطبيق، وليست السيرفر." ;;
        401|403) err "auth مرفوض (status=$SCORES_CODE) -> principal لا يصل بدور admin أو التوكن غير صالح." ;;
        503) err "503 مؤكد من الخادم -> افحص body أعلاه لقيمة code (AppError.code من ErrorResponseDto): scoring.row_corrupt/scoring.*/غيرها = مشكلة بيانات أو DB، ليست شبكة." ;;
        curl_error|000) err "لم يصل الطلب للخادم إطلاقًا رغم /health سابقًا — افحص التوقيت (rate limit/timeout) أو قطع اتصال متقطع." ;;
        *) warn "status غير متوقع: $SCORES_CODE — راجع body." ;;
      esac
    else
      warn "لتشخيص نهائي 100% لهذا الـendpoint تحديدًا، أعد التشغيل مع:"
      echo "    ADMIN_BEARER_TOKEN=<توكن المشرف> ROUND_ID=<معرف جولة فعلي> API_BASE_URL=$API_BASE_URL bash fix_nukhba_runtime.sh"
      echo "  (التوكن لن يُطبع أبدًا؛ يُستخدم فقط في رأس الطلب.)"
    fi
  else
    err "لا يوجد API_BASE_URL معروف — لا يمكن إجراء أي فحص شبكي فعلي. مرّره يدويًا كما هو موضح أعلاه."
  fi
fi

# ----------------------------------------------------------------------------
# 3) التشخيص المؤقت داخل التطبيق: عرض AppError.code + kind تحت رسالة الخطأ
#    فقط في قسم Results/Scoring (حساب نقاط الجولة + تقرير الجولة).
#    Python + assertions: يتوقف فورًا إن اختلف النص المتوقع عن الملف الفعلي.
# ----------------------------------------------------------------------------
log "تطبيق التشخيص المؤقت (Python + assertions، لا تغيير معماري)"

python3 - "$REPO_ROOT" <<'PYEOF'
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(path, old, new, label):
    p = root / path
    assert p.exists(), f"الملف غير موجود: {path}"
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    assert count == 1, (
        f"[{label}] توقّع تطابق واحد بالضبط في {path}، وُجد {count}. "
        "توقفت دون تعديل — النص المتوقع لم يعد مطابقًا لما في الريبو."
    )
    p.write_text(text.replace(old, new), encoding="utf-8")
    print(f"  ✓ عُدّل: {path} [{label}]")

# 1) AdminErrorBanner: إضافة debugDetail اختياري (مؤقت للتشخيص فقط)
ui_kit = "apps/mobile/lib/features/admin/widgets/admin_ui_kit.dart"
old_banner = """class AdminErrorBanner extends StatelessWidget {
  const AdminErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: t.error, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(color: t.error),
            ),
          ),
        ],
      ),
    );
  }
}"""
new_banner = """class AdminErrorBanner extends StatelessWidget {
  const AdminErrorBanner({
    super.key,
    required this.message,
    this.debugDetail,
  });

  final String message;

  /// TEMP DIAGNOSTIC — remove once the transient-error root cause behind
  /// "We could not reach the server" is confirmed and fixed at its source.
  /// Renders [AppError.kind]/[AppError.code] beneath [message] so a real
  /// network failure (api_client.network_unreachable/timeout) can be told
  /// apart from a decoded server-side transient (e.g. scoring.*), which
  /// ErrorPresenter otherwise collapses into the same sentence. Never
  /// includes the bearer token or any response body.
  final String? debugDetail;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: t.error, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: context.text.bodySmall?.copyWith(color: t.error),
                ),
                if (debugDetail != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    debugDetail!,
                    style: context.text.labelSmall?.copyWith(
                      color: t.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}"""
patch(ui_kit, old_banner, new_banner, "AdminErrorBanner.debugDetail")

# 2) results_scoring_section.dart: تمرير debugDetail لثلاث بانرات فقط
#    (scoreState / lookupState / reportState) — القسمان المتأثران بالمشكلة.
section = "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart"

old_helper_anchor = "class _ResultsScoringSectionState extends ConsumerState<ResultsScoringSection> {\n  final _homeGoals = TextEditingController();"
new_helper_anchor = (
    "class _ResultsScoringSectionState extends ConsumerState<ResultsScoringSection> {\n"
    "  // TEMP DIAGNOSTIC — remove alongside AdminErrorBanner.debugDetail above.\n"
    "  String _diag(AppError e) => '${e.kind.name} \u00b7 ${e.code}';\n\n"
    "  final _homeGoals = TextEditingController();"
)
patch(section, old_helper_anchor, new_helper_anchor, "_diag helper")

old_score = """              if (scoreState is AsyncError<RoundScoresDto>)
                AdminErrorBanner(
                  message: ErrorPresenter.message(scoreState.error as AppError),
                ),"""
new_score = """              if (scoreState is AsyncError<RoundScoresDto>)
                AdminErrorBanner(
                  message: ErrorPresenter.message(scoreState.error as AppError),
                  debugDetail: _diag(scoreState.error as AppError),
                ),"""
patch(section, old_score, new_score, "scoreState banner")

old_lookup = """        if (lookupState is AsyncError<RoundScoresDto>)
          AdminErrorBanner(
            message: ErrorPresenter.message(lookupState.error as AppError),
          ),"""
new_lookup = """        if (lookupState is AsyncError<RoundScoresDto>)
          AdminErrorBanner(
            message: ErrorPresenter.message(lookupState.error as AppError),
            debugDetail: _diag(lookupState.error as AppError),
          ),"""
patch(section, old_lookup, new_lookup, "lookupState banner")

old_report = """              if (reportState is AsyncError<List<RoundReportRow>>)
                AdminErrorBanner(
                  message: ErrorPresenter.message(
                    reportState.error as AppError,
                  ),
                ),"""
new_report = """              if (reportState is AsyncError<List<RoundReportRow>>)
                AdminErrorBanner(
                  message: ErrorPresenter.message(
                    reportState.error as AppError,
                  ),
                  debugDetail: _diag(reportState.error as AppError),
                ),"""
patch(section, old_report, new_report, "reportState banner")

print("تم تطبيق كل التعديلات المؤقتة بنجاح.")
PYEOF
PY_STATUS=$?

if [ $PY_STATUS -ne 0 ]; then
  err "توقف تعديل Python — لم يُطبَّق أي تشخيص مؤقت. راجع الرسالة أعلاه (على الأرجح النص في الريبو تغيّر عن المتوقع)."
else
  ok "التشخيص المؤقت طُبِّق على: admin_ui_kit.dart + results_scoring_section.dart"
fi

MODIFIED_FILES="apps/mobile/lib/features/admin/widgets/admin_ui_kit.dart apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart"

# ----------------------------------------------------------------------------
# 4) dart format للملفات المعدلة فقط
# ----------------------------------------------------------------------------
if [ $PY_STATUS -eq 0 ]; then
  log "dart format للملفات المعدلة"
  if command -v dart >/dev/null 2>&1; then
    dart format $MODIFIED_FILES || err "dart format فشل"
  else
    err "dart غير موجود في PATH — لم يُشغَّل dart format. ثبّت Flutter SDK قبل المتابعة."
  fi
fi

# ----------------------------------------------------------------------------
# 5) build_runner — غير مطلوب هنا (لا تعديل على أي كلاس بـ codegen annotations)
# ----------------------------------------------------------------------------
log "build_runner"
warn "تخطّي: لا التعديل يمسّ أي كلاس codegen (@riverpod/@freezed/إلخ) — غير مطلوب لهذا التغيير."

# ----------------------------------------------------------------------------
# 6) الاختبارات + melos run verify
# ----------------------------------------------------------------------------
if [ $PY_STATUS -eq 0 ]; then
  if command -v melos >/dev/null 2>&1 || command -v dart >/dev/null 2>&1; then
    log "melos run verify (format-check + analyze + import-lint + test + test-mobile)"
    if command -v melos >/dev/null 2>&1; then
      melos run verify || err "melos run verify فشل — راجع المخرجات أعلاه ولا تتجاهلها."
    else
      warn "melos غير مثبت عالميًا — تشغيل عبر dart pub global أو تفعيله يدويًا مطلوب."
      dart pub global run melos run verify 2>/dev/null || err "تعذّر تشغيل melos. ثبّته: dart pub global activate melos"
    fi
  else
    err "لا dart ولا melos متاحين — لا يمكن تشغيل الاختبارات. ثبّت Flutter SDK (يوفر dart) ثم dart pub global activate melos."
  fi
fi

# ----------------------------------------------------------------------------
# 7) عرض git diff/stat النهائي — لا commit، لا reset، لا clean
# ----------------------------------------------------------------------------
log "git diff --stat"
git diff --stat -- $MODIFIED_FILES 2>/dev/null || true

log "git diff الكامل"
git diff -- $MODIFIED_FILES 2>/dev/null || true

echo
if [ "$FAIL" -eq 1 ]; then
  echo "النتيجة: توجد إخفاقات أعلاه (FAIL) — لم يُخفَ أي منها. راجعها قبل أي دفع/نشر."
  exit 1
else
  echo "النتيجة: التشخيص المؤقت طُبِّق بدون إخفاء أي فشل. راجع مخرجات فحوصات الشبكة أعلاه"
  echo "لتحديد السبب الحقيقي بدقة (network/CORS مقابل 503 من الخادم)، ثم أزل"
  echo "debugDetail/_diag بعد التأكد — هذا تشخيص مؤقت وليس إصلاحًا نهائيًا للسبب الجذري."
fi
