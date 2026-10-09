/// The fixture-prediction **submit** controller — a hand-written
/// (non-generator) Riverpod family notifier that owns the
/// [FixtureSubmissionState] lifecycle for a single `(seasonId, fixtureId)`
/// pair (Axiom 4 Amendment — the per-fixture successor of the retired
/// round-level submit controller).
///
/// ## Why no `@riverpod` codegen here
/// See `fixture_prediction_providers.dart`'s file doc: this slice was
/// written by hand (manual `FamilyNotifier` + `NotifierProvider.family`,
/// mirroring `theme_controller.dart`'s single-instance `Notifier` pattern)
/// because it was built with no Dart SDK available to run
/// `build_runner build` and verify a generated `.g.dart`. It performs
/// identically to a `@riverpod` version and can be converted later as a pure
/// refactor.
///
/// ## Responsibility
/// This is the ONLY place `apps/mobile` triggers a fixture-prediction
/// *write*. It drives the sealed [FixtureSubmissionState]
/// (`Idle → InFlight → Succeeded | Failed`) through
/// `PredictionApi.submitFixturePrediction`, one call per command, a newer
/// one waiting behind the one in flight (from the ratified `api_client`,
/// obtained via `core/providers.dart`'s `predictionApiProvider`); the app
/// performs no HTTP itself (ADR-002 §2.8). Widgets never touch `api_client`
/// or branch on raw codes — they watch this controller and call [submit] /
/// [reset].
///
/// ## One fixture, one call (Axiom 4 Amendment)
/// Unlike the round-based controller, there is no batch: [submit] sends
/// exactly one fixture's `homeGoals`/`awayGoals`/`isDouble` per call. NO
/// points, participant id, or computed value is ever sent or fabricated
/// client-side: the participant is resolved server-side from the verified
/// principal, and points are a Scoring/Ledger concern. Server-side rules
/// (fixture belongs to the season, participant, fixture-not-locked, at most
/// one double per participant per UTC day) are enforced by
/// `SubmitFixturePrediction` in `apps/server` — this controller does not
/// re-implement them; it surfaces their typed failures.
///
/// ## Auto-join on first prediction (Axiom 1, social-first)
/// A user may predict without an explicit prior "join" step: if the server
/// refuses the submit with `prediction.not_a_participant`, this controller
/// transparently calls `CompetitionApi.joinCompetition(seasonId)` (the
/// season id is already known — it is part of this notifier's family key,
/// unlike the round-based controller which had to resolve it from the round
/// first), then retries the SAME submit exactly once with the identical
/// scoreline. If the join itself fails, that error is surfaced instead (it
/// is the more actionable failure).
///
/// ## Failure keeps the fixture editable
/// Any `Err` (a `409` locked fixture / daily-double cap → `invariant`; a
/// network/`503` → `transient`) becomes [FixtureSubmissionFailed] carrying
/// the typed [AppError]. The screen renders it via `ErrorPresenter` and
/// keeps the fixture editable so the user can correct and retry; the
/// controller never clears the user's input.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import 'fixture_prediction_submission.dart';

/// The stable server code meaning "the caller has not joined this season
/// yet". Exposed as a constant so the auto-join retry below and any test
/// reference the exact same token the server produces (shared with
/// `prediction_controller.dart`'s identical constant for the round flow).
const String fixturePredictionNotAParticipantCode =
    'prediction.not_a_participant';

/// The family key identifying one fixture's submit lifecycle: the season it
/// belongs to (needed for both the submit call and the auto-join retry) plus
/// the fixture itself.
typedef FixturePredictionKey = ({String seasonId, String fixtureId});

/// One submit: what [FixturePredictionController.submit] sends.
typedef _FixtureCommand = ({int homeGoals, int awayGoals, bool isDouble});

/// Owns and mutates the [FixtureSubmissionState] for one
/// `(seasonId, fixtureId)` pair.
///
/// A family notifier: the submit lifecycle of one fixture is independent of
/// any other, including other fixtures in the same season. The initial
/// state is [FixtureSubmissionIdle].
class FixturePredictionController extends Notifier<FixtureSubmissionState> {
  /// Creates the controller for [arg] (the fixture this instance owns).
  FixturePredictionController(this.arg);

  /// The `(seasonId, fixtureId)` pair this controller instance owns
  /// (Riverpod 3.x removed `FamilyNotifier`; the family argument is now a
  /// plain constructor parameter, matching the pattern used elsewhere in
  /// this app).
  final FixturePredictionKey arg;

  PredictionApi get _api => ref.read(predictionApiProvider);
  CompetitionApi get _competitionApi => ref.read(competitionApiProvider);

  @override
  FixtureSubmissionState build() => const FixtureSubmissionIdle();

  /// The command on the wire, and the newest one asked for while it was
  /// there (see [submit]).
  _FixtureCommand? _sending;
  _FixtureCommand? _waiting;

  /// Submits (or idempotently amends) the caller's prediction for this
  /// controller's fixture with the given [homeGoals]/[awayGoals]/[isDouble].
  ///
  /// Transitions `→ InFlight` for the duration of the call (including a
  /// possible auto-join + retry, see class doc), then `→ Succeeded(prediction)`
  /// on a `200` or `→ Failed(error)` on any typed failure.
  ///
  /// Latest wins. A call made while a submit is in flight is not sent
  /// at once, and it is not dropped either: it waits, a newer call replaces
  /// it, and it goes out as soon as the one in flight lands. Dropping it
  /// lost the player's newest score whenever the server took longer than
  /// the card's retry budget (about a second): the card showed 2-1 while
  /// the server kept 2-0. Asking again for the command already in flight
  /// sends nothing more, so a double tap is still one request. The state
  /// stays InFlight until the last waiting command has its answer, and that
  /// answer becomes the state.
  Future<void> submit({
    required int homeGoals,
    required int awayGoals,
    bool isDouble = false,
  }) async {
    final _FixtureCommand command = (
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    );
    if (state is FixtureSubmissionInFlight) {
      _waiting = command == _sending ? null : command;
      return;
    }

    state = const FixtureSubmissionInFlight();

    _FixtureCommand next = command;
    _FixtureCommand? waiting;
    Result<FixturePredictionDto> result;
    do {
      _sending = next;
      result = await _send(next);
      waiting = _waiting;
      _waiting = null;
      if (waiting != null) next = waiting;
    } while (waiting != null && ref.mounted);
    _sending = null;

    // The container can go while a request is out (sign-out replaces it):
    // nobody is left to tell.
    if (!ref.mounted) return;
    state = switch (result) {
      Ok<FixturePredictionDto>(:final value) => FixtureSubmissionSucceeded(
        value,
      ),
      Err<FixturePredictionDto>(:final error) => FixtureSubmissionFailed(error),
    };
  }

  /// Sends one [command], joining the season first when the server says the
  /// caller has not joined it yet.
  Future<Result<FixturePredictionDto>> _send(_FixtureCommand command) async {
    final seasonId = arg.seasonId;
    final fixtureId = arg.fixtureId;

    Result<FixturePredictionDto> result = await _api.submitFixturePrediction(
      seasonId: seasonId,
      fixtureId: fixtureId,
      homeGoals: command.homeGoals,
      awayGoals: command.awayGoals,
      isDouble: command.isDouble,
    );

    // Auto-join on first prediction (Axiom 1, social-first): the caller has
    // never joined this season. Join, then retry the SAME submit exactly
    // once with the identical scoreline.
    if (result case Err<FixturePredictionDto>(
      :final error,
    ) when error.code == fixturePredictionNotAParticipantCode) {
      if (!ref.mounted) return result;
      final joinResult = await _competitionApi.joinCompetition(seasonId);
      if (joinResult is Err<ParticipantDto>) {
        return Result.err(joinResult.error);
      }
      if (!ref.mounted) return result;
      result = await _api.submitFixturePrediction(
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: command.homeGoals,
        awayGoals: command.awayGoals,
        isDouble: command.isDouble,
      );
    }
    return result;
  }

  /// Returns the controller to [FixtureSubmissionIdle] (e.g. after the user
  /// dismisses a success confirmation, or to clear a prior failure before
  /// editing again). A no-op while a submit is [FixtureSubmissionInFlight] —
  /// an attempt in flight is not silently discarded.
  void reset() {
    if (state is FixtureSubmissionInFlight) {
      return;
    }
    state = const FixtureSubmissionIdle();
  }
}

/// The provider exposing [FixturePredictionController], keyed by
/// [FixturePredictionKey] (one instance per fixture).
final fixturePredictionControllerProvider =
    NotifierProvider.family<
      FixturePredictionController,
      FixtureSubmissionState,
      FixturePredictionKey
    >(FixturePredictionController.new);
