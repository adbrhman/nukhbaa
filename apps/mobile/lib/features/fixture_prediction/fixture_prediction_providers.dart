/// The fixture-prediction **read** state — hand-written (non-generator)
/// Riverpod providers exposing a season's fixture list for the new
/// per-fixture predict flow (Axiom 4 Amendment).
///
/// ## Why no `@riverpod` codegen here
/// Every other read/controller pair in `apps/mobile` uses the
/// `riverpod_annotation` generator (see `prediction_providers.dart`). This
/// slice was deliberately written by hand instead: it was built in a sandbox
/// with no Dart SDK to run `dart run build_runner build`, so a generator
/// annotation here would have shipped an unverified `.g.dart` stub. The
/// manual `FutureProvider.family` below needs no generated glue and is
/// exactly what the generator would have produced. It can be converted to
/// `@riverpod` later with a normal build_runner pass if desired — that is a
/// pure refactor, not a behavior change.
///
/// ## Wiring
/// All networking is the ratified `api_client` via [CompetitionApi]
/// (obtained from `core/providers.dart`'s `competitionApiProvider`, the same
/// client the Competition browse slice already uses); `apps/mobile` performs
/// no HTTP itself.
///
/// ## Scope
/// [seasonFixturesProvider] is the only read this file owns: the season's
/// linked fixtures (`GET /seasons/{id}/fixtures`), each carrying only its
/// identity (`seasonId`/`fixtureId`) plus schedule (`homeTeam`/`awayTeam`/
/// `kickoffAt`) when registered. There is deliberately no "my prediction for
/// this fixture" read here — the server does not expose one yet (only the
/// `POST .../prediction` submit endpoint exists as of Phase 7.2), so the
/// fixture-prediction screen submits blind, with no pre-fill, until that read
/// is added.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// `GET /seasons/{id}/fixtures` — every fixture linked to season [seasonId],
/// in server-returned order.
///
/// A season with no linked fixtures — or one that does not exist — is a
/// *legitimate* `Ok(<empty list>)` (the server reveals no existence oracle on
/// this browse read; mirrors `seasonRoundsProvider`/`roundFixturesProvider`).
/// Any other failure (authorization, transient) is rethrown as the typed
/// [AppError] so the watching widget receives it as `AsyncError` and renders
/// it through `ErrorPresenter`.
final seasonFixturesProvider =
    FutureProvider.family<List<SeasonFixtureCardDto>, String>((
      ref,
      seasonId,
    ) async {
      final api = ref.watch(competitionApiProvider);
      final result = await api.browseSeasonFixtures(seasonId);
      return switch (result) {
        Ok<List<SeasonFixtureCardDto>>(:final value) => value,
        Err<List<SeasonFixtureCardDto>>(:final error) => throw error,
      };
    });
