#!/usr/bin/env python3
"""step5 — البند (7): ربط api_client بـ BrowseRoundFixtures.

يحوّل CompetitionApi.listRoundFixtures (-> List<RoundFixtureDto>) إلى
CompetitionApi.browseRoundFixtures (-> List<RoundFixtureCardDto>)، ويحدّث كل
الاستهلاك التابع في apps/mobile (provider + شاشتي البراوز والتوقعات) وملفات
الاختبار (api_client + mobile harnesses)، بدون أي تعديل على منطق القفل/الدبل
بالواجهة (مؤجَّل للبند 8 — الحقول الجديدة homeTeam/awayTeam/kickoffAt غير
مستخدمة بعد بالعرض، فقط بالـ DTO/fixtures).

كل تعديل هو str.replace على تطابق حرفي واحد بالضبط؛ أي عدم تطابق يوقف
السكربت بخطأ صريح قبل كتابة أي شيء لذلك الملف (لا كتابة صامتة/جزئية).
"""

import sys

EDITS = {
    # -------------------------------------------------------------------
    # 1) api_client: العميل الفعلي
    # -------------------------------------------------------------------
    "packages/api_client/lib/src/competition_api.dart": [
        (
            "///   * `GET /rounds/{id}/fixtures`       -> `List<RoundFixtureDto>`\n"
            "///     (`routes/rounds/[id]/fixtures/index.dart` GET branch, display order;\n"
            "///     an absent round is a legitimate empty array — no existence oracle)\n",
            "///   * `GET /rounds/{id}/fixtures`       -> `List<RoundFixtureCardDto>`\n"
            "///     (`routes/rounds/[id]/fixtures/index.dart` GET branch, display order,\n"
            "///     each card enriched with its schedule identity — team names + kickoff,\n"
            "///     all nullable since the round<->fixture link never verifies a schedule\n"
            "///     exists, Axiom 3; query intent `BrowseRoundFixtures`, Session decision\n"
            "///     2026-08-07 widened this read instead of a new endpoint; an absent round\n"
            "///     is a legitimate empty array — no existence oracle)\n",
        ),
        (
            "  /// `GET /rounds/{id}/fixtures` — the round's fixtures in display order.\n"
            "  ///\n"
            "  /// A round with no linked fixtures — or one that does not exist — is a\n"
            "  /// legitimate `Ok(<empty list>)` (the server reveals no existence oracle on\n"
            "  /// this browse read).\n"
            "  Future<Result<List<RoundFixtureDto>>> listRoundFixtures(String roundId) {\n"
            "    return _transport.getList<RoundFixtureDto>(\n"
            "      '/rounds/$roundId/fixtures',\n"
            "      parseElement: RoundFixtureDto.fromJson,\n"
            "    );\n"
            "  }\n",
            "  /// `GET /rounds/{id}/fixtures` — the round's fixtures in display order,\n"
            "  /// each enriched with its schedule identity (team names + kickoff) for the\n"
            "  /// prediction-form render (query intent `BrowseRoundFixtures`; Session\n"
            "  /// decision 2026-08-07 widened this read instead of a new per-fixture\n"
            "  /// endpoint — batched, no N+1).\n"
            "  ///\n"
            "  /// A round with no linked fixtures — or one that does not exist — is a\n"
            "  /// legitimate `Ok(<empty list>)` (the server reveals no existence oracle on\n"
            "  /// this browse read). `homeTeam`/`awayTeam`/`kickoffAt` are `null` when the\n"
            "  /// linked fixture has no schedule yet (the link never verifies one exists —\n"
            "  /// Axiom 3).\n"
            "  Future<Result<List<RoundFixtureCardDto>>> browseRoundFixtures(\n"
            "    String roundId,\n"
            "  ) {\n"
            "    return _transport.getList<RoundFixtureCardDto>(\n"
            "      '/rounds/$roundId/fixtures',\n"
            "      parseElement: RoundFixtureCardDto.fromJson,\n"
            "    );\n"
            "  }\n",
        ),
    ],
    # -------------------------------------------------------------------
    # 2) api_client: اختبارات العميل
    # -------------------------------------------------------------------
    "packages/api_client/test/competition_api_test.dart": [
        (
            "  group('CompetitionApi.listRoundFixtures (GET /rounds/{id}/fixtures)', () {\n"
            "    test('200 -> Ok(List<RoundFixtureDto>) at the fixtures path', () async {\n"
            "      const f0 = RoundFixtureDto(\n"
            "        roundId: 'r',\n"
            "        fixtureId: 'f-a',\n"
            "        displayOrder: 0,\n"
            "      );\n"
            "      const f1 = RoundFixtureDto(\n"
            "        roundId: 'r',\n"
            "        fixtureId: 'f-b',\n"
            "        displayOrder: 1,\n"
            "      );\n"
            "      final ctx = buildTransport(\n"
            "        (_) async => okJson([f0.toJson(), f1.toJson()]),\n"
            "      );\n"
            "\n"
            "      final result = await CompetitionApi(ctx.transport).listRoundFixtures('r');\n"
            "\n"
            "      expect(result, const Result<List<RoundFixtureDto>>.ok([f0, f1]));\n"
            "      expect(ctx.captured.single.url.path, '/rounds/r/fixtures');\n"
            "    });\n"
            "\n"
            "    test('an absent round is a legitimate empty array (no oracle)', () async {\n"
            "      final ctx = buildTransport((_) async => okJson(<Object>[]));\n"
            "\n"
            "      final result = await CompetitionApi(\n"
            "        ctx.transport,\n"
            "      ).listRoundFixtures('gone');\n"
            "\n"
            "      expect((result as Ok<List<RoundFixtureDto>>).value, isEmpty);\n"
            "    });\n"
            "\n"
            "    test('503 -> Err(transient) retryable', () async {\n"
            "      final ctx = buildTransport(\n"
            "        (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),\n"
            "      );\n"
            "\n"
            "      final result = await CompetitionApi(ctx.transport).listRoundFixtures('r');\n"
            "\n"
            "      expect((result as Err<List<RoundFixtureDto>>).error.isRetryable, isTrue);\n"
            "    });\n"
            "  });\n",
            "  group('CompetitionApi.browseRoundFixtures (GET /rounds/{id}/fixtures)', () {\n"
            "    test(\n"
            "      '200 -> Ok(List<RoundFixtureCardDto>) at the fixtures path',\n"
            "      () async {\n"
            "        const f0 = RoundFixtureCardDto(\n"
            "          roundId: 'r',\n"
            "          fixtureId: 'f-a',\n"
            "          displayOrder: 0,\n"
            "          homeTeam: 'Al Hilal',\n"
            "          awayTeam: 'Al Nassr',\n"
            "          kickoffAt: '2026-08-15T18:00:00.000Z',\n"
            "        );\n"
            "        const f1 = RoundFixtureCardDto(\n"
            "          roundId: 'r',\n"
            "          fixtureId: 'f-b',\n"
            "          displayOrder: 1,\n"
            "          homeTeam: null,\n"
            "          awayTeam: null,\n"
            "          kickoffAt: null,\n"
            "        );\n"
            "        final ctx = buildTransport(\n"
            "          (_) async => okJson([f0.toJson(), f1.toJson()]),\n"
            "        );\n"
            "\n"
            "        final result = await CompetitionApi(\n"
            "          ctx.transport,\n"
            "        ).browseRoundFixtures('r');\n"
            "\n"
            "        expect(result, const Result<List<RoundFixtureCardDto>>.ok([f0, f1]));\n"
            "        expect(ctx.captured.single.url.path, '/rounds/r/fixtures');\n"
            "      },\n"
            "    );\n"
            "\n"
            "    test('an absent round is a legitimate empty array (no oracle)', () async {\n"
            "      final ctx = buildTransport((_) async => okJson(<Object>[]));\n"
            "\n"
            "      final result = await CompetitionApi(\n"
            "        ctx.transport,\n"
            "      ).browseRoundFixtures('gone');\n"
            "\n"
            "      expect((result as Ok<List<RoundFixtureCardDto>>).value, isEmpty);\n"
            "    });\n"
            "\n"
            "    test('503 -> Err(transient) retryable', () async {\n"
            "      final ctx = buildTransport(\n"
            "        (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),\n"
            "      );\n"
            "\n"
            "      final result = await CompetitionApi(\n"
            "        ctx.transport,\n"
            "      ).browseRoundFixtures('r');\n"
            "\n"
            "      expect(\n"
            "        (result as Err<List<RoundFixtureCardDto>>).error.isRetryable,\n"
            "        isTrue,\n"
            "      );\n"
            "    });\n"
            "  });\n",
        ),
    ],
    # -------------------------------------------------------------------
    # 3) apps/mobile: provider (competition_providers.dart)
    # -------------------------------------------------------------------
    "apps/mobile/lib/features/competition/competition_providers.dart": [
        (
            "/// `GET /rounds/{id}/fixtures` — the round's fixtures (display order).\n"
            "///\n"
            "/// The final hop. A round with no linked fixtures — or one that does not exist —\n"
            "/// resolves to a legitimate empty list (no existence oracle).\n"
            "@riverpod\n"
            "Future<List<RoundFixtureDto>> roundFixtures(Ref ref, String roundId) async {\n"
            "  final api = ref.watch(competitionApiProvider);\n"
            "  return _unwrap(await api.listRoundFixtures(roundId));\n"
            "}\n",
            "/// `GET /rounds/{id}/fixtures` — the round's fixtures (display order), each\n"
            "/// enriched with its schedule identity (team names + kickoff; `null` when the\n"
            "/// linked fixture has no schedule yet, Axiom 3).\n"
            "///\n"
            "/// The final hop. A round with no linked fixtures — or one that does not exist —\n"
            "/// resolves to a legitimate empty list (no existence oracle).\n"
            "@riverpod\n"
            "Future<List<RoundFixtureCardDto>> roundFixtures(\n"
            "  Ref ref,\n"
            "  String roundId,\n"
            ") async {\n"
            "  final api = ref.watch(competitionApiProvider);\n"
            "  return _unwrap(await api.browseRoundFixtures(roundId));\n"
            "}\n",
        ),
    ],
    # -------------------------------------------------------------------
    # 4) apps/mobile: شاشة البراوز (round_fixtures_screen.dart)
    # -------------------------------------------------------------------
    "apps/mobile/lib/features/competition/round_fixtures_screen.dart": [
        (
            "            child: AsyncListView<RoundFixtureDto>(\n",
            "            child: AsyncListView<RoundFixtureCardDto>(\n",
        ),
    ],
    # -------------------------------------------------------------------
    # 5) apps/mobile: شاشة التوقعات (prediction_screen.dart)
    # -------------------------------------------------------------------
    "apps/mobile/lib/features/prediction/prediction_screen.dart": [
        (
            "  const _PredictionEditor({required this.roundId, required this.fixtures});\n"
            "\n"
            "  final String roundId;\n"
            "  final List<RoundFixtureDto> fixtures;\n",
            "  const _PredictionEditor({required this.roundId, required this.fixtures});\n"
            "\n"
            "  final String roundId;\n"
            "  final List<RoundFixtureCardDto> fixtures;\n",
        ),
        (
            "  final RoundFixtureDto fixture;\n"
            "  final TextEditingController homeController;\n",
            "  final RoundFixtureCardDto fixture;\n"
            "  final TextEditingController homeController;\n",
        ),
    ],
    # -------------------------------------------------------------------
    # 6) apps/mobile: test harness — البراوز (competition_harness.dart)
    # -------------------------------------------------------------------
    "apps/mobile/test/support/competition_harness.dart": [
        (
            "/// A sample fixture link of [sampleRound].\n"
            "const RoundFixtureDto sampleFixture = RoundFixtureDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-1',\n"
            "  displayOrder: 0,\n"
            ");\n",
            "/// A sample fixture link of [sampleRound].\n"
            "const RoundFixtureCardDto sampleFixture = RoundFixtureCardDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-1',\n"
            "  displayOrder: 0,\n"
            "  homeTeam: 'Al Hilal',\n"
            "  awayTeam: 'Al Nassr',\n"
            "  kickoffAt: '2026-08-15T18:00:00.000Z',\n"
            ");\n",
        ),
    ],
    # -------------------------------------------------------------------
    # 7) apps/mobile: test harness — التوقعات (prediction_harness.dart)
    # -------------------------------------------------------------------
    "apps/mobile/test/support/prediction_harness.dart": [
        (
            "/// Two fixtures of [openRound], in display order.\n"
            "const RoundFixtureDto fixtureA = RoundFixtureDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-a',\n"
            "  displayOrder: 0,\n"
            ");\n"
            "\n"
            "/// The second fixture of [openRound].\n"
            "const RoundFixtureDto fixtureB = RoundFixtureDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-b',\n"
            "  displayOrder: 1,\n"
            ");\n",
            "/// Two fixtures of [openRound], in display order.\n"
            "const RoundFixtureCardDto fixtureA = RoundFixtureCardDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-a',\n"
            "  displayOrder: 0,\n"
            "  homeTeam: 'Al Hilal',\n"
            "  awayTeam: 'Al Nassr',\n"
            "  kickoffAt: '2026-08-15T18:00:00.000Z',\n"
            ");\n"
            "\n"
            "/// The second fixture of [openRound].\n"
            "const RoundFixtureCardDto fixtureB = RoundFixtureCardDto(\n"
            "  roundId: 'r-1',\n"
            "  fixtureId: 'f-b',\n"
            "  displayOrder: 1,\n"
            "  homeTeam: null,\n"
            "  awayTeam: null,\n"
            "  kickoffAt: null,\n"
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

    print("OK: كل الملفات (7) عُدِّلت بنجاح.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
