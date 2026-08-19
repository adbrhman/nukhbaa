#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
\u0625\u0636\u0627\u0641\u0629: \u0646\u0634\u0631 \u0623\u062d\u062f\u062b APK \u062a\u0644\u0642\u0627\u0626\u064a\u0627\u064b \u0643\u0640 GitHub Release \u062b\u0627\u0628\u062a \u0628\u0627\u0633\u0645 "latest"
\u0628\u0639\u062f \u0646\u062c\u0627\u062d build_android \u0641\u064a build-verification.yml (push \u0639\u0644\u0649 main \u0641\u0642\u0637).
\u0631\u0627\u0628\u0637 \u062a\u062d\u0645\u064a\u0644 \u062b\u0627\u0628\u062a:
https://github.com/adbrhman/nukhbaa/releases/download/latest/nukhbaa.apk
\u0634\u063a\u0651\u0644\u0647 \u0645\u0646 \u062c\u0630\u0631 \u0627\u0644\u0645\u0633\u062a\u0648\u062f\u0639: python3 fix_publish_apk.py
Idempotent: \u064a\u062a\u062d\u0642\u0642 \u0645\u0646 \u0639\u062f\u0645 \u0648\u062c\u0648\u062f \u0627\u0644\u062a\u0639\u062f\u064a\u0644 \u0642\u0628\u0644 \u062a\u0637\u0628\u064a\u0642\u0647.
"""
import sys

EDITS = [
    {
        "path": ".github/workflows/build-verification.yml",
        "old": (
            "      - uses: actions/upload-artifact@v4\n"
            "        with:\n"
            "          name: nukhba-android-apk\n"
            "          path: apps/mobile/build/app/outputs/flutter-apk/*.apk\n"
            "          retention-days: 14\n"
            "\n"
            "  build_server_image:\n"
        ),
        "new": (
            "      - uses: actions/upload-artifact@v4\n"
            "        with:\n"
            "          name: nukhba-android-apk\n"
            "          path: apps/mobile/build/app/outputs/flutter-apk/*.apk\n"
            "          retention-days: 14\n"
            "\n"
            "  publish_latest_apk:\n"
            "    name: Publish latest APK to Release\n"
            "    runs-on: ubuntu-latest\n"
            "    needs: build_android\n"
            "    if: github.ref == 'refs/heads/main' && github.event_name == 'push'\n"
            "    permissions:\n"
            "      contents: write\n"
            "    steps:\n"
            "      - uses: actions/download-artifact@v4\n"
            "        with:\n"
            "          name: nukhba-android-apk\n"
            "          path: apk\n"
            "\n"
            "      - name: Rename to a stable filename\n"
            "        run: mv apk/*.apk apk/nukhbaa.apk\n"
            "\n"
            "      - name: Publish/update the 'latest' release\n"
            "        uses: softprops/action-gh-release@v2\n"
            "        with:\n"
            "          tag_name: latest\n"
            "          name: Latest build\n"
            "          body: |\n"
            "            \u0628\u0646\u0627\u0621 \u062a\u0644\u0642\u0627\u0626\u064a \u0645\u0646 commit ${{ github.sha }}\n"
            "            \u0631\u0627\u0628\u0637 \u062b\u0627\u0628\u062a \u0644\u0644\u062a\u062d\u0645\u064a\u0644 \u062f\u0627\u0626\u0645\u0627\u064b:\n"
            "            https://github.com/${{ github.repository }}/releases/download/latest/nukhbaa.apk\n"
            "          make_latest: true\n"
            "          files: apk/nukhbaa.apk\n"
            "        env:\n"
            "          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n"
            "\n"
            "  build_server_image:\n"
        ),
        "marker": "publish_latest_apk:",
    },
]


def apply_edit(edit):
    path = edit["path"]
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"[\u062a\u062e\u0637\u064a] \u0627\u0644\u0645\u0644\u0641 \u063a\u064a\u0631 \u0645\u0648\u062c\u0648\u062f: {path}")
        return False

    if edit["marker"] in content:
        print(f"[\u062a\u0645 \u0645\u0633\u0628\u0642\u064b\u0627] {path}")
        return True

    if edit["old"] not in content:
        print(f"[!!] \u0644\u0645 \u064a\u062a\u0645 \u0625\u064a\u062c\u0627\u062f \u0627\u0644\u0646\u0635 \u0627\u0644\u0645\u0637\u0644\u0648\u0628 \u0641\u064a {path} \u2014 \u0631\u0627\u062c\u0639 \u0627\u0644\u0645\u0644\u0641 \u064a\u062f\u0648\u064a\u064b\u0627")
        return False

    content = content.replace(edit["old"], edit["new"], 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[\u062a\u0645 \u0627\u0644\u062a\u0639\u062f\u064a\u0644] {path}")
    return True


def main():
    ok = True
    for edit in EDITS:
        if not apply_edit(edit):
            ok = False
    print()
    if ok:
        print("\u062a\u0645 \u062a\u0637\u0628\u064a\u0642 \u0627\u0644\u062a\u0639\u062f\u064a\u0644. \u0644\u0627 \u062d\u0627\u062c\u0629 \u0644\u0640 flutter gen-l10n \u0623\u0648 build_runner \u0647\u0646\u0627 \u2014")
        print("\u0647\u0630\u0627 \u0645\u0644\u0641 CI \u0641\u0642\u0637. \u0627\u0644\u062e\u0637\u0648\u0629 \u0627\u0644\u062a\u0627\u0644\u064a\u0629:")
        print("  git add -A && git commit -m 'ci: publish latest APK as a GitHub Release' && git push origin main")
    else:
        print("\u0628\u0639\u0636 \u0627\u0644\u062a\u0639\u062f\u064a\u0644\u0627\u062a \u0644\u0645 \u062a\u064f\u0637\u0628\u0651\u0642 \u2014 \u0631\u0627\u062c\u0639 \u0627\u0644\u0631\u0633\u0627\u0626\u0644 \u0623\u0639\u0644\u0627\u0647 \u0642\u0628\u0644 \u0627\u0644\u0645\u062a\u0627\u0628\u0639\u0629.")
        sys.exit(1)


if __name__ == "__main__":
    main()
