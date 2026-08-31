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
/// 3), round administration — link a fixture into a round, and
/// results/scoring administration — record a fixture's actual result (all
/// over `CompetitionApi` — `POST /seasons/{id}/rounds` /
/// `POST /rounds/{id}/fixtures` / `PUT /fixtures/{id}/result`). Ledger-post
/// administration is a separate follow-up slice, mirroring how Groups was
/// phased in this project.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import 'fixture_report.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/fixture_prediction_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';

part 'admin_providers.g.dart';

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// The live data used by the Admin Control Center.
///
/// This is deliberately composed from the existing typed APIs. The dashboard
/// never owns a second repository, cache, or database and it does not invent
/// totals when the current API only exposes a bounded admin page.
final class AdminDashboardSnapshot {
  const AdminDashboardSnapshot({
    required this.users,
    required this.auditLog,
    required this.competitions,
    required this.currentMonthFixtures,
  });

  final UserListDto users;
  final AuditLogDto auditLog;
  final List<CompetitionDto> competitions;
  final List<CurrentMonthFixtureItemDto> currentMonthFixtures;

  int get activeUsers =>
      users.users.where((user) => user.status == 'active').length;

  int get suspendedUsers =>
      users.users.where((user) => user.status == 'suspended').length;

  int get todayFixtures {
    final now = DateTime.now();
    return currentMonthFixtures.where((item) {
      final kickoff = DateTime.tryParse(item.fixture.kickoffAt ?? '');
      if (kickoff == null) return false;
      final local = kickoff.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).length;
  }

  int get upcomingFixtures {
    final now = DateTime.now();
    return currentMonthFixtures.where((item) {
      final kickoff = DateTime.tryParse(item.fixture.kickoffAt ?? '');
      return kickoff != null && kickoff.isAfter(now.toUtc());
    }).length;
  }
}

/// Reads the real sources needed by the overview in parallel.
///
/// The users endpoint is intentionally requested with its server-side maximum
/// page size. Until a count/pagination contract exists, the UI labels this
/// value as a bounded admin view rather than pretending it is a global total.
@riverpod
Future<AdminDashboardSnapshot> adminDashboard(Ref ref) async {
  final adminApi = ref.watch(adminApiProvider);
  final competitionApi = ref.watch(competitionApiProvider);
  final results = await (
    adminApi.listUsers(limit: 50),
    adminApi.listAuditLog(limit: 10),
    competitionApi.listCompetitions(),
    competitionApi.getCurrentMonthFixtures(),
  ).wait;

  return AdminDashboardSnapshot(
    users: _unwrap(results.$1),
    auditLog: _unwrap(results.$2),
    competitions: _unwrap(results.$3),
    currentMonthFixtures: _unwrap(results.$4),
  );
}

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

/// Owns the record-fixture-result command (`PUT /fixtures/{id}/result`,
/// command intent `RecordFixtureResult`; Axiom 3) over `CompetitionApi`.
/// Modelled as a controller rather than a `FutureProvider` because it is an
/// admin-triggered write, not a passive view a screen loads on entry.
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

/// Owns the score-fixture command (`POST /fixtures/{id}/score`, command
/// intent `ScoreFixture`) over [CompetitionApi]. The per-fixture sibling of
/// the retired round-level `ScoreRoundController`.
@riverpod
class ScoreFixtureController extends _$ScoreFixtureController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<FixtureScoresDto>? build() => null;

  /// Scores every prediction recorded for [fixtureId].
  Future<void> score(String fixtureId) async {
    state = const AsyncValue.loading();
    final result = await _api.scoreFixture(fixtureId);
    state = switch (result) {
      Ok<FixtureScoresDto>(:final value) => AsyncValue.data(value),
      Err<FixtureScoresDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the post-fixture-to-ledger command (`POST /fixtures/{id}/ledger`,
/// command intent `PostFixtureToLedger`) over [CompetitionApi].
@riverpod
class PostFixtureToLedgerController extends _$PostFixtureToLedgerController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<PostFixtureToLedgerResponseDto>? build() => null;

  /// Posts fixture [fixtureId]'s already-computed scores to the ledger.
  Future<void> post(String fixtureId) async {
    state = const AsyncValue.loading();
    final result = await _api.postFixtureToLedger(fixtureId);
    state = switch (result) {
      Ok<PostFixtureToLedgerResponseDto>(:final value) => AsyncValue.data(
        value,
      ),
      Err<PostFixtureToLedgerResponseDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the fixture-report bulk read: fetches `GET /admin/fixtures/{id}/scores`
/// and `GET /admin/fixtures/{id}/predictions` (both `AdminApi`, the second
/// itself audited) concurrently — admin-only, no season-participation gate
/// (the per-fixture sibling of the retired round-level
/// `RoundReportController`, added so an admin can review any fixture's
/// predictions/scores regardless of the admin's own season membership, for
/// investigating user complaints). Modelled as a controller rather than a
/// `FutureProvider` because an admin explicitly triggers the report, it is
/// not a passive view a screen loads on entry.
@riverpod
class FixtureReportController extends _$FixtureReportController {
  AdminApi get _adminApi => ref.read(adminApiProvider);

  @override
  AsyncValue<List<FixtureReportRow>>? build() => null;

  /// Loads the report for [fixtureId]. [reason] is an optional justification
  /// recorded on the raw-predictions audit entry.
  ///
  /// Both calls run concurrently; either failing surfaces its error and skips
  /// the merge (same all-or-nothing rationale as the retired
  /// `RoundReportController`).
  Future<void> load(String fixtureId, {String? reason}) async {
    state = const AsyncValue.loading();
    final results = await (
      _adminApi.adminGetFixtureScores(fixtureId),
      _adminApi.adminListFixturePredictions(fixtureId, reason: reason),
    ).wait;
    final scoresResult = results.$1;
    final predictionsResult = results.$2;

    if (scoresResult is Err<FixtureScoresDto>) {
      state = AsyncValue.error(scoresResult.error, StackTrace.current);
      return;
    }
    if (predictionsResult is Err<List<FixturePredictionDto>>) {
      state = AsyncValue.error(predictionsResult.error, StackTrace.current);
      return;
    }

    final scores = (scoresResult as Ok<FixtureScoresDto>).value;
    final predictions =
        (predictionsResult as Ok<List<FixturePredictionDto>>).value;
    state = AsyncValue.data(
      buildFixtureReport(scores: scores, rawPredictions: predictions),
    );
  }
}

/// نتيجة دمج تسجيل المباراة وربطها بالجولة — نجاح فقط إذا نجحت العمليتان معاً.
class AddMatchResult {
  const AddMatchResult({required this.fixture, required this.link});

  final FixtureScheduleDto fixture;
  final SeasonFixtureDto link;
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

  /// يسجّل مباراة جديدة ثم يربطها بـ [seasonId] عند [displayOrder]
  /// (Phase 7.4 — Competition → Season → Fixture، بلا Round، Axiom 4
  /// Amendment).
  Future<void> submit({
    required String seasonId,
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

    // (2) ربط المباراة بالموسم — لا نعلن النجاح إلا بعد نجاح هذه الخطوة.
    final linkResult = await _competitionApi.linkFixtureToSeason(
      seasonId: seasonId,
      fixtureId: fixture.fixtureId,
      displayOrder: displayOrder,
    );
    if (linkResult is Err<SeasonFixtureDto>) {
      state = AsyncValue.error(linkResult.error, StackTrace.current);
      return;
    }
    final link = (linkResult as Ok<SeasonFixtureDto>).value;

    state = AsyncValue.data(AddMatchResult(fixture: fixture, link: link));

    // حدّث قائمة مباريات الموسم حتى يُحسب displayOrder التالي تلقائياً.
    ref.invalidate(seasonFixturesProvider(seasonId));
    ref.invalidate(currentMonthFixturesProvider);
  }
}

/// Owns the create-competition command (`POST /competitions`, command
/// intent `CreateCompetition`; Section 9 -- Monthly Competitions) over
/// [AdminApi]. Modelled as a controller for the same reason as
/// [UserSanctionController]: a one-shot admin command, not a passive view
/// an admin screen loads on entry. On success it invalidates
/// [competitionListProvider] so the new competition appears in every
/// picker/catalogue read immediately.
@riverpod
class CreateCompetitionController extends _$CreateCompetitionController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<CompetitionDto>? build() => null;

  /// Creates a competition named [name] with [format]/[visibility].
  Future<void> create({
    required String name,
    required String format,
    required String visibility,
  }) async {
    state = const AsyncValue.loading();
    final result = await _api.createCompetition(
      name: name,
      format: format,
      visibility: visibility,
    );
    state = switch (result) {
      Ok<CompetitionDto>(:final value) => AsyncValue.data(value),
      Err<CompetitionDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
    if (state is AsyncData<CompetitionDto>) {
      ref.invalidate(competitionListProvider);
    }
  }
}

/// Owns the start-season command (`POST /competitions/{id}/seasons`,
/// command intent `StartSeason`; Section 9 -- Monthly Competitions) over
/// [AdminApi]. Family-scoped by [competitionId] (Section 9 UI wiring,
/// 2026-08-29): the monthly-competitions admin screen shows one "Start
/// Season" action per competition row, so each competition needs its own
/// independent loading/success/error state. A single shared instance (as
/// used by [CreateCompetitionController], which backs exactly one
/// on-screen form) would let one row's in-flight/result state leak into
/// another row's. On success it invalidates [competitionSeasonsProvider]
/// and [currentSeasonProvider] for the same competition so both "previous
/// months" and "current month" reflect the new season immediately.
@riverpod
class StartSeasonController extends _$StartSeasonController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<SeasonDto>? build(String competitionId) => null;

  /// Starts the calendar-month season for [year]/[month] (1-12) under
  /// this controller's [competitionId].
  Future<void> start({required int year, required int month}) async {
    state = const AsyncValue.loading();
    final result = await _api.startSeason(
      competitionId: competitionId,
      year: year,
      month: month,
    );
    state = switch (result) {
      Ok<SeasonDto>(:final value) => AsyncValue.data(value),
      Err<SeasonDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
    if (state is AsyncData<SeasonDto>) {
      ref.invalidate(competitionSeasonsProvider(competitionId));
      ref.invalidate(currentSeasonProvider(competitionId));
    }
  }
}
