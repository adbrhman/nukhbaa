#!/usr/bin/env python3
# 37_saudi_crests_local — الشعارات التي فشل تنزيلها موجودة في المستودع.
import csv, io, os, shutil, subprocess

ROOT = os.path.expanduser('~/nukhbaa-backup-1787537565')
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
DART = os.path.join(ROOT, 'apps/mobile/lib/features/competition/team_logo_assets.dart')
ASSETS = os.path.join(ROOT, 'apps/mobile/assets/team_logos')
CSV = os.path.join(ROOT, 'supabase/seed_assets/saudi-2026-27-teams.csv')
SRC = os.path.join(ROOT, 'docs/handoff/logos-2026-27/spl-2026-27')
for p in (DART, CSV):
    assert os.path.isfile(p), 'MISSING: ' + p
assert os.path.isdir(SRC), 'MISSING: ' + SRC

AR = {'al-hilal': u'\u0627\u0644\u0647\u0644\u0627\u0644',
      'al-faisaly': u'\u0627\u0644\u0641\u064a\u0635\u0644\u064a'}

copied = []
with io.open(CSV, encoding='utf-8') as f:
    for row in csv.reader(f):
        if len(row) < 5 or row[0] == 'filename':
            continue
        filename, slug = row[0].strip(), row[4].strip()
        dest = os.path.join(ASSETS, slug + '.png')
        if os.path.isfile(dest):
            continue
        src = os.path.join(SRC, filename)
        if not os.path.isfile(src):
            print('SKIP %s — source missing' % slug)
            continue
        with open(src, 'rb') as fh:
            if not fh.read(4).startswith(b'\x89PNG'):
                print('SKIP %s — not a PNG' % slug)
                continue
        shutil.copyfile(src, dest)
        copied.append(slug)

print('copied: %s' % (', '.join(copied) or 'none'))
if not copied:
    raise SystemExit('nothing copied; Dart left untouched')

src_txt = io.open(DART, encoding='utf-8').read()
SET_A = "\n  'anderlecht',\n"
MAP_A = u"\n  '\u0641\u0627\u064a\u0643\u064a\u0646\u063a': 'viking',\n"
assert src_txt.count(SET_A) == 1 and src_txt.count(MAP_A) == 1, 'ANCHOR DRIFT'
add_set = ''.join("  '%s',\n" % s for s in copied if "\n  '%s',\n" % s not in src_txt)
src_txt = src_txt.replace(SET_A, SET_A + add_set, 1)
add_map = ''.join(u"  '%s': '%s',\n" % (AR[s], s) for s in copied if s in AR
                  and u"'%s': '%s'," % (AR[s], s) not in src_txt)
src_txt = src_txt.replace(MAP_A, MAP_A + add_map, 1)
io.open(DART, 'w', encoding='utf-8').write(src_txt)
print('WIRED %d' % len(copied))

entry = (u"\n2026-09-06 \u2014 37_saudi_crests_local: \u0627\u0644\u0647\u0644\u0627\u0644 "
         u"\u0648\u0627\u0644\u0641\u064a\u0635\u0644\u064a \u0641\u0634\u0644 "
         u"\u062a\u0646\u0632\u064a\u0644\u0647\u0645\u0627 \u0641\u064a "
         u"36_missing_crests (404 \u0645\u0646 CDN \u0628\u0645\u0639\u0631\u0651\u0641\u0627\u062a "
         u"team_registry.dart \u0627\u0644\u0645\u0642\u062f\u0651\u0631\u0629)\u060c "
         u"\u0648\u0645\u0644\u0641\u0627\u0647\u0645\u0627 \u0645\u0648\u062c\u0648\u062f\u0627\u0646 "
         u"\u0623\u0635\u0644\u0627\u064b \u0641\u064a "
         u"docs/handoff/logos-2026-27/spl-2026-27 \u0645\u0646\u0630 \u0628\u0630\u0631\u0629 "
         u"\u0627\u0644\u062f\u0648\u0631\u064a \u0627\u0644\u0633\u0639\u0648\u062f\u064a. "
         u"\u0627\u0644\u0646\u0633\u062e \u0645\u062d\u0644\u0651\u064a \u0645\u0646 CSV "
         u"seed_assets \u0644\u0627 \u0628\u0623\u0633\u0645\u0627\u0621 "
         u"\u0645\u0643\u062a\u0648\u0628\u0629 \u064a\u062f\u0648\u064a\u0627\u064b\u060c "
         u"\u0641\u064a\u0634\u0645\u0644 \u0623\u064a \u0634\u0631\u064a\u062d\u0629 "
         u"\u0633\u0639\u0648\u062f\u064a\u0629 \u0646\u0627\u0642\u0635\u0629 "
         u"\u0645\u0633\u062a\u0642\u0628\u0644\u0627\u064b. "
         u"\u0627\u0644\u062f\u0631\u0633: \u0645\u0635\u062f\u0631 \u062f\u0627\u062e\u0644 "
         u"\u0627\u0644\u0645\u0633\u062a\u0648\u062f\u0639 \u064a\u064f\u0642\u062f\u0651\u0645 "
         u"\u0639\u0644\u0649 \u0627\u0644\u0634\u0628\u0643\u0629 "
         u"\u2014 apps/mobile/lib/features/competition/team_logo_assets.dart, "
         u"apps/mobile/assets/team_logos/*.png\n")
with io.open(os.path.join(ROOT, 'docs/checkpoints/session-log.md'), 'a',
             encoding='utf-8') as f:
    f.write(entry)

subprocess.check_call(['git', 'add', '-A'], cwd=ROOT)
subprocess.check_call(['git', 'commit', '-m',
                       '37_saudi_crests_local: copy the two remaining crests from the repo'],
                      cwd=ROOT)
