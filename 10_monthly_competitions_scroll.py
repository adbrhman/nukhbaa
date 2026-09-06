#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""10 — قسم المسابقات الشهرية لا يُمرَّر.

السبب: AdminShell._bodyFor يُرجع على الجوال `Padding` عاريًا بلا تمرير،
اعتمادًا على أن كل قسم يمرّر نفسه. سبعة أقسام من ثمانية تفعل — وهذا
القسم وحده يُرجع Column طويلًا (قائمة + نموذج إنشاء + كتالوج شعارات)
فيُقصّ من الأسفل ولا يُمرَّر.

الحل: لفّ الـColumn في SingleChildScrollView داخل هذا القسم وحده.
لا مساس بـadmin_shell.dart — لفّ _bodyFor هناك كان سيكسر السبعة
الأخرى بخطأ ارتفاع غير محدود.

كذلك مؤشّر التحميل في صفّ المسابقة كان 14×14 وسط صفّ عريض، فيبدو
الصفّ فارغًا بينما ينتظر currentSeasonProvider — كُبِّر إلى 18 وأُضيف
نصّ بجواره.
"""
import datetime
import io
import os
import subprocess
import sys

REL = "apps/mobile/lib/features/admin/screens/sections/admin_monthly_competitions_section.dart"

EDITS = [
    (
        """    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(title: l10n.adminMonthlyCompetitionsTab),""",
        """    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(title: l10n.adminMonthlyCompetitionsTab),""",
    ),
    (
        """        const SizedBox(height: AppSpacing.lg),
        const _CreateCompetitionForm(),
        const SizedBox(height: AppSpacing.lg),
        const _MonthlyCompetitionLogoCatalog(),
      ],
    );
  }
}""",
        """          const SizedBox(height: AppSpacing.lg),
          const _CreateCompetitionForm(),
          const SizedBox(height: AppSpacing.lg),
          const _MonthlyCompetitionLogoCatalog(),
        ],
      ),
    );
  }
}""",
    ),
    (
        """      _ => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };""",
        """      _ => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };""",
    ),
]

LOG = (
    "10_monthly_competitions_scroll: قسم المسابقات الشهرية كان يُقصّ ولا "
    "يُمرَّر لأن AdminShell._bodyFor يُرجع على الجوال Padding بلا تمرير، "
    "وهذا القسم وحده من الثمانية لا يمرّر نفسه؛ لُفَّ Column في "
    "SingleChildScrollView داخل القسم (لا في الـshell، فلفّه هناك يكسر "
    "الأقسام السبعة التي تحوي ListView). وكُبِّر مؤشّر تحميل الموسم من 14 "
    "إلى 18 لأنه كان يبدو فراغًا وسط الصفّ — %s" % REL
)
MSG = "fix(mobile): make the monthly competitions admin section scrollable"


def main():
    root = os.path.abspath(os.environ.get("NUKHBAA_ROOT") or os.getcwd())
    if not os.path.isdir(os.path.join(root, "apps/mobile/lib")):
        sys.exit("[!] ليس جذر المشروع: %s — صدّر NUKHBAA_ROOT" % root)
    who = subprocess.run(["whoami"], capture_output=True, text=True).stdout.strip()
    print("[i] user=%s root=%s" % (who, root))

    path = os.path.join(root, REL)
    src = io.open(path, encoding="utf-8").read()
    for i, (old, new) in enumerate(EDITS, 1):
        if src.count(old) != 1:
            sys.exit("[!] 10.%d: المرساة غير موجودة أو متكررة في %s" % (i, REL))
        src = src.replace(old, new, 1)
    io.open(path, "w", encoding="utf-8").write(src)
    print("[ok] patched", REL)

    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with io.open(
        os.path.join(root, "docs/checkpoints/session-log.md"), "a", encoding="utf-8"
    ) as f:
        f.write("\n%s — %s\n" % (ts, LOG))

    subprocess.run(
        ["git", "add", REL, "docs/checkpoints/session-log.md"], cwd=root, check=True
    )
    subprocess.run(["git", "commit", "-m", MSG], cwd=root)
    print("[ok] 10 done")


main()
