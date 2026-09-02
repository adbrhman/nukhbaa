import os

FILES_TO_DELETE = [
    "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart.orig",
    "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart.rej",
    "apps/mobile/lib/features/admin/widgets/admin_pickers.dart.rej",
    "docs/checkpoints/session-log.md.orig",
    "docs/checkpoints/session-log.md.rej",
    "Fixture with incomplete data",
    "This round has no fixtures.",
    "This season has no fixtures.",
    "لا توجد مباريات في هذا الموسم.",
    "لا توجد مباريات في هذه الجولة.",
    "مباراة غير مكتملة البيانات",
]

for f in FILES_TO_DELETE:
    if os.path.exists(f):
        os.remove(f)
        print(f"حُذف: {f}")
    else:
        print(f"غير موجود (تخطّي): {f}")

print("\n== git status ==")
os.system("git status --porcelain")
