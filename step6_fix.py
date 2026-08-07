#!/usr/bin/env python3
"""step6_fix — يصحّح فقط جزئي step6.py اللي فشلا (XX) بسبب RoundFixtureDto
بدل RoundFixtureCardDto الفعلي (بعد BrowseRoundFixtures). الأجزاء اللي نجحت
بالفعل بالملفين (OK بالطرفية) لا تُلمس هنا.

يعدّل:
  1) apps/mobile/lib/features/prediction/prediction_screen.dart
     (كلاس _FixtureScoreInput: fixture type فقط)
  2) apps/mobile/test/support/prediction_harness.dart
     (fixtureB: fixture type + الحقول الناقصة، + إضافة fixtureLocked)
"""

import sys

EDITS = {
    "apps/mobile/lib/features/prediction/prediction_screen.dart": [
        (
            "/// One fixture's home/away goal inputs.\n"
            "class _FixtureScoreInput extends StatelessWidget {\n"
            "  const _FixtureScoreInput({\n"
            "    required this.fixture,\n"
            "    required this.homeController,\n"
            "    required this.awayController,\n"
            "    required this.enabled,\n"
            "    required this.onChanged,\n"
            "    super.key,\n"
            "  });\n"
            "\n"
            "  final RoundFixtureCardDto fixture;\n"
            "  final TextEditingController homeController;\n"
            "  final TextEditingController awayController;\n"
            "  final bool enabled;\n"
            "  final VoidCallback onChanged;\n"
            "\n"
            "  @override\n"
            "  Widget build(BuildContext context) {\n"
            "    final l10n = AppLocalizations.of(context);\n"
            "    return Padding(\n"
            "      padding: const EdgeInsets.symmetric(vertical: 8),\n"
            "      child: Row(\n"
            "        children: <Widget>[\n"
            "          CircleAvatar(child: Text('${fixture.displayOrder + 1}')),\n"
            "          const SizedBox(width: 12),\n"
            "          Expanded(\n"
            "            child: Text(\n"
            "              l10n.fixtureItemTitle(fixture.fixtureId),\n"
            "              overflow: TextOverflow.ellipsis,\n"
            "            ),\n"
            "          ),\n"
            "          const SizedBox(width: 12),\n"
            "          _GoalField(\n"
            "            key: Key('prediction.home.${fixture.fixtureId}'),\n"
            "            controller: homeController,\n"
            "            enabled: enabled,\n"
            "            onChanged: onChanged,\n"
            "          ),\n"
            "          const Padding(\n"
            "            padding: EdgeInsets.symmetric(horizontal: 8),\n"
            "            child: Text('-'),\n"
            "          ),\n"
            "          _GoalField(\n"
            "            key: Key('prediction.away.${fixture.fixtureId}'),\n"
            "            controller: awayController,\n"
            "            enabled: enabled,\n"
            "            onChanged: onChanged,\n"
            "          ),\n"
            "        ],\n"
            "      ),\n"
            "    );\n"
            "  }\n"
            "}\n",
            "/// One fixture's home/away goal inputs, plus (for an open fixture) the\n"
            "/// double-selection star.\n"
            "class _FixtureScoreInput extends StatelessWidget {\n"
            "  const _FixtureScoreInput({\n"
            "    required this.fixture,\n"
            "    required this.locked,\n"
            "    required this.homeController,\n"
            "    required this.awayController,\n"
            "    required this.enabled,\n"
            "    required this.isDouble,\n"
            "    required this.doubleSelectable,\n"
            "    required this.onDoubleSelected,\n"
            "    required this.onChanged,\n"
            "    super.key,\n"
            "  });\n"
            "\n"
            "  final RoundFixtureCardDto fixture;\n"
            "\n"
            "  /// Whether this fixture has already kicked off — its score inputs render\n"
            "  /// disabled and it never gets a tappable double star.\n"
            "  final bool locked;\n"
            "  final TextEditingController homeController;\n"
            "  final TextEditingController awayController;\n"
            "  final bool enabled;\n"
            "\n"
            "  /// Whether this fixture is currently the caller's double (open selection\n"
            "  /// or an already-locked one carried over).\n"
            "  final bool isDouble;\n"
            "\n"
            "  /// Whether the double star is tappable for this fixture (open, not locked,\n"
            "  /// no submit in flight, and no already-locked fixture holds the double).\n"
            "  final bool doubleSelectable;\n"
            "  final VoidCallback onDoubleSelected;\n"
            "  final VoidCallback onChanged;\n"
            "\n"
            "  @override\n"
            "  Widget build(BuildContext context) {\n"
            "    final l10n = AppLocalizations.of(context);\n"
            "    final home = fixture.homeTeam;\n"
            "    final away = fixture.awayTeam;\n"
            "    final title = home != null && away != null\n"
            "        ? l10n.fixtureVsTitle(home, away)\n"
            "        : l10n.fixtureItemTitle(fixture.fixtureId);\n"
            "    return Padding(\n"
            "      padding: const EdgeInsets.symmetric(vertical: 8),\n"
            "      child: Row(\n"
            "        children: <Widget>[\n"
            "          IconButton(\n"
            "            key: Key('prediction.double.${fixture.fixtureId}'),\n"
            "            icon: Icon(isDouble ? Icons.star : Icons.star_border),\n"
            "            tooltip: l10n.predictionDoubleLabel,\n"
            "            color: isDouble\n"
            "                ? Theme.of(context).colorScheme.primary\n"
            "                : Theme.of(context).colorScheme.outline,\n"
            "            onPressed: doubleSelectable ? onDoubleSelected : null,\n"
            "          ),\n"
            "          Expanded(\n"
            "            child: Column(\n"
            "              crossAxisAlignment: CrossAxisAlignment.start,\n"
            "              children: <Widget>[\n"
            "                Text(title, overflow: TextOverflow.ellipsis),\n"
            "                if (locked)\n"
            "                  Text(\n"
            "                    l10n.predictionFixtureLockedLabel,\n"
            "                    key: Key('prediction.locked.${fixture.fixtureId}'),\n"
            "                    style: TextStyle(\n"
            "                      fontSize: 12,\n"
            "                      color: Theme.of(context).colorScheme.outline,\n"
            "                    ),\n"
            "                  ),\n"
            "              ],\n"
            "            ),\n"
            "          ),\n"
            "          const SizedBox(width: 12),\n"
            "          _GoalField(\n"
            "            key: Key('prediction.home.${fixture.fixtureId}'),\n"
            "            controller: homeController,\n"
            "            enabled: enabled && !locked,\n"
            "            onChanged: onChanged,\n"
            "          ),\n"
            "          const Padding(\n"
            "            padding: EdgeInsets.symmetric(horizontal: 8),\n"
            "            child: Text('-'),\n"
            "          ),\n"
            "          _GoalField(\n"
            "            key: Key('prediction.away.${fixture.fixtureId}'),\n"
            "            controller: awayController,\n"
            "            enabled: enabled && !locked,\n"
            "            onChanged: onChanged,\n"
            "          ),\n"
            "        ],\n"
            "      ),\n"
            "    );\n"
            "  }\n"
            "}\n",
        ),
    ],
    "apps/mobile/test/support/prediction_harness.dart": [
        (
            "/// The second fixture of [openRound].\n"
            "const RoundFixtureCardDto fixtureB = RoundFixtureCardDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-b',\n"
            "  displayOrder: 1,\n"
            "  homeTeam: null,\n"
            "  awayTeam: null,\n"
            "  kickoffAt: null,\n"
            ");\n",
            "/// The second fixture of [openRound].\n"
            "const RoundFixtureCardDto fixtureB = RoundFixtureCardDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-b',\n"
            "  displayOrder: 1,\n"
            "  homeTeam: null,\n"
            "  awayTeam: null,\n"
            "  kickoffAt: null,\n"
            ");\n"
            "\n"
            "/// A third fixture of [openRound] that has already kicked off (a fixed date\n"
            "/// safely in the past): exercises the per-fixture lock — disabled score\n"
            "/// inputs, no tappable double star.\n"
            "const RoundFixtureCardDto fixtureLocked = RoundFixtureCardDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-locked',\n"
            "  displayOrder: 2,\n"
            "  homeTeam: 'Al Ahly',\n"
            "  awayTeam: 'Zamalek',\n"
            "  kickoffAt: '2020-01-01T00:00:00.000Z',\n"
            ");\n",
        ),
    ],
}


def main() -> int:
    failures = []
    for path, replacements in EDITS.items():
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
        except FileNotFoundError:
            failures.append(f"XX: الملف غير موجود: {path}")
            continue

        original = content
        for old, new in replacements:
            count = content.count(old)
            if count != 1:
                failures.append(
                    f"XX: {path}: تطابق={count} (متوقع 1) لهذا المقطع:\n"
                    f"{old[:120]!r}..."
                )
                continue
            content = content.replace(old, new)

        if content == original:
            continue

        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"OK: {path}")

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1

    print("OK: كل الملفات (2) عُدِّلت بنجاح.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
