import subprocess

PATH = "apps/mobile/lib/features/admin/widgets/admin_pickers.dart"

with open(PATH, "r", encoding="utf-8") as f:
    content = f.read()

START = "/// قائمة الجولة المنسدلة"
END = "/// قائمة المباراة المنسدلة (الموسم ← المباراة مباشرة"

i = content.index(START)
j = content.index(END)
assert i < j

content = content[:i] + content[j:]

if "class RoundPickerField" in content or "class FixturePickerField" in content:
    raise SystemExit("فشل: الكلاسات لم تُحذف بالكامل")

count = content.count("l10n.adminNoFixturesHint")
if count != 1:
    raise SystemExit(f"فشل: توقعت مرجعًا واحدًا، وجدت {count}")
content = content.replace("l10n.adminNoFixturesHint", "l10n.adminNoSeasonFixturesHint")

with open(PATH, "w", encoding="utf-8") as f:
    f.write(content)

print("حُذف RoundPickerField + FixturePickerField")
print("صُحّح: adminNoFixturesHint -> adminNoSeasonFixturesHint")

print("\n== dart format ==")
subprocess.run(["dart", "format", PATH])

print("\n== flutter analyze ==")
subprocess.run(["flutter", "analyze"], cwd="apps/mobile")

print("\n== git diff --stat ==")
subprocess.run(["git", "diff", "--stat", "--", PATH])
