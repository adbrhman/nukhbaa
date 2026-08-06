/// The Admin Panel **view** state (audit log) plus the sanction commands
/// (suspend/reinstate) and the narrow cross-user ledger support-read.
///
/// Admin-only, enforced entirely server-side (Security ADR §2.2/§2.3) — this
/// file makes no authorization decision; `AdminApi` surfaces a non-admin
/// refusal as a typed `AppError` like any other failure.
///
/// **Scope (this pass):** audit trail, user suspend/reinstate, the
/// single-participant ledger support-read (all three over `AdminApi`), and
/// fixture-identity register/correct (over `FixtureScheduleApi` —
/// `POST /fixtures` / `PUT /fixtures/{id}`, the fixture-IDENTITY seam, Axiom
/// 3). Round/scoring administration (open/lock a round, link a fixture to a
/// round, record a result, run scoring, post to the ledger) still requires
/// additional `api_client` write methods over the existing server routes and
/// remains deferred to a follow-up pass, mirroring how Groups was phased in
/// this project.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

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
