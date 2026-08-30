/// The **current-month fixtures** read state — an annotation-based Riverpod
/// provider exposing the unified `GET /feed/current-month-fixtures` read
/// (every public competition's current-month fixtures, flattened into one
/// server-ordered list) for the unified mobile "Matches" screen that
/// replaces the Round-based feed for the regular user (Monthly Competitions
/// transition, CONTINUITY §3 item 5).
///
/// ## Wiring
/// All networking is the ratified `api_client` via [CompetitionApi]
/// (obtained from `core/providers.dart`'s `competitionApiProvider`);
/// `apps/mobile` performs no HTTP itself. This mirrors every other read in
/// `competition_providers.dart`/`prediction_providers.dart`: `Ok(value)` ->
/// the provider's data value (an empty list is a *legitimate* success, never
/// an error — no public competitions, none with a season covering "now", or
/// none of those seasons having a linked fixture are all a valid "nothing to
/// show" state, no existence oracle); `Err(error)` -> the provider throws the
/// typed [AppError] so the watching widget receives it as `AsyncError` and
/// renders it through `ErrorPresenter`.
///
/// ## Scope
/// Read-only. The submit path for each card is the existing, UNMODIFIED
/// `FixturePredictionController`/`fixture_prediction_submission.dart`
/// (keyed by `(seasonId, fixtureId)`, taken from the nested
/// `CurrentMonthFixtureItemDto.fixture` on each item) — this file owns no
/// mutation.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'current_month_fixtures_providers.g.dart';

/// `GET /feed/current-month-fixtures` — every public competition's
/// current-month fixtures, flattened into one server-ordered list.
///
/// No public competitions, none with a season currently covering "now", or
/// none of those seasons having a linked fixture are all a legitimate
/// `Ok(<empty list>)` (no existence oracle); any other failure is rethrown as
/// the typed [AppError].
@riverpod
Future<List<CurrentMonthFixtureItemDto>> currentMonthFixtures(Ref ref) async {
  final api = ref.watch(competitionApiProvider);
  final result = await api.getCurrentMonthFixtures();
  return switch (result) {
    Ok<List<CurrentMonthFixtureItemDto>>(:final value) => value,
    Err<List<CurrentMonthFixtureItemDto>>(:final error) => throw error,
  };
}
