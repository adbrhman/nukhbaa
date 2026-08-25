/// The client's fixture-prediction **submission** state — the per-fixture
/// sibling of `prediction_submission.dart`'s [SubmissionState] (Axiom 4
/// Amendment: a fixture prediction is submitted independently, not as part of
/// a round-wide batch, so its lifecycle is tracked one fixture at a time
/// instead of once per round).
///
///   * [FixtureSubmissionIdle]      — no attempt in flight; the fixture's
///     score fields are editable.
///   * [FixtureSubmissionInFlight]  — a `POST
///     /seasons/{id}/fixtures/{fixtureId}/prediction` is running; the screen
///     disables that fixture's inputs.
///   * [FixtureSubmissionSucceeded] — the server accepted (or idempotently
///     amended) the prediction; carries the stored [FixturePredictionDto] so
///     the screen can confirm what was saved.
///   * [FixtureSubmissionFailed]    — the attempt produced a typed
///     [AppError], presented via `ErrorPresenter`; the fixture stays
///     editable so the user can correct and retry.
///
/// The sealed hierarchy lets the analyzer enforce exhaustive `switch` in the
/// screen (Coding Standards ADR §4 — illegal states unrepresentable). No
/// points ever appear here (Axioms 2/5): a submission carries only the
/// user's intent and echoes back the stored prediction.
library;

import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Base type of every fixture-submission state. Sealed so callers must
/// handle each case.
sealed class FixtureSubmissionState {
  const FixtureSubmissionState();
}

/// No submission attempt has been made yet for this fixture (or it was
/// reset). The score fields are editable and the submit affordance is
/// enabled.
final class FixtureSubmissionIdle extends FixtureSubmissionState {
  /// Creates the idle state.
  const FixtureSubmissionIdle();

  @override
  bool operator ==(Object other) => other is FixtureSubmissionIdle;

  @override
  int get hashCode => (FixtureSubmissionIdle).hashCode;
}

/// A submit/amend request for this fixture is in flight. The UI shows
/// progress and disables this fixture's score inputs and submit affordance
/// so the user cannot fire a second overlapping request.
final class FixtureSubmissionInFlight extends FixtureSubmissionState {
  /// Creates the in-flight state.
  const FixtureSubmissionInFlight();

  @override
  bool operator ==(Object other) => other is FixtureSubmissionInFlight;

  @override
  int get hashCode => (FixtureSubmissionInFlight).hashCode;
}

/// The server accepted the prediction for this fixture (a first submission
/// or an idempotent amendment — one row per `(fixture, participant)`,
/// Axiom 4 Amendment). Carries the stored [prediction] so the screen can
/// confirm exactly what was saved.
final class FixtureSubmissionSucceeded extends FixtureSubmissionState {
  /// Creates a succeeded state carrying the stored [prediction].
  const FixtureSubmissionSucceeded(this.prediction);

  /// The stored prediction the server returned (echoed intent, no points).
  final FixturePredictionDto prediction;

  @override
  bool operator ==(Object other) =>
      other is FixtureSubmissionSucceeded && other.prediction == prediction;

  @override
  int get hashCode => prediction.hashCode;
}

/// The last submit attempt for this fixture failed. Carries the typed
/// [error] so the screen can render a message via `ErrorPresenter` (e.g.
/// the fixture already kicked off, the daily-double cap, not a participant,
/// network) and keep the fixture editable for a correction or retry.
final class FixtureSubmissionFailed extends FixtureSubmissionState {
  /// Creates a failed state carrying [error].
  const FixtureSubmissionFailed(this.error);

  /// The typed failure from the submit attempt.
  final AppError error;

  @override
  bool operator ==(Object other) =>
      other is FixtureSubmissionFailed && other.error == error;

  @override
  int get hashCode => error.hashCode;
}
