#!/usr/bin/env python3
"""
تطبيق: GET /admin/rounds/{id}/predictions (round-report raw predictions).
شغّله من جذر nukhbaa-main:  python3 apply_admin_round_predictions.py
"""
import os

ROOT = os.getcwd()


def replace(path, old, new, label):
    full = os.path.join(ROOT, path)
    with open(full, "r", encoding="utf-8") as f:
        content = f.read()
    if content.count(old) != 1:
        raise SystemExit(
            f"[FAIL] {label}: النص المطلوب غير موجود (أو مكرر) بالملف {path}"
        )
    content = content.replace(old, new, 1)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK] {label}")


def write_new(path, content, label):
    full = os.path.join(ROOT, path)
    if os.path.exists(full):
        raise SystemExit(f"[FAIL] {label}: الملف موجود مسبقًا {path}")
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK] {label} (ملف جديد)")


# ---------------------------------------------------------------------------
# 1) domain: AuditAction enum value جديدة
# ---------------------------------------------------------------------------
replace(
    "packages/domain/lib/src/admin/audit_action.dart",
    "  /// An admin linked a fixture to a round (reused `LinkFixtureToRound`).\n"
    "  fixtureLinkedToRound;",
    "  /// An admin linked a fixture to a round (reused `LinkFixtureToRound`).\n"
    "  fixtureLinkedToRound,\n\n"
    "  /// An admin viewed every participant's raw predictions for a scored round\n"
    "  /// (the round-report bulk read; narrow to one round, itself audited —\n"
    "  /// mirrors [participantLedgerViewed]'s no-silent-exemption rule).\n"
    "  roundPredictionsViewed;",
    "audit_action.dart: enum value",
)

replace(
    "packages/domain/lib/src/admin/audit_action.dart",
    "    AuditAction.fixtureLinkedToRound => 'fixture_linked_to_round',\n  };",
    "    AuditAction.fixtureLinkedToRound => 'fixture_linked_to_round',\n"
    "    AuditAction.roundPredictionsViewed => 'round_predictions_viewed',\n  };",
    "audit_action.dart: wireValue",
)

# ---------------------------------------------------------------------------
# 2) migration جديدة
# ---------------------------------------------------------------------------
write_new(
    "supabase/migrations/0014_round_predictions_audit.sql",
    """-- 0014_round_predictions_audit.sql
-- Extends `admin.audit_action` with the new admin round-report capability
-- (forward-only `alter type … add value`, exactly as 0010_admin.sql documents).

alter type admin.audit_action add value if not exists 'round_predictions_viewed';
""",
    "migration 0014",
)

# ---------------------------------------------------------------------------
# 3) application: use-case جديد
# ---------------------------------------------------------------------------
write_new(
    "packages/application/lib/src/admin/admin_list_round_predictions.dart",
    '''import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/prediction_repository.dart';
import 'package:application/src/prediction/prediction_view.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the admin **round-report raw-predictions read** — every
/// participant's predicted scorelines for one **scored** round (Admin Panel
/// decision OPEN-A #3 lineage: read-only, scoped to a single round by explicit
/// id, and itself audited — the report gets NO silent exemption from the
/// trail, mirroring [ViewParticipantLedger]).
///
/// Deliberately NOT a reuse of `ListRoundPredictions` (whose gate is
/// "caller is a participant of the round's season"): here the caller is an
/// admin who may not be a participant at all, reading every participant's
/// raw forecast at once for the round report. That widening — and the fact it
/// is bulk, not single-participant — is exactly why it is its own admin
/// use-case rather than a role bypass bolted onto the participant-facing one.
///
/// Gated on [RoundStatus.scored] (not merely locked): the round report pairs
/// this raw read with `GetRoundScores`, which uses the same gate, so both
/// halves of the report become available at the same moment and a
/// locked-but-unscored round never partially leaks.
///
/// Steps:
/// 1. authorize the caller as [PlatformRole.admin];
/// 2. resolve the round and require it is `scored`;
/// 3. record an immutable [AuditEntry] (`round_predictions_viewed`) BEFORE
///    returning the data;
/// 4. return every [PredictionView] for the round.
///
/// Never throws; returns a typed [Result].
final class AdminListRoundPredictions {
  /// Creates the use-case over its collaborators.
  const AdminListRoundPredictions({
    required CompetitionRepository competitionRepository,
    required PredictionRepository predictionRepository,
    required AuditRecorder auditRecorder,
  }) : _competition = competitionRepository,
       _predictions = predictionRepository,
       _audit = auditRecorder;

  final CompetitionRepository _competition;
  final PredictionRepository _predictions;
  final AuditRecorder _audit;

  /// Returns every participant's raw prediction for the scored round
  /// [roundId], recording the bulk support read in the audit trail.
  Future<Result<List<PredictionView>>> call({
    required AuthenticatedUser principal,
    required String roundId,
    String? reason,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final roundIdResult = RoundId.tryParse(roundId);
    if (roundIdResult is Err<RoundId>) {
      return Result.err(roundIdResult.error);
    }
    final rId = (roundIdResult as Ok<RoundId>).value;

    final roundResult = await _competition.findRound(rId);
    if (roundResult is Err<Round>) {
      return Result.err(roundResult.error);
    }
    final round = (roundResult as Ok<Round>).value;

    if (round.status != RoundStatus.scored) {
      return Result.err(
        AppError.invariant(
          'admin.round_not_scored',
          'The round report is available only after the round is scored '
              '(round is \\${round.status.wireValue})',
        ),
      );
    }

    // Audit the bulk cross-user read BEFORE serving the data (§2.4): a
    // completed report read always leaves an attributable trace.
    final audit = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.roundPredictionsViewed,
      targetRef: rId.value,
      reason: reason,
    );
    if (audit is Err<AuditEntry>) {
      return Result.err(audit.error);
    }

    return _predictions.listByRound(rId);
  }
}
''',
    "admin_list_round_predictions.dart",
)

# ---------------------------------------------------------------------------
# 4) application.dart barrel export
# ---------------------------------------------------------------------------
replace(
    "packages/application/lib/application.dart",
    "export 'src/admin/view_participant_ledger.dart';",
    "export 'src/admin/admin_list_round_predictions.dart';\n"
    "export 'src/admin/view_participant_ledger.dart';",
    "application.dart: export",
)

# ---------------------------------------------------------------------------
# 5) server route جديد
# ---------------------------------------------------------------------------
write_new(
    "apps/server/routes/admin/rounds/[id]/predictions/index.dart",
    '''import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/prediction_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/rounds/{id}/predictions` — the round-report **raw-predictions**
/// bulk read: every participant's predicted scorelines for one **scored**
/// round (Admin Panel decision OPEN-A #3 lineage: read-only, scoped to a
/// single round by explicit id, itself audited). Admin-only, enforced inside
/// `AdminListRoundPredictions`.
///
/// Unlike `GET /rounds/{id}/predictions/all` (whose gate is "caller is a
/// participant of the round's season", and which only requires the round be
/// locked), this is an admin-only bulk read of a **scored** round — the same
/// gate `GET /rounds/{id}/scores` uses — so the report's score half and raw
/// half become available together. A not-yet-scored round is `409`
/// `admin.round_not_scored`. The read is itself audited
/// (`round_predictions_viewed`), matching `GET /admin/participants/{id}/ledger`.
///
/// An optional `?reason=` query parameter is passed through to the audit
/// record; when supplied it must be non-blank (the domain `AuditEntry.create`
/// enforces this).
///
/// Returns a JSON array of [PredictionDto] (`200`) — the same wire shape as
/// the participant-facing endpoint, so the mobile admin round-report screen
/// reuses one mapper; an empty array means the round is scored but no one
/// predicted. `405` on any non-GET method.
///
/// The `/admin` subtree is already behind `bearerAuth`
/// (`routes/admin/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final reason = context.request.uri.queryParameters['reason'];

  final result = await root.adminListRoundPredictions(
    principal: principal,
    roundId: id,
    reason: reason,
  );

  return switch (result) {
    Ok<List<PredictionView>>(:final value) => Response.json(
      body: [for (final view in value) predictionViewToJson(view)],
    ),
    Err<List<PredictionView>>(:final error) => errorResponse(error),
  };
}
''',
    "admin/rounds/[id]/predictions/index.dart",
)

# ---------------------------------------------------------------------------
# 6) composition_root.dart — أربع نقاط ربط
# ---------------------------------------------------------------------------
CR = "apps/server/lib/composition/composition_root.dart"

replace(
    CR,
    "    required this.viewParticipantLedger,\n  }) : _connection = connection,",
    "    required this.viewParticipantLedger,\n"
    "    required this.adminListRoundPredictions,\n  }) : _connection = connection,",
    "composition_root: private constructor param",
)

replace(
    CR,
    "    ViewParticipantLedger? viewParticipantLedger,\n"
    "  }) : checkHealth = checkHealth ?? _absentCheckHealth(),",
    "    ViewParticipantLedger? viewParticipantLedger,\n"
    "    AdminListRoundPredictions? adminListRoundPredictions,\n"
    "  }) : checkHealth = checkHealth ?? _absentCheckHealth(),",
    "composition_root: forTesting param",
)

replace(
    CR,
    "       viewParticipantLedger =\n"
    "           viewParticipantLedger ?? _absentViewParticipantLedger(),\n"
    "       _connection = null,",
    "       viewParticipantLedger =\n"
    "           viewParticipantLedger ?? _absentViewParticipantLedger(),\n"
    "       adminListRoundPredictions =\n"
    "           adminListRoundPredictions ?? _absentAdminListRoundPredictions(),\n"
    "       _connection = null,",
    "composition_root: forTesting init",
)

replace(
    CR,
    "        auditRecorder: _absentAuditRecorder(),\n"
    "      );\n\n"
    "  /// The Postgres connection owned by a production root.",
    "        auditRecorder: _absentAuditRecorder(),\n"
    "      );\n\n"
    "  static AdminListRoundPredictions _absentAdminListRoundPredictions() =>\n"
    "      AdminListRoundPredictions(\n"
    "        competitionRepository: _unwiredCompetitionRepository,\n"
    "        predictionRepository: _unwiredPredictionRepository,\n"
    "        auditRecorder: _absentAuditRecorder(),\n"
    "      );\n\n"
    "  /// The Postgres connection owned by a production root.",
    "composition_root: absent factory",
)

replace(
    CR,
    "  final ViewParticipantLedger viewParticipantLedger;\n\n"
    "  /// Builds the graph from process environment",
    "  final ViewParticipantLedger viewParticipantLedger;\n\n"
    "  /// The admin round-report bulk read: every participant's raw prediction for\n"
    "  /// one scored round, itself audited (admin-only — mirrors\n"
    "  /// [viewParticipantLedger]'s no-silent-exemption rule).\n"
    "  final AdminListRoundPredictions adminListRoundPredictions;\n\n"
    "  /// Builds the graph from process environment",
    "composition_root: field",
)

replace(
    CR,
    "      viewParticipantLedger: ViewParticipantLedger(\n"
    "        participantReader: participantReader, // already built (Ledger slice)\n"
    "        ledgerRepository: ledgerRepository, // already built (Ledger slice)\n"
    "        auditRecorder: auditRecorder,\n"
    "      ),\n    );\n  }",
    "      viewParticipantLedger: ViewParticipantLedger(\n"
    "        participantReader: participantReader, // already built (Ledger slice)\n"
    "        ledgerRepository: ledgerRepository, // already built (Ledger slice)\n"
    "        auditRecorder: auditRecorder,\n"
    "      ),\n"
    "      adminListRoundPredictions: AdminListRoundPredictions(\n"
    "        competitionRepository: competitionRepository, // already built\n"
    "        predictionRepository: predictionRepository, // already built\n"
    "        auditRecorder: auditRecorder,\n"
    "      ),\n    );\n  }",
    "composition_root: bootstrap wiring",
)

# ---------------------------------------------------------------------------
# 7) اختبار use-case
# ---------------------------------------------------------------------------
write_new(
    "packages/application/test/admin/admin_list_round_predictions_test.dart",
    """import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import '../prediction/fake_prediction_repository.dart';
import 'fakes.dart';

const _roundId = '44444444-4444-4444-4444-444444444444';
const _otherParticipantId = '88888888-8888-8888-8888-888888888888';
const _predictionId = '66666666-6666-6666-6666-666666666666';
const _fixtureA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

final _submittedAt = DateTime.utc(2026, 8, 1, 12);

Round _round({RoundStatus status = RoundStatus.open}) {
  final open =
      (Round.open(
                id: const RoundId(_roundId),
                seasonId: const SeasonId(seasonUuid),
                sequence: 1,
                predictionDeadline: DateTime.utc(2026, 8, 2),
                ruleset: testSnapshot(),
              )
              as Ok<Round>)
          .value;
  if (status == RoundStatus.open) return open;
  final locked = (open.transitionTo(RoundStatus.locked) as Ok<Round>).value;
  if (status == RoundStatus.locked) return locked;
  return (locked.transitionTo(RoundStatus.scored) as Ok<Round>).value;
}

Prediction _prediction(String id, String participantId) =>
    (Prediction.submit(
              id: PredictionId(id),
              roundId: const RoundId(_roundId),
              participantId: ParticipantId(participantId),
              roundStatus: RoundStatus.open,
              scores: [
                (FixtureScorePrediction.create(
                          fixture: const FixtureRef(_fixtureA),
                          homeGoals: 2,
                          awayGoals: 1,
                        )
                        as Ok<FixtureScorePrediction>)
                    .value,
              ],
            )
            as Ok<Prediction>)
        .value;

void main() {
  late FakePredictionRepository predictions;
  late FakeCompetitionRepository competition;
  late InMemoryAuditLogRepository auditLog;
  late AdminListRoundPredictions useCase;

  setUp(() {
    predictions = FakePredictionRepository();
    competition = FakeCompetitionRepository();
    auditLog = InMemoryAuditLogRepository();
    useCase = AdminListRoundPredictions(
      competitionRepository: competition,
      predictionRepository: predictions,
      auditRecorder: auditRecorderOver(auditLog),
    );
  });

  test(
    'refuses a non-admin caller before any read or audit',
    () async {
      competition.seedRound(_round(status: RoundStatus.scored));
      final result = await useCase(
        principal: principal(userId: adminUuid, role: PlatformRole.user),
        roundId: _roundId,
      );
      final error = (result as Err<List<PredictionView>>).error;
      expect(error.kind, ErrorKind.authorization);
      expect(error.code, 'auth.insufficient_role');
      expect(auditLog.rows, isEmpty);
    },
  );

  test('rejects a round that is not yet scored', () async {
    competition.seedRound(_round(status: RoundStatus.locked));
    final result = await useCase(
      principal: principal(userId: adminUuid),
      roundId: _roundId,
    );
    final error = (result as Err<List<PredictionView>>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'admin.round_not_scored');
    expect(auditLog.rows, isEmpty);
  });

  test(
    'returns every participant\\'s raw prediction for a scored round, '
    'auditing the read',
    () async {
      competition.seedRound(_round(status: RoundStatus.scored));
      predictions.seedPrediction(
        _prediction(_predictionId, _otherParticipantId),
        _submittedAt,
      );

      final result = await useCase(
        principal: principal(userId: adminUuid),
        roundId: _roundId,
      );

      final list = (result as Ok<List<PredictionView>>).value;
      expect(list, hasLength(1));
      expect(list.single.prediction.scores.single.homeGoals, 2);
      expect(list.single.prediction.scores.single.awayGoals, 1);

      expect(auditLog.rows, hasLength(1));
      expect(auditLog.rows.single.action, AuditAction.roundPredictionsViewed);
      expect(auditLog.rows.single.targetRef, _roundId);
    },
  );

  test('a missing round is an invariant precondition failure', () async {
    final result = await useCase(
      principal: principal(userId: adminUuid),
      roundId: _roundId,
    );
    final error = (result as Err<List<PredictionView>>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'competition.round_not_found');
  });
}
""",
    "admin_list_round_predictions_test.dart",
)

print("\nتم بنجاح. شغّل الآن:")
print("  melos run build_runner  (إن لزم)")
print("  melos exec -- dart test    # أو: dart test داخل كل باكج متأثر")
print("  dart analyze")
