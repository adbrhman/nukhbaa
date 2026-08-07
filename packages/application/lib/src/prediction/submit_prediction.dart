import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/prediction_repository.dart';
import 'package:application/src/prediction/prediction_view.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One fixture's predicted scoreline as it arrives from the client — a raw,
/// untrusted intent (Application ADR, Section 2: commands speak in domain
/// intents, validated server-side). The use-case turns each of these into a
/// validated [FixtureScorePrediction]; the client never constructs domain
/// value objects (Axioms 2/5).
final class FixtureScoreInput {
  /// Creates a raw fixture-score input.
  const FixtureScoreInput({
    required this.fixtureId,
    required this.homeGoals,
    required this.awayGoals,
    this.isDouble = false,
  });

  /// The referenced fixture id (untrusted; validated via [FixtureRef.tryParse]).
  final String fixtureId;

  /// The predicted goals for the home side (untrusted; range-checked by the
  /// domain value object).
  final int homeGoals;

  /// The predicted goals for the away side (untrusted; range-checked).
  final int awayGoals;

  /// Whether the caller marked this fixture as their round double (untrusted;
  /// the use-case enforces exactly one across the participant's full forecast).
  final bool isDouble;
}

/// Use-case: submit (or amend) a participant's prediction for a round
/// (Application ADR, Section 2: command intent `SubmitPrediction`).
///
/// This is the platform's highest-volume integrity-critical write, so the
/// Prediction aggregate is kept separate from Competition (Database ADR,
/// Sections 1 & 2.1). The principal predicts as *themselves*: the participant
/// is resolved server-side from the verified token and the round's season,
/// never from the request body, so a caller can never predict on someone
/// else's behalf (Security ADR, Section 2 / Axiom 2). Points are never accepted
/// or computed here — the client submits only intent (Axioms 2/5).
///
/// Business invariants enforced (in order):
/// 1. **Round is open.** Submitting/amending after lock is rejected — the
///    domain [Prediction.submit]/[Prediction.amend] guard is the primary check,
///    the migration's check constraint the backstop (Axiom 6). This is the
///    round's ADMIN-controlled gate (`LockRound`); it is independent of the
///    PER-FIXTURE kickoff lock below.
/// 2. **Every predicted fixture belongs to the round** (product decision,
///    2026-07-10): a score whose `FixtureRef` isn't among the round's
///    `RoundFixture` links is rejected `prediction.fixture_not_in_round`.
/// 3. **A fixture that has already kicked off cannot be written** (product
///    decision, 2026-07-xx — the double feature's fairness model): each
///    fixture locks individually the instant `FixtureSchedule.kickoffAt`
///    passes, independent of the round's admin-controlled open/locked status.
///    A submission naming an already-kicked-off fixture is rejected
///    `prediction.fixture_locked` — the caller must resubmit without it. A
///    fixture with no registered [FixtureSchedule] is treated as NOT locked
///    (there is no kickoff instant to compare against yet).
/// 4. **The forecast covers every currently-open fixture, exactly** (revised
///    from the original "covers the whole round" rule to accommodate #3): the
///    submitted fixture-id set must equal the round's OPEN fixtures exactly —
///    no missing open fixture, no extra, and no already-locked fixture — else
///    `prediction.incomplete_forecast`. Already-locked fixtures are NOT
///    required here: a participant joining after some fixtures kicked off is
///    never blocked from predicting the rest (fairness), and any fixture that
///    locked before they ever predicted it is simply graded `missed` (zero
///    points) at scoring time — never rejected here.
/// 5. **Exactly one fixture in the resulting full forecast must be the
///    double** (merging this submission's open-fixture scores with any
///    already-locked scores carried over from a prior submission): zero
///    doubles is rejected `prediction.double_not_selected`; more than one is
///    rejected by the domain aggregate itself (`prediction.multiple_doubles`)
///    when the merged list is handed to [Prediction.submit]/[Prediction.amend].
///
/// Already-locked fixtures from a prior submission are always carried over
/// unchanged (never overwritten, never dropped) — the caller only ever
/// resubmits the fixtures still open to them.
///
/// **Idempotent** (Application ADR, Section 2): a first call for a
/// `(round, participant)` inserts; a repeat call amends the existing prediction
/// in place (one row, Axiom 4). A concurrent duplicate insert that loses the
/// race converges by re-reading and amending.
///
/// Never throws; returns a typed [Result].
final class SubmitPrediction {
  /// Creates the use-case over its collaborators.
  const SubmitPrediction({
    required PredictionRepository predictionRepository,
    required CompetitionRepository competitionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _predictions = predictionRepository,
       _competition = competitionRepository,
       _fixtureSchedules = fixtureScheduleRepository,
       _idGenerator = idGenerator,
       _clock = clock;

  final PredictionRepository _predictions;
  final CompetitionRepository _competition;
  final FixtureScheduleRepository _fixtureSchedules;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Submits [scores] as [principal]'s prediction for round [roundId].
  ///
  /// On success returns a [PredictionView] carrying the persisted prediction
  /// **and** the exact UTC instant this call stamped it under (the clock read
  /// once below), so the edge can build a faithful versioned `PredictionDto`
  /// without ever fabricating a timestamp (Axioms 2/5).
  Future<Result<PredictionView>> call({
    required AuthenticatedUser principal,
    required String roundId,
    required List<FixtureScoreInput> scores,
  }) async {
    // Layer 1: any authenticated user may predict (social-first entry, Axiom 1).
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final roundIdResult = RoundId.tryParse(roundId);
    if (roundIdResult is Err<RoundId>) {
      return Result.err(roundIdResult.error);
    }
    final rId = (roundIdResult as Ok<RoundId>).value;

    // Load the round: it must exist and still be open.
    final roundResult = await _competition.findRound(rId);
    if (roundResult is Err<Round>) {
      return Result.err(roundResult.error);
    }
    final round = (roundResult as Ok<Round>).value;
    if (!round.status.isOpen) {
      return Result.err(
        AppError.invariant(
          'prediction.round_not_open',
          'Predictions can only be submitted while the round is open '
              '(round is ${round.status.wireValue})',
        ),
      );
    }

    // Resolve the caller's participant in this round's season. A user must have
    // joined the season before predicting; absence is a business precondition
    // failure, not a permission error.
    final participantResult = await _competition.findParticipant(
      round.seasonId,
      principal.userId,
    );
    if (participantResult is Err<Participant?>) {
      return Result.err(participantResult.error);
    }
    final participant = (participantResult as Ok<Participant?>).value;
    if (participant == null) {
      return const Result.err(
        AppError.invariant(
          'prediction.not_a_participant',
          'You must join the season before submitting a prediction',
        ),
      );
    }

    // Load the round's fixture composition (the completeness reference).
    final fixturesResult = await _predictions.listRoundFixtures(rId);
    if (fixturesResult is Err<List<RoundFixture>>) {
      return Result.err(fixturesResult.error);
    }
    final roundFixtures = (fixturesResult as Ok<List<RoundFixture>>).value;
    final requiredFixtureIds = <String>{
      for (final link in roundFixtures) link.fixture.value,
    };
    if (requiredFixtureIds.isEmpty) {
      return const Result.err(
        AppError.invariant(
          'prediction.round_has_no_fixtures',
          'The round has no fixtures to predict',
        ),
      );
    }

    // Rule 3 groundwork: resolve which of the round's fixtures have already
    // kicked off. A fixture with no registered schedule is treated as NOT
    // locked — there is no kickoff instant to compare the clock against yet.
    final schedulesResult = await _fixtureSchedules.findByFixtures([
      for (final link in roundFixtures) link.fixture,
    ]);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final schedules = (schedulesResult as Ok<List<FixtureSchedule>>).value;
    final now = _clock.nowUtc();
    final lockedFixtureIds = <String>{
      for (final schedule in schedules)
        if (!schedule.kickoffAt.isAfter(now)) schedule.fixture.value,
    };
    final openFixtureIds = requiredFixtureIds.difference(lockedFixtureIds);
    if (openFixtureIds.isEmpty) {
      return const Result.err(
        AppError.invariant(
          'prediction.no_open_fixtures',
          'Every fixture in this round has already kicked off',
        ),
      );
    }

    // Idempotency read, moved ahead of validation: needed both to carry over
    // already-locked scores (Rule 4) and to decide insert vs. amend below.
    final existingResult = await _predictions.findByRoundAndParticipant(
      rId,
      participant.id,
    );
    if (existingResult is Err<PredictionView?>) {
      return Result.err(existingResult.error);
    }
    final existing = (existingResult as Ok<PredictionView?>).value;
    final lockedScoresByFixture = <String, FixtureScorePrediction>{
      if (existing != null)
        for (final score in existing.prediction.scores)
          if (lockedFixtureIds.contains(score.fixture.value))
            score.fixture.value: score,
    };

    // Validate every raw score into a domain value object (range + shape).
    final domainScoresByFixture = <String, FixtureScorePrediction>{};
    final submittedFixtureIds = <String>{};
    for (final input in scores) {
      final fixtureResult = FixtureRef.tryParse(input.fixtureId);
      if (fixtureResult is Err<FixtureRef>) {
        return Result.err(fixtureResult.error);
      }
      final fixture = (fixtureResult as Ok<FixtureRef>).value;

      // Rule 2: the fixture must belong to the round.
      if (!requiredFixtureIds.contains(fixture.value)) {
        return Result.err(
          AppError.validation(
            'prediction.fixture_not_in_round',
            'Fixture ${fixture.value} is not part of this round',
          ),
        );
      }

      // Rule 3: a fixture that has already kicked off can never be written —
      // not its score, not its double flag. Rejected outright rather than
      // silently ignored, so a stale client can never overwrite a locked
      // fixture by accident.
      if (lockedFixtureIds.contains(fixture.value)) {
        return Result.err(
          AppError.invariant(
            'prediction.fixture_locked',
            'Fixture ${fixture.value} has already kicked off and can no '
                'longer be predicted',
          ),
        );
      }

      final scoreResult = FixtureScorePrediction.create(
        fixture: fixture,
        homeGoals: input.homeGoals,
        awayGoals: input.awayGoals,
        isDouble: input.isDouble,
      );
      if (scoreResult is Err<FixtureScorePrediction>) {
        return Result.err(scoreResult.error);
      }
      domainScoresByFixture[fixture.value] =
          (scoreResult as Ok<FixtureScorePrediction>).value;
      submittedFixtureIds.add(fixture.value);
    }

    // Rule 4: the submission must cover exactly the round's currently OPEN
    // fixtures — no missing open fixture (a duplicate would have shrunk this
    // set), no extra, and no locked fixture (excluded by Rule 3 above).
    if (submittedFixtureIds.length != openFixtureIds.length ||
        !submittedFixtureIds.containsAll(openFixtureIds)) {
      return const Result.err(
        AppError.validation(
          'prediction.incomplete_forecast',
          'A prediction must cover every currently open fixture in the '
              'round, exactly once',
        ),
      );
    }

    // Merge locked-carried-over scores with the newly-validated open scores,
    // in the round's own fixture order (Axiom 4: one forecast, stable order).
    // A fixture that locked before the participant ever predicted it is
    // simply absent here — it is graded `missed` at scoring time, never
    // rejected at submission time.
    final finalScores = <FixtureScorePrediction>[
      for (final link in roundFixtures)
        if (lockedScoresByFixture[link.fixture.value] case final locked?)
          locked
        else
          ?domainScoresByFixture[link.fixture.value],
    ];

    // Rule 5: exactly one double across the full merged forecast. The domain
    // aggregate itself rejects MORE than one when it validates `finalScores`
    // below; only the "zero selected" half needs checking here.
    final doubleCount = finalScores.where((s) => s.isDouble).length;
    if (doubleCount == 0) {
      return const Result.err(
        AppError.validation(
          'prediction.double_not_selected',
          'Select exactly one fixture as your double before submitting',
        ),
      );
    }

    if (existing != null) {
      return _amend(existing.prediction, round.status, finalScores, now);
    }
    return _insert(rId, participant.id, round.status, finalScores, now);
  }

  Future<Result<PredictionView>> _insert(
    RoundId roundId,
    ParticipantId participantId,
    RoundStatus roundStatus,
    List<FixtureScorePrediction> scores,
    DateTime now,
  ) async {
    final idResult = PredictionId.tryParse(_idGenerator.newUuid());
    if (idResult is Err<PredictionId>) {
      return Result.err(idResult.error);
    }

    final predictionResult = Prediction.submit(
      id: (idResult as Ok<PredictionId>).value,
      roundId: roundId,
      participantId: participantId,
      roundStatus: roundStatus,
      scores: scores,
    );
    if (predictionResult is Err<Prediction>) {
      return Result.err(predictionResult.error);
    }
    final prediction = (predictionResult as Ok<Prediction>).value;

    final saved = await _predictions.save(prediction, now);
    return switch (saved) {
      // The instant we stamped (`now`) is exactly the row's `submitted_at`.
      Ok<void>() => Result.ok(
        PredictionView(prediction: prediction, submittedAt: now),
      ),
      // A concurrent first submission won the race; converge by amending it.
      Err<void>(:final error) =>
        error.code == 'prediction.already_submitted'
            ? await _resolveConflictThenAmend(
                roundId,
                participantId,
                roundStatus,
                scores,
                now,
                error,
              )
            : Result.err(error),
    };
  }

  Future<Result<PredictionView>> _amend(
    Prediction existing,
    RoundStatus roundStatus,
    List<FixtureScorePrediction> scores,
    DateTime now,
  ) async {
    final amendedResult = existing.amend(
      roundStatus: roundStatus,
      scores: scores,
    );
    if (amendedResult is Err<Prediction>) {
      return Result.err(amendedResult.error);
    }
    final amended = (amendedResult as Ok<Prediction>).value;

    final updated = await _predictions.update(amended, now);
    return switch (updated) {
      // `update` refreshes `submitted_at` to `now` (Axiom 4: same row).
      Ok<void>() => Result.ok(
        PredictionView(prediction: amended, submittedAt: now),
      ),
      Err<void>(:final error) => Result.err(error),
    };
  }

  Future<Result<PredictionView>> _resolveConflictThenAmend(
    RoundId roundId,
    ParticipantId participantId,
    RoundStatus roundStatus,
    List<FixtureScorePrediction> scores,
    DateTime now,
    AppError insertError,
  ) async {
    final reread = await _predictions.findByRoundAndParticipant(
      roundId,
      participantId,
    );
    return switch (reread) {
      Ok<PredictionView?>(:final value) =>
        value != null
            ? await _amend(value.prediction, roundStatus, scores, now)
            : Result.err(insertError),
      Err<PredictionView?>(:final error) => Result.err(error),
    };
  }
}
