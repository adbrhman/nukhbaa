#!/usr/bin/env bash
set -euo pipefail
cd /home/dev/nukhbaa-backup-1787537565

python3 << 'PY'
path = "apps/server/lib/composition/composition_root.dart"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

edits = [
    # 1) required param في المُنشئ الخاص
    (
        "    required this.listMyFixturePredictions,\n"
        "  }) : _connection = connection,\n"
        "       _jwksClient = jwksClient;",
        "    required this.listMyFixturePredictions,\n"
        "    required this.listMyActiveSeasons,\n"
        "  }) : _connection = connection,\n"
        "       _jwksClient = jwksClient;",
    ),
    # 2) optional param في forTesting
    (
        "    ListMyFixturePredictions? listMyFixturePredictions,\n"
        "  }) : checkHealth = checkHealth ?? _absentCheckHealth(),",
        "    ListMyFixturePredictions? listMyFixturePredictions,\n"
        "    ListMyActiveSeasons? listMyActiveSeasons,\n"
        "  }) : checkHealth = checkHealth ?? _absentCheckHealth(),",
    ),
    # 3) absent default assignment
    (
        "       listMyFixturePredictions =\n"
        "           listMyFixturePredictions ?? _absentListMyFixturePredictions(),\n"
        "       _connection = null,\n"
        "       _jwksClient = null;",
        "       listMyFixturePredictions =\n"
        "           listMyFixturePredictions ?? _absentListMyFixturePredictions(),\n"
        "       listMyActiveSeasons =\n"
        "           listMyActiveSeasons ?? _absentListMyActiveSeasons(),\n"
        "       _connection = null,\n"
        "       _jwksClient = null;",
    ),
    # 4) static absent factory
    (
        "  static ListMyFixturePredictions _absentListMyFixturePredictions() =>\n"
        "      ListMyFixturePredictions(\n"
        "        fixturePredictionRepository: _unwiredFixturePredictionRepository,\n"
        "      );",
        "  static ListMyFixturePredictions _absentListMyFixturePredictions() =>\n"
        "      ListMyFixturePredictions(\n"
        "        fixturePredictionRepository: _unwiredFixturePredictionRepository,\n"
        "      );\n"
        "\n"
        "  static ListMyActiveSeasons _absentListMyActiveSeasons() =>\n"
        "      ListMyActiveSeasons(\n"
        "        competitionRepository: _unwiredCompetitionRepository,\n"
        "        clock: _unwiredClock,\n"
        "      );",
    ),
    # 5) إعلان الحقل
    (
        "  final ListMyFixturePredictions listMyFixturePredictions;",
        "  final ListMyFixturePredictions listMyFixturePredictions;\n"
        "\n"
        "  /// Lists every season [principal] is an active participant in right now\n"
        "  /// (participant-scoped analogue of [listMyFixturePredictions]; the client\n"
        "  /// fans out per season to [browseSeasonFixtures]).\n"
        "  final ListMyActiveSeasons listMyActiveSeasons;",
    ),
    # 6) الربط الإنتاجي
    (
        "      listMyFixturePredictions: ListMyFixturePredictions(\n"
        "        fixturePredictionRepository:\n"
        "            fixturePredictionRepository, // already built\n"
        "      ),\n"
        "    );\n"
        "  }",
        "      listMyFixturePredictions: ListMyFixturePredictions(\n"
        "        fixturePredictionRepository:\n"
        "            fixturePredictionRepository, // already built\n"
        "      ),\n"
        "      listMyActiveSeasons: ListMyActiveSeasons(\n"
        "        competitionRepository: competitionRepository,\n"
        "        clock: clock,\n"
        "      ),\n"
        "    );\n"
        "  }",
    ),
]

for i, (old, new) in enumerate(edits, start=1):
    count = content.count(old)
    if count != 1:
        raise SystemExit(f"فشل: النمط رقم {i} وُجد {count} مرة بدل 1 — توقف بلا تعديل")
    content = content.replace(old, new)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: 6 مواضع ListMyActiveSeasons مربوطة في composition_root.dart")
PY

echo "== flutter analyze apps/server =="
if flutter analyze apps/server; then
  ANALYZE_STATUS="نجح"
else
  ANALYZE_STATUS="فشل"
fi

echo "== flutter test apps/server =="
if flutter test apps/server; then
  TEST_STATUS="نجح"
else
  TEST_STATUS="فشل"
fi

if [ "$ANALYZE_STATUS" = "نجح" ] && [ "$TEST_STATUS" = "نجح" ]; then
  cat >> docs/checkpoints/session-log.md << EOF
- [$(date +%H:%M)] إصلاح: ربط ListMyActiveSeasons (6 مواضع: required param، optional param، absent default، absent factory، field، production wiring) | ملف: apps/server/lib/composition/composition_root.dart | اختبار: نجح
EOF
  git add -A
  git commit -m "feat: wire ListMyActiveSeasons into composition_root"
  git log --oneline -1
  echo "✅ تم الالتزام محليًا — بانتظار إذن push."
else
  echo "❌ توقف: analyze=$ANALYZE_STATUS test=$TEST_STATUS — لا commit."
  exit 1
fi
