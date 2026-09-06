#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""14 — «ترحيل إلى السجل» يفشل بـledger.row_corrupt.

الخطأ الحقيقي، بعد إخراجه من العميل بطباعة تشخيصية:

    kind=ErrorKind.transient  code=ledger.row_corrupt
    msg=Stored fixture_point_entries row has invalid entry_kind:
        Unknown ledger entry kind: Instance of 'UndecodedBytes'

`UndecodedBytes` هو المفتاح: سائق postgres لا يعرف كيف يفكّ ترميز نوع
ledger.entry_kind عند القراءة (نوع مُعرَّف من المستخدم، ليس ضمن أنواعه
المدمجة)، فيعيد بايتات خامًا. ثم row['entry_kind']?.toString() ينتج
"Instance of 'UndecodedBytes'" ويفشل EntryKind.tryParse.

فالعلّة في القراءة لا الكتابة — ولهذا لم يظهر شيء في سجلّ Northflank:
لا استثناء، بل Result.err نظيف يتحوّل إلى 503 عبر error_envelope.
وهذا أيضًا سبب أن إصلاح 04 (@entry_kind::ledger.entry_kind) كان صحيحًا
للكتابة لكنه لم يحلّ شيئًا: الاتجاه المعاكس بقي مكسورًا.

الحل: entry_kind::text في كل جملة تقرأ العمود — ستّ مواضع، ثلاث في كل
محوّل، بينها RETURNING بعد الإدراج. النصّ يطابق wireValue حرفيًا فلا
تغيير في EntryKind ولا في المخطّط ولا في العقود.
"""
import datetime
import io
import os
import subprocess
import sys

FIXTURE = "packages/infrastructure/lib/src/ledger/postgres_fixture_ledger_repository.dart"
ROUND = "packages/infrastructure/lib/src/ledger/postgres_ledger_repository.dart"

OLD_F = (
    "SELECT id, participant_id, fixture_id, entry_kind, amount, source_ref, "
    "occurred_at"
)
NEW_F = (
    "SELECT id, participant_id, fixture_id, entry_kind::text, amount, "
    "source_ref, occurred_at"
)
OLD_FR = (
    "RETURNING id, participant_id, fixture_id, entry_kind, amount, source_ref, "
    "occurred_at"
)
NEW_FR = (
    "RETURNING id, participant_id, fixture_id, entry_kind::text, amount, "
    "source_ref, occurred_at"
)
OLD_R = (
    "SELECT id, participant_id, round_id, entry_kind, amount, source_ref, "
    "occurred_at"
)
NEW_R = (
    "SELECT id, participant_id, round_id, entry_kind::text, amount, "
    "source_ref, occurred_at"
)
OLD_RR = (
    "RETURNING id, participant_id, round_id, entry_kind, amount, source_ref, "
    "occurred_at"
)
NEW_RR = (
    "RETURNING id, participant_id, round_id, entry_kind::text, amount, "
    "source_ref, occurred_at"
)

LOG = (
    "14_entry_kind_read_cast: «ترحيل إلى السجل» كان يفشل دائمًا بـ503 بلا أي "
    "أثر في سجلّ الخادم؛ الطباعة التشخيصية في العميل أخرجت السبب: "
    "ledger.row_corrupt — «Unknown ledger entry kind: Instance of "
    "UndecodedBytes». سائق postgres لا يفكّ ترميز النوع المُعرَّف "
    "ledger.entry_kind عند القراءة فيعيد بايتات خامًا. أُضيف ::text لكل جملة "
    "تقرأ العمود (ست مواضع، تشمل RETURNING) في محوّلي السجل. لا تغيير في "
    "EntryKind ولا المخطّط ولا العقود — %s + %s" % (FIXTURE, ROUND)
)
MSG = "fix(infra): read entry_kind as text so the driver stops returning raw bytes"


def patch(root, rel, pairs, tag):
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        sys.exit("[!] %s: الملف غير موجود %s" % (tag, rel))
    src = io.open(path, encoding="utf-8").read()
    total = 0
    for old, new in pairs:
        n = src.count(old)
        if n == 0:
            continue
        src = src.replace(old, new)
        total += n
    if total == 0:
        sys.exit("[!] %s: لم تُطابق أي مرساة في %s" % (tag, rel))
    if "entry_kind::text" not in src:
        sys.exit("[!] %s: التحويل لم يُكتب في %s" % (tag, rel))
    io.open(path, "w", encoding="utf-8").write(src)
    print("[ok] patched %s (%d موضعًا)" % (rel, total))


def main():
    root = os.path.abspath(os.environ.get("NUKHBAA_ROOT") or os.getcwd())
    if not os.path.isdir(os.path.join(root, "packages/infrastructure/lib")):
        sys.exit("[!] ليس جذر المشروع: %s — صدّر NUKHBAA_ROOT" % root)
    who = subprocess.run(["whoami"], capture_output=True, text=True).stdout.strip()
    print("[i] user=%s root=%s" % (who, root))

    patch(root, FIXTURE, [(OLD_FR, NEW_FR), (OLD_F, NEW_F)], "14a")
    patch(root, ROUND, [(OLD_RR, NEW_RR), (OLD_R, NEW_R)], "14b")

    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with io.open(
        os.path.join(root, "docs/checkpoints/session-log.md"), "a", encoding="utf-8"
    ) as f:
        f.write("\n%s — %s\n" % (ts, LOG))

    subprocess.run(
        ["git", "add", FIXTURE, ROUND, "docs/checkpoints/session-log.md"],
        cwd=root,
        check=True,
    )
    subprocess.run(["git", "commit", "-m", MSG], cwd=root)
    print("[ok] 14 done")


main()
