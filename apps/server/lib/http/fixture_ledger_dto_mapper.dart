import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects the fixture-scoped Ledger read values onto their versioned wire
/// shapes (API ADR §4; docs/project-context.md, Axiom 4 Amendment — the
/// per-fixture sibling of `ledger_dto_mapper.dart`).

/// Projects one immutable [FixturePointEntry] onto the wire
/// [FixturePointEntryDto].
FixturePointEntryDto fixturePointEntryToDto(FixturePointEntry entry) {
  return FixturePointEntryDto(
    id: entry.id.value,
    participantId: entry.participantId.value,
    fixtureId: entry.fixture.value,
    kind: entry.kind.wireValue,
    amount: entry.amount,
    sourceRef: entry.sourceRef,
    occurredAt: entry.occurredAt.toUtc().toIso8601String(),
  );
}

/// Shapes the response of `POST /fixtures/{id}/ledger` — the fixture posted
/// plus the entries this post actually appended. An **empty** list means the
/// fixture was already fully posted (idempotent replay — Axiom 4).
Map<String, Object?> postFixtureToLedgerResponseJson(
  String fixtureId,
  List<FixturePointEntry> appendedEntries,
) {
  return PostFixtureToLedgerResponseDto(
    fixtureId: fixtureId,
    appendedEntries: [
      for (final entry in appendedEntries) fixturePointEntryToDto(entry),
    ],
  ).toJson();
}
