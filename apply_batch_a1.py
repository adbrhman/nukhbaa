#!/usr/bin/env python3
"""دفعة أ.1 — حذف OpenRound/LockRound من application + server.
شغّله من جذر المستودع: python3 apply_batch_a1.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))


def die(msg):
    print(f"❌ {msg}", file=sys.stderr)
    sys.exit(1)


def replace_once(path, old, new, label):
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        die(f"{label}: الملف غير موجود: {path}")
    with open(full, "r", encoding="utf-8") as f:
        content = f.read()
    count = content.count(old)
    if count != 1:
        die(f"{label}: توقعت تطابقًا واحدًا لكن وُجد {count} — الملف {path} قد يكون مختلفًا عمّا هو متوقع. لم يُعدَّل شيء.")
    content = content.replace(old, new, 1)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"✅ {label}: {path}")


def remove_file(path):
    full = os.path.join(ROOT, path)
    if os.path.exists(full):
        os.remove(full)
        print(f"🗑️  حُذف: {path}")
    else:
        print(f"⚠️  غير موجود أصلًا (تخطّي): {path}")


# 1) حذف الملفات المخصصة بالكامل
for p in [
    "packages/application/lib/src/competition/open_round.dart",
    "packages/application/lib/src/competition/lock_round.dart",
    "packages/application/test/competition/open_round_test.dart",
    "packages/application/test/competition/lock_round_test.dart",
    "apps/server/routes/rounds/[id]/lock/index.dart",
    "apps/server/test/routes/round_lock_test.dart",
    "apps/server/test/routes/season_rounds_test.dart",
]:
    remove_file(p)

lock_dir = os.path.join(ROOT, "apps/server/routes/rounds/[id]/lock")
if os.path.isdir(lock_dir) and not os.listdir(lock_dir):
    os.rmdir(lock_dir)
    print("🗑️  حُذف المجلد الفارغ: apps/server/routes/rounds/[id]/lock")

# 2) application.dart — إزالة exports
replace_once(
    "packages/application/lib/application.dart",
    "export 'src/competition/lock_round.dart';\nexport 'src/competition/open_round.dart';\n",
    "",
    "application.dart exports",
)

# 3) route: seasons/[id]/rounds/index.dart
route_path = "apps/server/routes/seasons/[id]/rounds/index.dart"
replace_once(
    route_path,
    """///   [RoundDto] (ruleset *version* only — the opaque frozen snapshot is never
///   exposed).
/// * `POST` — open a round in the season, freezing the ruleset (command intent
///   `OpenRound`, not a raw insert). Admin-authorized inside the use-case.
///
/// Both branches are authenticated (bearerAuth middleware; the `/seasons`
/// subtree already applies it via `seasons/_middleware.dart`). Any other method
/// is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _list(context, id),
    HttpMethod.post => _create(context, id),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}""",
    """///   [RoundDto] (ruleset *version* only — the opaque frozen snapshot is never
///   exposed).
///
/// Authenticated (bearerAuth middleware; the `/seasons` subtree already
/// applies it via `seasons/_middleware.dart`). Any other method is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _list(context, id),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}""",
    "route: onRequest",
)

replace_once(
    route_path,
    """
/// POST /seasons/{id}/rounds — open a round, freezing the ruleset (unchanged
/// command path; API ADR §2: command intent `OpenRound`). Admin-only (use-case
/// layer).
///
/// Path: season id. Body: `{ "sequence", "prediction_deadline" }` where
/// `prediction_deadline` is an ISO-8601 instant. The edge parses the deadline
/// to a UTC [DateTime] (a transport concern); the domain re-asserts UTC and the
/// 1-based sequence rule. Returns the created [RoundDto] (`201`).
Future<Response> _create(RequestContext context, String id) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final sequence = requireInt(body, 'sequence');
  if (sequence is Err<int>) return errorResponse(sequence.error);

  final deadlineResult = _parseDeadline(body['prediction_deadline']);
  if (deadlineResult is Err<DateTime>) {
    return errorResponse(deadlineResult.error);
  }

  final result = await root.openRound(
    principal: principal,
    seasonId: id,
    sequence: (sequence as Ok<int>).value,
    predictionDeadline: (deadlineResult as Ok<DateTime>).value,
  );

  if (result is Err<Round>) return errorResponse(result.error);
  final created = (result as Ok<Round>).value;

  // The freshly-opened round needs its siblings to compute `isPredictable`
  // (e.g. opening round 2 while round 1 is still open must report `false`).
  final seasonRoundsResult = await root.listSeasonRounds(
    principal: principal,
    seasonId: id,
  );
  if (seasonRoundsResult is Err<List<Round>>) {
    return errorResponse(seasonRoundsResult.error);
  }
  final seasonRounds = (seasonRoundsResult as Ok<List<Round>>).value;

  return Response.json(
    statusCode: HttpStatus.created,
    body: roundToDto(created, seasonRounds: seasonRounds).toJson(),
  );
}

/// Parses the untrusted `prediction_deadline` field into a UTC [DateTime].
///
/// Requires an ISO-8601 string; anything else is a validation failure. The
/// parsed instant is normalized to UTC so the domain's UTC invariant holds
/// regardless of the offset the caller supplied.
Result<DateTime> _parseDeadline(Object? raw) {
  if (raw is! String) {
    return const Result.err(
      AppError.validation(
        'request.field_missing',
        'Field "prediction_deadline" is required and must be an ISO-8601 string',
      ),
    );
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return const Result.err(
      AppError.validation(
        'request.deadline_malformed',
        'Field "prediction_deadline" must be a valid ISO-8601 instant',
      ),
    );
  }
  return Result.ok(parsed.toUtc());
}""",
    "",
    "route: حذف _create + _parseDeadline",
)

replace_once(
    route_path,
    "import 'package:server/http/error_envelope.dart';\nimport 'package:server/http/json_body.dart';\nimport 'package:shared/shared.dart';",
    "import 'package:server/http/error_envelope.dart';\nimport 'package:shared/shared.dart';",
    "route: إزالة استيراد json_body غير المستخدم",
)

# 4) composition_root.dart
cr_path = "apps/server/lib/composition/composition_root.dart"

replace_once(
    cr_path,
    "    required this.startSeason,\n    required this.openRound,\n    required this.lockRound,\n    required this.linkFixtureToRound,",
    "    required this.startSeason,\n    required this.linkFixtureToRound,",
    "composition_root: constructor الأساسي required params",
)

replace_once(
    cr_path,
    "    StartSeason? startSeason,\n    OpenRound? openRound,\n    LockRound? lockRound,\n    LinkFixtureToRound? linkFixtureToRound,",
    "    StartSeason? startSeason,\n    LinkFixtureToRound? linkFixtureToRound,",
    "composition_root: forTesting factory params",
)

replace_once(
    cr_path,
    "       startSeason = startSeason ?? _absentStartSeason(),\n       openRound = openRound ?? _absentOpenRound(),\n       lockRound = lockRound ?? _absentLockRound(),\n       linkFixtureToRound = linkFixtureToRound ?? _absentLinkFixtureToRound(),",
    "       startSeason = startSeason ?? _absentStartSeason(),\n       linkFixtureToRound = linkFixtureToRound ?? _absentLinkFixtureToRound(),",
    "composition_root: forTesting assignment",
)

replace_once(
    cr_path,
    "  static OpenRound _absentOpenRound() => OpenRound(\n    repository: _unwiredCompetitionRepository,\n    rulesetProvider: _unwiredRulesetProvider,\n    idGenerator: _unwiredIdGenerator,\n  );\n\n  static LockRound _absentLockRound() =>\n      LockRound(_unwiredCompetitionRepository);\n\n  static LinkFixtureToRound _absentLinkFixtureToRound() =>",
    "  static LinkFixtureToRound _absentLinkFixtureToRound() =>",
    "composition_root: حذف _absentOpenRound/_absentLockRound",
)

replace_once(
    cr_path,
    "  final StartSeason startSeason;\n\n  /// Opens a round in a season, freezing the ruleset (admin-only command).\n  final OpenRound openRound;\n\n  /// Locks an open round (admin-only command).\n  final LockRound lockRound;\n\n  /// Links a fixture to an open round (admin-only command).",
    "  final StartSeason startSeason;\n\n  /// Links a fixture to an open round (admin-only command).",
    "composition_root: حذف حقول openRound/lockRound",
)

replace_once(
    cr_path,
    "      openRound: OpenRound(\n        repository: competitionRepository,\n        rulesetProvider: rulesetProvider,\n        idGenerator: idGenerator,\n      ),\n      lockRound: LockRound(competitionRepository),\n      linkFixtureToRound: LinkFixtureToRound(competitionRepository),",
    "      linkFixtureToRound: LinkFixtureToRound(competitionRepository),",
    "composition_root: حذف التوصيل الفعلي",
)

replace_once(
    cr_path,
    "/// Backs an \"absent\" [OpenRound]'s ruleset provider.\nfinal class _UnwiredRulesetProvider implements RulesetProvider {\n  @override\n  Future<Result<RulesetSnapshot>> currentSnapshotFor(FormatType format) =>\n      throw StateError('OpenRound was not wired into this root');\n}",
    "/// Backs an \"absent\" ruleset-dependent use-case's ruleset provider.\nfinal class _UnwiredRulesetProvider implements RulesetProvider {\n  @override\n  Future<Result<RulesetSnapshot>> currentSnapshotFor(FormatType format) =>\n      throw StateError('A ruleset-dependent use-case was not wired into this root');\n}",
    "composition_root: تحديث رسالة _UnwiredRulesetProvider",
)

print("\n🎉 اكتملت دفعة أ.1 بنجاح.")
