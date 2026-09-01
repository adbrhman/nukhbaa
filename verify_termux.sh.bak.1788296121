#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "==> [1/7] فحص أدوات Termux الأساسية"
pkg list-installed 2>/dev/null | grep -q "^git/" || pkg install -y git
pkg list-installed 2>/dev/null | grep -q "^jq/"  || pkg install -y jq
pkg list-installed 2>/dev/null | grep -q "^unzip/" || pkg install -y unzip

echo "==> [2/7] قراءة إصدار Flutter المثبَّت من .fvmrc"
if [ ! -f .fvmrc ]; then
  echo "خطأ: .fvmrc غير موجود في $REPO_ROOT — تأكد أنك داخل جذر المستودع." >&2
  exit 1
fi
FLUTTER_VERSION="$(jq -r .flutter .fvmrc)"
echo "    الإصدار المطلوب: $FLUTTER_VERSION"

echo "==> [3/7] التحقق من وجود Flutter/Dart في PATH"
if ! command -v flutter >/dev/null 2>&1; then
  cat >&2 <<'EOF'
 يُعثر على أمر flutter في PATH.
EOF
  exit 1
fi

INSTALLED_VERSION="$(flutter --version --machine 2>/dev/null | jq -r .flutterVersion || true)"
if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "$FLUTTER_VERSION" ]; then
  echo "    تحذير: Flutter المثبَّت ($INSTALLED_VERSION) يختلف عن المثبَّت في .fvmrc ($FLUTTER_VERSION)."
fi

echo "==> [4/7] Resolve workspace dependencies (flutter pub get)"
flutter pub get

echo "==> [5/7] توليد الكود (build_runner, mobile)"
(cd apps/mobile && flutter pub run build_runner build --delete-conflicting-outputs)

echo "==> [6/7] Analyze (workspace, fatal warnings) + فحص التنسيق"
dart analyze --fatal-warnings .
dart format --output=none --set-exit-if-changed .

echo "==> [7/7] Import-lint (حدود Clean Architecture) ثم كل الاختبارات (melos)"
dart run tooling/import_lint/bin/import_lint.dart
dart run --no-pub melos run test

echo ""
echo "✅ التحقق اكتمل بنجاح — مطابق لخطوات build-verification.yml."
