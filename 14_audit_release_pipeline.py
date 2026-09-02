import os
import pathlib
import subprocess

os.chdir(pathlib.Path(__file__).resolve().parent)

def grep(pattern, paths, extra_flags=None):
    flags = extra_flags or []
    r = subprocess.run(
        ["grep", "-rn"] + flags + [pattern] + paths,
        capture_output=True, text=True,
    )
    return r.stdout.strip()

print("==> [1/6] أين يُشار إلى NUKHBA_API_BASE_URL في المستودع كله")
out = grep("NUKHBA_API_BASE_URL", ["."], ["--include=*.dart", "--include=*.yml",
    "--include=*.yaml", "--include=*.sh", "--include=*.gradle", "--include=*.gradle.kts",
    "--include=*.properties"])
print(out if out else "لا مطابقات")

print("")
print("==> [2/6] ملفات GitHub Actions workflows")
wf_dir = pathlib.Path(".github/workflows")
if wf_dir.exists():
    for f in sorted(wf_dir.glob("*.yml")):
        print(str(f))
else:
    print("لا مجلد .github/workflows")

print("")
print("==> [3/6] أين يُستخدم apksigner في المستودع")
out = grep("apksigner", ["."], ["--include=*.yml", "--include=*.yaml", "--include=*.sh",
    "--include=*.gradle", "--include=*.gradle.kts"])
print(out if out else "لا مطابقات")

print("")
print("==> [4/6] سكريبتات/أدوات بناء الـrelease (بحث بالاسم)")
r = subprocess.run(
    ["find", ".", "-iname", "*release*", "-not", "-path", "*/build/*",
     "-not", "-path", "*/.dart_tool/*", "-not", "-path", "*/node_modules/*"],
    capture_output=True, text=True,
)
print(r.stdout.strip() if r.stdout.strip() else "لا نتائج")

print("")
print("==> [5/6] مجلد docs الخاص بـGitHub Pages (adbrhman.github.io/nukhbaa)")
for candidate in ["docs", "gh-pages", "web/docs"]:
    p = pathlib.Path(candidate)
    if p.exists():
        print(candidate + " موجود:")
        r = subprocess.run(["find", candidate, "-maxdepth", "2"], capture_output=True, text=True)
        print(r.stdout)

print("")
print("==> [6/6] ملفات OTA/update ذات صلة (بحث بالاسم داخل apps/mobile)")
r = subprocess.run(
    ["find", "apps/mobile", "-iname", "*update*", "-o", "-iname", "*ota*"],
    capture_output=True, text=True,
)
print(r.stdout.strip() if r.stdout.strip() else "لا نتائج")
