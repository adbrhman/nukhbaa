#!/usr/bin/env python3
"""20_predictions_display_name.

display_name in the admin raw-predictions read.
Same shape as ParticipantFixtureScoreDto: optional field, default '',
joined at the route via AdminGetParticipantDisplayNames. No new deps,
no schema change, no new use-case.
"""
import subprocess
import sys
from pathlib import Path

DRY = "--dry" in sys.argv

ROOT = Path.home() / "nukhbaa-backup-1787537565"
assert ROOT.is_dir(), f"missing project root: {ROOT}"


def patch(rel, pairs):
    p = ROOT / rel
    assert p.is_file(), f"missing file: {p}"
    src = p.read_text(encoding="utf-8")
    for i, (old, new) in enumerate(pairs):
        n = src.count(old)
        assert n == 1, f"{rel}: anchor #{i} matched {n} times"
        src = src.replace(old, new)
    p.write_text(src, encoding="utf-8")
    print(f"ok {rel}")


# ---------------------------------------------------------------- contracts
patch(
    "packages/contracts/lib/src/fixture_prediction_dto.dart",
    [
        (
            """    this.isDouble = false,
    this.seasonId,
    this.schemaVersion = currentSchemaVersion,
  });""",
            """    this.isDouble = false,
    this.seasonId,
    this.displayName = '',
    this.schemaVersion = currentSchemaVersion,
  });""",
        ),
        (
            """      seasonId: json['season_id'] as String?,
    );""",
            """      seasonId: json['season_id'] as String?,
      displayName: (json['display_name'] as String?) ?? '',
    );""",
        ),
        (
            """  final String? seasonId;

  /// The schema version of this payload.""",
            """  final String? seasonId;

  /// The participant's display name, joined server-side on the admin
  /// raw-predictions read only (the same optional-join shape as
  /// `ParticipantFixtureScoreDto.displayName`). Empty when unavailable, and
  /// then omitted from the wire payload — so a decoder that never saw the
  /// field keeps decoding unchanged.
  final String displayName;

  /// The schema version of this payload.""",
        ),
        (
            """    if (seasonId != null) 'season_id': seasonId,
  };""",
            """    if (seasonId != null) 'season_id': seasonId,
    if (displayName.isNotEmpty) 'display_name': displayName,
  };""",
        ),
        (
            """      other.seasonId == seasonId &&
      other.schemaVersion == schemaVersion;""",
            """      other.seasonId == seasonId &&
      other.displayName == displayName &&
      other.schemaVersion == schemaVersion;""",
        ),
        (
            """    isDouble,
    seasonId,
    schemaVersion,
  );""",
            """    isDouble,
    seasonId,
    displayName,
    schemaVersion,
  );""",
        ),
    ],
)

# ------------------------------------------------------------------- mapper
patch(
    "apps/server/lib/http/fixture_prediction_dto_mapper.dart",
    [
        (
            """Map<String, Object?> fixturePredictionViewToJson(FixturePredictionView view) {
  final prediction = view.prediction;""",
            """Map<String, Object?> fixturePredictionViewToJson(
  FixturePredictionView view, {
  String displayName = '',
}) {
  final prediction = view.prediction;""",
        ),
        (
            """    seasonId: view.seasonId?.value,
  ).toJson();""",
            """    seasonId: view.seasonId?.value,
    displayName: displayName,
  ).toJson();""",
        ),
    ],
)

# -------------------------------------------------------------------- route
patch(
    "apps/server/routes/admin/fixtures/[id]/predictions/index.dart",
    [
        (
            """  return switch (result) {
    Ok<List<FixturePredictionView>>(:final value) => Response.json(
      body: [for (final view in value) fixturePredictionViewToJson(view)],
    ),
    Err<List<FixturePredictionView>>(:final error) => errorResponse(error),
  };
}""",
            """  return switch (result) {
    Ok<List<FixturePredictionView>>(:final value) => await _withDisplayNames(
      root,
      principal,
      value,
    ),
    Err<List<FixturePredictionView>>(:final error) => errorResponse(error),
  };
}

/// Joins each participant's display name onto the raw-predictions payload —
/// the same optional enrichment `GET /admin/fixtures/{id}/scores` performs,
/// via the same admin-gated `AdminGetParticipantDisplayNames`. A failed or
/// unwired name lookup degrades to no names (the field is then omitted from
/// the wire shape), never to an error: the predictions read is the primary
/// value here and must not fail on a cosmetic join.
Future<Response> _withDisplayNames(
  CompositionRoot root,
  AuthenticatedUser principal,
  List<FixturePredictionView> views,
) async {
  final namesResult = await root.adminGetParticipantDisplayNames(
    principal: principal,
    participantIds: [
      for (final view in views) view.prediction.participantId.value,
    ],
  );
  final names = namesResult is Ok<Map<String, String>>
      ? namesResult.value
      : const <String, String>{};
  return Response.json(
    body: [
      for (final view in views)
        fixturePredictionViewToJson(
          view,
          displayName: names[view.prediction.participantId.value] ?? '',
        ),
    ],
  );
}""",
        )
    ],
)

# ------------------------------------------------------------------- mobile
patch(
    "apps/mobile/lib/features/admin/screens/sections/admin_predictions_section.dart",
    [
        (
            """class _PredictionRowCard extends StatelessWidget {""",
            """/// Fallback when the server joined no display name: a short slice of the
/// id instead of a full UUID filling the row.
String _shortId(String participantId) => participantId.length <= 8
    ? participantId
    : '${participantId.substring(0, 8)}\u2026';

class _PredictionRowCard extends StatelessWidget {""",
        ),
        (
            """                Text(
                  prediction.participantId,
                  key: Key('admin.predictions.item.${prediction.id}'),""",
            """                Text(
                  prediction.displayName.isNotEmpty
                      ? prediction.displayName
                      : _shortId(prediction.participantId),
                  key: Key('admin.predictions.item.${prediction.id}'),""",
        ),
    ],
)


def run(cmd, cwd=ROOT):
    print(f"$ {cmd}")
    if DRY:
        return
    r = subprocess.run(cmd, shell=True, cwd=cwd)
    if r.returncode != 0:
        sys.exit(r.returncode)


run("dart format packages/contracts/lib/src/fixture_prediction_dto.dart "
    "apps/server/lib/http/fixture_prediction_dto_mapper.dart "
    "'apps/server/routes/admin/fixtures/[id]/predictions/index.dart' "
    "apps/mobile/lib/features/admin/screens/sections/admin_predictions_section.dart")
run("cd packages/contracts && flutter test --reporter=failures-only")
run("cd apps/server && flutter test --reporter=failures-only")
run("cd apps/mobile && flutter analyze --no-fatal-infos lib/features/admin")
run("cd apps/mobile && flutter test --reporter=failures-only")

if not DRY:
    LOG = ROOT / "docs/checkpoints/session-log.md"
    LOG.write_text(
        LOG.read_text(encoding="utf-8")
        + "\n2026-09-05 \u2014 20_predictions_display_name: "
        "\u00ab\u0627\u0644\u062a\u0648\u0642\u0639\u0627\u062a\u00bb \u0641\u064a "
        "\u0644\u0648\u062d\u0629 \u0627\u0644\u0645\u0634\u0631\u0641 \u0635\u0627\u0631\u062a "
        "\u062a\u0639\u0631\u0636 \u0627\u0644\u0627\u0633\u0645. "
        "displayName \u0623\u064f\u0636\u064a\u0641 \u0625\u0644\u0649 FixturePredictionDto "
        "\u0628\u0646\u0641\u0633 \u0634\u0643\u0644 ParticipantFixtureScoreDto "
        "(\u0627\u062e\u062a\u064a\u0627\u0631\u064a\u060c \u0627\u0641\u062a\u0631\u0627\u0636\u064a "
        "''\u060c \u0648\u064a\u064f\u062d\u0630\u0641 \u0645\u0646 JSON \u0639\u0646\u062f "
        "\u0641\u0631\u0627\u063a\u0647 \u0641\u0644\u0627 \u064a\u0646\u0643\u0633\u0631 "
        "\u0645\u064f\u0641\u0643\u0651\u0643 \u0642\u062f\u064a\u0645)\u060c "
        "\u0648\u0627\u0644\u0631\u0628\u0637 \u064a\u062a\u0645 \u0641\u064a \u0627\u0644\u0645\u0633\u0627\u0631 "
        "GET /admin/fixtures/{id}/predictions \u0639\u0628\u0631 "
        "AdminGetParticipantDisplayNames \u0646\u0641\u0633\u0647 \u0627\u0644\u0630\u064a "
        "\u064a\u0633\u062a\u062e\u062f\u0645\u0647 \u0645\u0633\u0627\u0631 scores \u2014 "
        "\u0628\u0644\u0627 use-case \u062c\u062f\u064a\u062f \u0648\u0644\u0627 "
        "\u062a\u063a\u064a\u064a\u0631 \u0645\u062e\u0637\u0651\u0637 \u0648\u0644\u0627 "
        "\u062a\u0628\u0639\u064a\u0629. \u0641\u0634\u0644 \u0627\u0644\u0631\u0628\u0637 "
        "\u064a\u0646\u062d\u062f\u0631 \u0625\u0644\u0649 \u0628\u0644\u0627 "
        "\u0623\u0633\u0645\u0627\u0621 \u0644\u0627 \u0625\u0644\u0649 \u062e\u0637\u0623. "
        "\u2014 packages/contracts/lib/src/fixture_prediction_dto.dart, "
        "apps/server/lib/http/fixture_prediction_dto_mapper.dart, "
        "apps/server/routes/admin/fixtures/[id]/predictions/index.dart, "
        "apps/mobile/lib/features/admin/screens/sections/admin_predictions_section.dart\n",
        encoding="utf-8",
    )

run("git add packages/contracts/lib/src/fixture_prediction_dto.dart "
    "apps/server/lib/http/fixture_prediction_dto_mapper.dart "
    "'apps/server/routes/admin/fixtures/[id]/predictions/index.dart' "
    "apps/mobile/lib/features/admin/screens/sections/admin_predictions_section.dart "
    "docs/checkpoints/session-log.md")
run('git commit -m "feat(admin): join participant display name onto raw predictions read"')
print("done - no push")
