#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
إصلاح: إضافة زر/أمر "ترحيل النقاط للسجل" المفقود في لوحة المشرف.
السبب الجذري: ScoreRound يحسب النقاط في scoring.round_scores فقط.
قاعة المشاهير والتصنيف الموسمي يقرآن حصراً من ledger.point_entries،
التي تُملأ فقط عبر PostRoundToLedger (POST /rounds/{id}/ledger) — موجود
وجاهز في السيرفر لكن غير مربوط بأي زر في تطبيق الموبايل.
شغّله من جذر المستودع: python3 fix_post_to_ledger.py
Idempotent: يتحقق من عدم وجود التعديل قبل تطبيقه.
"""
import sys

EDITS = [
    {
        "path": "apps/mobile/lib/l10n/app_ar.arb",
        "old": '  "adminScoreRoundButton": "احتساب الجولة",',
        "new": '  "adminScoreRoundButton": "احتساب الجولة",\n'
               '  "adminPostToLedgerButton": "ترحيل النقاط للسجل",\n'
               '  "adminPostToLedgerSuccessLabel": "تم الترحيل، عدد القيود الجديدة",',
        "marker": '"adminPostToLedgerButton"',
    },
    {
        "path": "apps/mobile/lib/l10n/app_en.arb",
        "old": '  "adminScoreRoundButton": "Score round",',
        "new": '  "adminScoreRoundButton": "Score round",\n'
               '  "adminPostToLedgerButton": "Post to ledger",\n'
               '  "adminPostToLedgerSuccessLabel": "Posted, new entries",',
        "marker": '"adminPostToLedgerButton"',
    },
    {
        "path": "packages/api_client/lib/src/competition_api.dart",
        "old": "  /// `GET /rounds/{id}/scores` — reads every participant's computed score for",
        "new": (
            "  /// `POST /rounds/{id}/ledger` — posts a **scored** round to the\n"
            "  /// append-only Ledger (command intent `PostRoundToLedger`). No request\n"
            "  /// body — the amounts are copied server-side from the round's already-\n"
            "  /// persisted `RoundScore`s (Axioms 2/5). Admin-only, enforced inside the\n"
            "  /// server use-case. A not-yet-scored round is refused\n"
            "  /// `409 ledger.round_not_scored`. Idempotent: re-posting an\n"
            "  /// already-posted round appends nothing new (`appended_entries` empty).\n"
            "  /// This is the Scoring -> Leaderboard seam: the Hall of Fame and season\n"
            "  /// standings read exclusively from the ledger, never from round_scores\n"
            "  /// directly.\n"
            "  Future<Result<PostRoundToLedgerResponseDto>> postRoundToLedger(\n"
            "    String roundId,\n"
            "  ) {\n"
            "    return _transport.postObject<PostRoundToLedgerResponseDto>(\n"
            "      '/rounds/$roundId/ledger',\n"
            "      body: const {},\n"
            "      parse: PostRoundToLedgerResponseDto.fromJson,\n"
            "    );\n"
            "  }\n\n"
            "  /// `GET /rounds/{id}/scores` — reads every participant's computed score for"
        ),
        "marker": "Future<Result<PostRoundToLedgerResponseDto>> postRoundToLedger(",
    },
    {
        "path": "apps/mobile/lib/features/admin/admin_providers.dart",
        "old": "/// Owns the round-scores lookup (`GET /rounds/{id}/scores`, query intent",
        "new": (
            "/// Owns the post-round-to-ledger command (`POST /rounds/{id}/ledger`,\n"
            "/// command intent `PostRoundToLedger`) over `CompetitionApi`. Modelled as a\n"
            "/// controller for the same reason as [ScoreRoundController]. This is the\n"
            "/// required step after [ScoreRoundController] and before a participant's\n"
            "/// points appear in the Hall of Fame / season leaderboard: those read\n"
            "/// exclusively from the ledger, never from round_scores directly.\n"
            "@riverpod\n"
            "class PostRoundToLedgerController extends _$PostRoundToLedgerController {\n"
            "  CompetitionApi get _api => ref.read(competitionApiProvider);\n\n"
            "  @override\n"
            "  AsyncValue<PostRoundToLedgerResponseDto>? build() => null;\n\n"
            "  /// Posts round [roundId]'s already-computed scores to the ledger.\n"
            "  Future<void> post(String roundId) async {\n"
            "    state = const AsyncValue.loading();\n"
            "    final result = await _api.postRoundToLedger(roundId);\n"
            "    state = switch (result) {\n"
            "      Ok<PostRoundToLedgerResponseDto>(:final value) => AsyncValue.data(\n"
            "        value,\n"
            "      ),\n"
            "      Err<PostRoundToLedgerResponseDto>(:final error) => AsyncValue.error(\n"
            "        error,\n"
            "        StackTrace.current,\n"
            "      ),\n"
            "    };\n"
            "  }\n"
            "}\n\n"
            "/// Owns the round-scores lookup (`GET /rounds/{id}/scores`, query intent"
        ),
        "marker": "class PostRoundToLedgerController extends _$PostRoundToLedgerController",
    },
    {
        "path": "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart",
        "old": "  void _lookup() {",
        "new": (
            "  void _postToLedger() {\n"
            "    final r = _roundId;\n"
            "    if (r == null) return;\n"
            "    ref.read(postRoundToLedgerControllerProvider.notifier).post(r);\n"
            "  }\n\n"
            "  void _lookup() {"
        ),
        "marker": "void _postToLedger() {",
    },
    {
        "path": "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart",
        "old": "    final reportInFlight = reportState is AsyncLoading<List<RoundReportRow>>;",
        "new": (
            "    final reportInFlight = reportState is AsyncLoading<List<RoundReportRow>>;\n"
            "    final ledgerPostState = ref.watch(postRoundToLedgerControllerProvider);\n"
            "    final ledgerPostInFlight =\n"
            "        ledgerPostState is AsyncLoading<PostRoundToLedgerResponseDto>;"
        ),
        "marker": "ledgerPostState is AsyncLoading<PostRoundToLedgerResponseDto>",
    },
    {
        "path": "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart",
        "old": (
            "                ],\n"
            "              ),\n"
            "            ],\n"
            "          ),\n"
            "        ),\n"
            "        const SizedBox(height: AppSpacing.md),\n\n"
            "        if (lookupState is AsyncError<RoundScoresDto>)"
        ),
        "new": (
            "                ],\n"
            "              ),\n"
            "              const SizedBox(height: AppSpacing.md),\n"
            "              if (ledgerPostState is AsyncError<PostRoundToLedgerResponseDto>)\n"
            "                AdminErrorBanner(\n"
            "                  message: ErrorPresenter.message(\n"
            "                    ledgerPostState.error as AppError,\n"
            "                  ),\n"
            "                ),\n"
            "              if (ledgerPostState is AsyncData<PostRoundToLedgerResponseDto>)\n"
            "                AdminSuccessBanner(\n"
            "                  message:\n"
            "                      '${l10n.adminPostToLedgerSuccessLabel}: '\n"
            "                      '${ledgerPostState.value.appendedEntries.length}',\n"
            "                ),\n"
            "              if (ledgerPostState is AsyncError<PostRoundToLedgerResponseDto> ||\n"
            "                  ledgerPostState is AsyncData<PostRoundToLedgerResponseDto>)\n"
            "                const SizedBox(height: AppSpacing.sm),\n"
            "              AdminSecondaryButton(\n"
            "                key: const Key('admin.results.postToLedger'),\n"
            "                label: l10n.adminPostToLedgerButton,\n"
            "                icon: Icons.receipt_long_rounded,\n"
            "                loading: ledgerPostInFlight,\n"
            "                onPressed: (ledgerPostInFlight || _roundId == null)\n"
            "                    ? null\n"
            "                    : _postToLedger,\n"
            "              ),\n"
            "            ],\n"
            "          ),\n"
            "        ),\n"
            "        const SizedBox(height: AppSpacing.md),\n\n"
            "        if (lookupState is AsyncError<RoundScoresDto>)"
        ),
        "marker": "admin.results.postToLedger",
    },
]


def apply_edit(edit):
    path = edit["path"]
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"[تخطي] الملف غير موجود: {path}")
        return False

    if edit["marker"] in content:
        print(f"[تم مسبقًا] {path}")
        return True

    if edit["old"] not in content:
        print(f"[!!] لم يتم إيجاد النص المطلوب في {path} — راجع الملف يدويًا")
        return False

    content = content.replace(edit["old"], edit["new"], 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[تم التعديل] {path}")
    return True


def main():
    ok = True
    for edit in EDITS:
        if not apply_edit(edit):
            ok = False
    print()
    if ok:
        print("تم تطبيق كل التعديلات. الخطوات التالية (نفّذها الآن):")
        print("  1) cd apps/mobile && flutter gen-l10n && cd ../..")
        print("  2) cd apps/mobile && flutter pub run build_runner build --delete-conflicting-outputs && cd ../..")
        print("  3) dart format . && flutter analyze && melos test")
    else:
        print("بعض التعديلات لم تُطبّق — راجع الرسائل أعلاه قبل المتابعة.")
        sys.exit(1)


if __name__ == "__main__":
    main()
