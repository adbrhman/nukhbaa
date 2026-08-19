/// The Admin Panel **view** state (audit log) plus the sanction commands
/// (suspend/reinstate) and the narrow cross-user ledger support-read.
///
/// Admin-only, enforced entirely server-side (Security ADR §2.2/§2.3) — this
/// file makes no authorization decision; `AdminApi` surfaces a non-admin
/// refusal as a typed `AppError` like any other failure.
///
/// **Scope (this pass):** audit trail, user suspend/reinstate, the
/// single-participant ledger support-read (all three over `AdminApi`),
/// fixture-identity register/correct (over `FixtureScheduleApi` —
/// `POST /fixtures` / `PUT /fixtures/{id}`, the fixture-IDENTITY seam, Axiom
/// 3), round administration — open a round + link a fixture into it, and
/// results/scoring administration — record a fixture's actual result, score
/// a round, and look up a scored round's results (all over `CompetitionApi`
/// — `POST /seasons/{id}/rounds` / `POST /rounds/{id}/fixtures` /
/// `PUT /fixtures/{id}/result` / `POST /rounds/{id}/score` /
/// `GET /rounds/{id}/scores`). Ledger-post administration is a separate
/// follow-up slice, mirroring how Groups was phased in this project.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import 'round_report.dart';
import '../competition/competition_providers.dart';

part 'admin_providers.g.dart';

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// `GET /admin/audit` — the append-only audit trail, newest first.
@riverpod
Future<AuditLogDto> auditLog(Ref ref) async {
  final api = ref.watch(adminApiProvider);
  return _unwrap(await api.listAuditLog());
}

/// Owns the suspend/reinstate sanction commands. On success it invalidates
/// [auditLogProvider] so the trail reflects the new entry.
@riverpod
class UserSanctionController extends _$UserSanctionController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<UserSanctionResultDto>? build() => null;

  /// Suspends [userId] with the mandatory [reason].
  Future<void> suspend(String userId, String reason) async {
    state = const AsyncValue.loading();
    final result = await _api.suspendUser(userId, reason);
    _applyAndRefresh(result);
  }

  /// Reinstates [userId] with the mandatory [reason].
  Future<void> reinstate(String userId, String reason) async {
    state = const AsyncValue.loading();
    final result = await _api.reinstateUser(userId, reason);
    _applyAndRefresh(result);
  }

  void _applyAndRefresh(Result<UserSanctionResultDto> result) {
    state = switch (result) {
      Ok<UserSanctionResultDto>(:final value) => AsyncValue.data(value),
      Err<UserSanctionResultDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
    if (state is AsyncData<UserSanctionResultDto>) {
      ref.invalidate(auditLogProvider);
    }
  }
}

/// Owns the users browse/search read (`GET /admin/users`), used to find a
/// target user id for the sanction fields. Modelled as a controller (rather
/// than a `FutureProvider`) since a search is an explicit admin action, not a
/// passive view a screen loads on entry.
@riverpod
class UsersLookupController extends _$UsersLookupController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<UserListDto>? build() => null;

  /// Searches users by an optional email-contains [search].
  Future<void> search(String search) async {
    state = const AsyncValue.loading();
    final result = await _api.listUsers(search: search);
    state = switch (result) {
      Ok<UserListDto>(:final value) => AsyncValue.data(value),
      Err<UserListDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the narrow cross-user ledger support-read
/// (`GET /admin/participants/{id}/ledger`). Modelled as a controller (rather
/// than a `FutureProvider`) because the read is itself an audited *action*
/// (Admin Panel decision OPEN-A #3) an admin explicitly triggers, not a
/// passive view an admin screen loads on entry.
@riverpod
class AdminLedgerLookupController extends _$AdminLedgerLookupController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<ParticipantEntriesDto>? build() => null;

  /// Looks up [participantId]'s ledger, optionally recording [reason] on the
  /// mandatory audit entry.
  Future<void> lookup(String participantId, {String? reason}) async {
    state = const AsyncValue.loading();
    final result = await _api.viewParticipantLedger(
      participantId,
      reason: reason,
    );
    state = switch (result) {
      Ok<ParticipantEntriesDto>(:final value) => AsyncValue.data(value),
      Err<ParticipantEntriesDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the fixture-identity register/correct commands
/// (`POST /fixtures` / `PUT /fixtures/{id}`) — the fixture-IDENTITY seam
/// (Axiom 3; Next-Task decision 2026-07-11, option (a)). Modelled as a
/// controller, not a `FutureProvider`, for the same reason as
/// [UserSanctionController]: a one-shot admin command, not a passive view an
/// admin screen loads on entry. No other provider reads a fixture's schedule
/// today, so a success here has nothing to invalidate.
@riverpod
class FixtureScheduleController extends _$FixtureScheduleController {
  FixtureScheduleApi get _api => ref.read(fixtureScheduleApiProvider);

  @override
  AsyncValue<FixtureScheduleDto>? build() => null;

  /// Registers a brand-new fixture's identity. The server generates the
  /// fixture id; it comes back on [FixtureScheduleDto.fixtureId] for the
  /// admin to note down (e.g. for a later [correct] call or to link it into
  /// a round).
  Future<void> register({
    required String homeTeam,
    required String awayTeam,
    required String kickoffAt,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.registerFixtureSchedule(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
    );
    _apply(result);
  }

  /// Corrects an already-registered fixture's identity by [fixtureId] (a
  /// mistyped team name or kickoff time, before the round is linked/locked).
  Future<void> correct({
    required String fixtureId,
    required String homeTeam,
    required String awayTeam,
    required String kickoffAt,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.correctFixtureSchedule(
      fixtureId: fixtureId,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
    );
    _apply(result);
  }

  void _apply(Result<FixtureScheduleDto> result) {
    state = switch (result) {
      Ok<FixtureScheduleDto>(:final value) => AsyncValue.data(value),
      Err<FixtureScheduleDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the open-round command (`POST /seasons/{id}/rounds`, command intent
/// `OpenRound`) over `CompetitionApi`. Modelled as a controller, not a
/// `FutureProvider`, for the same reason as [UserSanctionController]: a
/// one-shot admin command, not a passive view an admin screen loads on entry.
@riverpod
class RoundOpenController extends _$RoundOpenController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundDto>? build() => null;

  /// Opens round [sequence] in season [seasonId] with [predictionDeadline]
  /// (an ISO 8601 timestamp string; the server normalizes it to UTC).
  Future<void> open({
    required String seasonId,
    required int sequence,
    required String predictionDeadline,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.openRound(
      seasonId: seasonId,
      sequence: sequence,
      predictionDeadline: predictionDeadline,
    );
    state = switch (result) {
      Ok<RoundDto>(:final value) => AsyncValue.data(value),
      Err<RoundDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
    if (state is AsyncData<RoundDto>) {
      final RoundDto opened = (state as AsyncData<RoundDto>).value;
      ref.invalidate(seasonRoundsProvider(seasonId));
      ref.invalidate(roundDetailProvider(opened.id));
      ref.invalidate(roundFixturesProvider(opened.id));
    }
  }
}

/// Owns the lock-round command (`POST /rounds/{id}/lock`, command intent
/// `LockRound`) over `CompetitionApi`. Modelled as a controller for the same
/// reason as [RoundOpenController]: a one-shot admin command. A round must be
/// locked before [ScoreRoundController] can score it.
@riverpod
class RoundLockController extends _$RoundLockController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundDto>? build() => null;

  /// Locks round [roundId].
  Future<void> lock(String roundId) async {
    state = const AsyncValue.loading();
    final result = await _api.lockRound(roundId);
    state = switch (result) {
      Ok<RoundDto>(:final value) => AsyncValue.data(value),
      Err<RoundDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
    if (state is AsyncData<RoundDto>) {
      final RoundDto locked = (state as AsyncData<RoundDto>).value;
      ref.invalidate(seasonRoundsProvider(locked.seasonId));
      ref.invalidate(roundDetailProvider(locked.id));
    }
  }
}

/// Owns the link-fixture-to-round command (`POST /rounds/{id}/fixtures`,
/// command intent `LinkFixtureToRound`; Axiom 3) over `CompetitionApi`.
/// Modelled as a controller for the same reason as [RoundOpenController].
@riverpod
class RoundFixtureLinkController extends _$RoundFixtureLinkController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundFixtureDto>? build() => null;

  /// Links [fixtureId] into [roundId] at [displayOrder] (0-based).
  Future<void> link({
    required String roundId,
    required String fixtureId,
    required int displayOrder,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.linkFixtureToRound(
      roundId: roundId,
      fixtureId: fixtureId,
      displayOrder: displayOrder,
    );
    state = switch (result) {
      Ok<RoundFixtureDto>(:final value) => AsyncValue.data(value),
      Err<RoundFixtureDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
    if (state is AsyncData<RoundFixtureDto>) {
      ref.invalidate(roundFixturesProvider(roundId));
      ref.invalidate(roundDetailProvider(roundId));
    }
  }
}

/// Owns the remove-fixture-from-round command
/// (`DELETE /rounds/{id}/fixtures/{fixtureId}`, command intent
/// `RemoveFixtureFromRound` — the correction counterpart of
/// [RoundFixtureLinkController] for a duplicate/mistaken link) over
/// `CompetitionApi`. Modelled as a controller for the same reason as
/// [RoundOpenController].
@riverpod
class RemoveFixtureController extends _$RemoveFixtureController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<bool>? build() => null;

  /// Removes [fixtureId] from [roundId]. Refused (server-side) when the
  /// round is no longer open or the fixture already carries a recorded
  /// result (`competition.fixture_result_already_recorded`).
  Future<void> remove({
    required String roundId,
    required String fixtureId,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.removeFixtureFromRound(
      roundId: roundId,
      fixtureId: fixtureId,
    );
    state = switch (result) {
      Ok<bool>(:final value) => AsyncValue.data(value),
      Err<bool>(:final error) => AsyncValue.error(error, StackTrace.current),
    };
    if (state is AsyncData<bool>) {
      ref.invalidate(roundFixturesProvider(roundId));
      ref.invalidate(roundDetailProvider(roundId));
    }
  }
}

/// Owns the record-fixture-result command (`PUT /fixtures/{id}/result`,
/// command intent `RecordFixtureResult`; Axiom 3) over `CompetitionApi`.
/// Modelled as a controller for the same reason as [RoundOpenController].
@riverpod
class RecordFixtureResultController extends _$RecordFixtureResultController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<FixtureResultDto>? build() => null;

  /// Records fixture [fixtureId]'s actual final score.
  Future<void> record({
    required String fixtureId,
    required int homeGoals,
    required int awayGoals,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.recordFixtureResult(
      fixtureId: fixtureId,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
    );
    state = switch (result) {
      Ok<FixtureResultDto>(:final value) => AsyncValue.data(value),
      Err<FixtureResultDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the score-round command (`POST /rounds/{id}/score`, command intent
/// `ScoreRound`) over `CompetitionApi`. Modelled as a controller for the same
/// reason as [RoundOpenController]. No request body — points are computed
/// server-side (Axioms 2/5).
@riverpod
class ScoreRoundController extends _$ScoreRoundController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundScoresDto>? build() => null;

  /// Scores every prediction in [roundId].
  Future<void> score(String roundId) async {
    state = const AsyncValue.loading();
    final result = await _api.scoreRound(roundId);
    state = switch (result) {
      Ok<RoundScoresDto>(:final value) => AsyncValue.data(value),
      Err<RoundScoresDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the post-round-to-ledger command (`POST /rounds/{id}/ledger`,
/// command intent `PostRoundToLedger`) over `CompetitionApi`. Modelled as a
/// controller for the same reason as [ScoreRoundController]. This is the
/// required step after [ScoreRoundController] and before a participant's
/// points appear in the Hall of Fame / season leaderboard: those read
/// exclusively from the ledger, never from round_scores directly.
@riverpod
class PostRoundToLedgerController extends _$PostRoundToLedgerController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<PostRoundToLedgerResponseDto>? build() => null;

  /// Posts round [roundId]'s already-computed scores to the ledger.
  Future<void> post(String roundId) async {
    state = const AsyncValue.loading();
    final result = await _api.postRoundToLedger(roundId);
    state = switch (result) {
      Ok<PostRoundToLedgerResponseDto>(:final value) => AsyncValue.data(value),
      Err<PostRoundToLedgerResponseDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the round-scores lookup (`GET /rounds/{id}/scores`, query intent
/// `GetRoundScores`) over `CompetitionApi`. Modelled as a controller (rather
/// than a `FutureProvider`) for the same reason as
/// [AdminLedgerLookupController]: an admin explicitly triggers this read, it
/// is not a passive view a screen loads on entry.
@riverpod
class RoundScoresLookupController extends _$RoundScoresLookupController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<RoundScoresDto>? build() => null;

  /// Looks up [roundId]'s computed scores.
  Future<void> lookup(String roundId) async {
    state = const AsyncValue.loading();
    final result = await _api.adminGetRoundScores(roundId);
    state = switch (result) {
      Ok<RoundScoresDto>(:final value) => AsyncValue.data(value),
      Err<RoundScoresDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the round-report bulk read: fetches `GET /rounds/{id}/scores`
/// (`CompetitionApi`) and `GET /admin/rounds/{id}/predictions` (`AdminApi`,
/// itself audited) concurrently for a **scored** round, then merges them via
/// [buildRoundReport] into a ranked, per-fixture breakdown. Modelled as a
/// controller (rather than a `FutureProvider`) for the same reason as
/// [RoundScoresLookupController]: an admin explicitly triggers the report, it
/// is not a passive view a screen loads on entry — and the raw-predictions
/// half is itself an audited cross-user read that must not fire silently.
@riverpod
class RoundReportController extends _$RoundReportController {
  AdminApi get _adminApi => ref.read(adminApiProvider);

  @override
  AsyncValue<List<RoundReportRow>>? build() => null;

  /// Loads the report for the scored round [roundId]. [reason] is an
  /// optional justification recorded on the raw-predictions audit entry.
  ///
  /// Both calls run concurrently; either failing surfaces its error and skips
  /// the merge (a round-report is all-or-nothing — a half-merged report with
  /// missing raw scores or missing grades would mislead the admin).
  Future<void> load(String roundId, {String? reason}) async {
    state = const AsyncValue.loading();
    final results = await (
      _adminApi.adminGetRoundScores(roundId),
      _adminApi.adminListRoundPredictions(roundId, reason: reason),
    ).wait;
    final scoresResult = results.$1;
    final predictionsResult = results.$2;

    if (scoresResult is Err<RoundScoresDto>) {
      state = AsyncValue.error(scoresResult.error, StackTrace.current);
      return;
    }
    if (predictionsResult is Err<List<PredictionDto>>) {
      state = AsyncValue.error(predictionsResult.error, StackTrace.current);
      return;
    }

    final scores = (scoresResult as Ok<RoundScoresDto>).value;
    final predictions = (predictionsResult as Ok<List<PredictionDto>>).value;
    state = AsyncValue.data(
      buildRoundReport(scores: scores, rawPredictions: predictions),
    );
  }
}

/// Owns the round-report **summary** read: fetches `GET /rounds/{id}/report`
/// directly (Task 5) — server-side aggregated correct/incorrect counts and
/// points, no client-side merge. Named "Summary" to avoid colliding with
/// [RoundReportController] (Task 4's grid — a client merge of two other
/// reads).
@riverpod
class RoundReportSummaryController extends _$RoundReportSummaryController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<RoundReportDto>? build() => null;

  /// Loads the report summary for the scored round [roundId].
  Future<void> load(String roundId) async {
    state = const AsyncValue.loading();
    final result = await _api.adminGetRoundReport(roundId);
    state = switch (result) {
      Ok<RoundReportDto>(:final value) => AsyncValue.data(value),
      Err<RoundReportDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// نتيجة دمج تسجيل المباراة وربطها بالجولة — نجاح فقط إذا نجحت العمليتان معاً.
class AddMatchResult {
  const AddMatchResult({
    required this.fixture,
    required this.link,
    required this.roundSequence,
  });

  final FixtureScheduleDto fixture;
  final RoundFixtureDto link;
  final int roundSequence;
}

/// يدمج `registerFixtureSchedule` ثم `linkFixtureToRound` في أمر واحد ذرّي من
/// منظور المستخدم: لا يُعلن النجاح إلا بعد نجاح العمليتين معاً. إذا نجح التسجيل
/// وفشل الربط، تظهر رسالة خطأ الربط ولا تُعتبر العملية ناجحة.
///
/// يبقى تسلسل الأمرين لأن العقود تفصل `POST /fixtures` عن
/// `POST /rounds/{id}/fixtures` (Axiom 3) — لا يوجد endpoint واحد يفعل الاثنين،
/// فنؤمّن الذرّية على الواجهة دون أي تعديل على الخادم.
@riverpod
class AddMatchController extends _$AddMatchController {
  FixtureScheduleApi get _fixtureApi => ref.read(fixtureScheduleApiProvider);
  CompetitionApi get _competitionApi => ref.read(competitionApiProvider);

  @override
  AsyncValue<AddMatchResult>? build() => null;

  /// يسجّل مباراة جديدة ثم يربطها بـ [roundId] عند [displayOrder].
  /// [roundSequence] يُستخدم فقط لرسالة النجاح الودّية.
  Future<void> submit({
    required String roundId,
    required int roundSequence,
    required String homeTeam,
    required String awayTeam,
    required String kickoffAt,
    required int displayOrder,
  }) async {
    state = const AsyncValue.loading();

    // (1) تسجيل هوية المباراة — الخادم يولّد fixtureId.
    final registerResult = await _fixtureApi.registerFixtureSchedule(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
    );
    if (registerResult is Err<FixtureScheduleDto>) {
      state = AsyncValue.error(registerResult.error, StackTrace.current);
      return;
    }
    final fixture = (registerResult as Ok<FixtureScheduleDto>).value;

    // (2) ربط المباراة بالجولة — لا نعلن النجاح إلا بعد نجاح هذه الخطوة.
    final linkResult = await _competitionApi.linkFixtureToRound(
      roundId: roundId,
      fixtureId: fixture.fixtureId,
      displayOrder: displayOrder,
    );
    if (linkResult is Err<RoundFixtureDto>) {
      state = AsyncValue.error(linkResult.error, StackTrace.current);
      return;
    }
    final link = (linkResult as Ok<RoundFixtureDto>).value;

    state = AsyncValue.data(
      AddMatchResult(
        fixture: fixture,
        link: link,
        roundSequence: roundSequence,
      ),
    );

    // حدّث قوائم مباريات الجولة حتى يُحسب displayOrder التالي تلقائياً.
    ref.invalidate(roundFixturesProvider(roundId));
    ref.invalidate(roundDetailProvider(roundId));
  }
}
