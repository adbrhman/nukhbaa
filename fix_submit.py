import re

path = "apps/mobile/lib/features/prediction/prediction_screen.dart"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

old_open = "    return ListView(\n      key: const Key('prediction.form'),\n      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),\n      children: <Widget>[\n"
new_open = (
    "    return Column(\n"
    "      children: <Widget>[\n"
    "        Expanded(\n"
    "          child: ListView(\n"
    "            key: const Key('prediction.form'),\n"
    "            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),\n"
    "            children: <Widget>[\n"
)
assert src.count(old_open) == 1, "open marker not found or not unique: %d" % src.count(old_open)
src = src.replace(old_open, new_open)

old_tail = (
    "        const SizedBox(height: 12),\n"
    "        _SubmitButton(\n"
    "          inFlight: inFlight,\n"
    "          onSubmit: scores == null\n"
    "              ? null\n"
    "              : () => ref\n"
    "                    .read(predictionControllerProvider(widget.roundId).notifier)\n"
    "                    .submit(scores),\n"
    "        ),\n"
    "      ],\n"
    "    );\n"
    "  }\n"
    "}\n"
)
new_tail = (
    "            ],\n"
    "          ),\n"
    "        ),\n"
    "        SafeArea(\n"
    "          top: false,\n"
    "          child: Padding(\n"
    "            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),\n"
    "            child: _SubmitButton(\n"
    "              inFlight: inFlight,\n"
    "              onSubmit: scores == null\n"
    "                  ? null\n"
    "                  : () => ref\n"
    "                        .read(predictionControllerProvider(widget.roundId).notifier)\n"
    "                        .submit(scores),\n"
    "            ),\n"
    "          ),\n"
    "        ),\n"
    "      ],\n"
    "    );\n"
    "  }\n"
    "}\n"
)
assert src.count(old_tail) == 1, "tail marker not found or not unique: %d" % src.count(old_tail)
src = src.replace(old_tail, new_tail)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("OK")
