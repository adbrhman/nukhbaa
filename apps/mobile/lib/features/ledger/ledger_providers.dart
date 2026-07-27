/// The Ledger **view** state — read-only providers over a participant's own
/// balance and entry stream (Core scope, mirrors `leaderboards_providers.dart`).
///
/// A ledger is a server-produced projection over the append-only `PointEntry`
/// stream (Axiom 5): this file builds no points logic of its own — it only
/// displays what `LedgerApi` returns. Ownership is enforced entirely
/// server-side (`ReadParticipantLedger`); a non-owned participant id is
/// refused `Err(authorization, code: ledger.participant_not_found)`, rethrown
/// here so the screen renders it via `ErrorPresenter`.
library;

import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'ledger_providers.g.dart';

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// `GET /participants/{participantId}/balance` — the participant's current
/// projected balance.
@riverpod
Future<BalanceDto> participantBalance(Ref ref, String participantId) async {
  final api = ref.watch(ledgerApiProvider);
  return _unwrap(await api.balanceOf(participantId));
}

/// `GET /participants/{participantId}/entries` — the participant's
/// append-only entry stream. An empty list is a legitimate result, never an
/// error.
@riverpod
Future<ParticipantEntriesDto> participantEntries(
  Ref ref,
  String participantId,
) async {
  final api = ref.watch(ledgerApiProvider);
  return _unwrap(await api.entriesOf(participantId));
}
