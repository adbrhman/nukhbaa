/// The current-month fixtures **read** state — a single flat feed across
/// every current-month competition/season (Monthly Competitions transition,
/// CONTINUITY.md section 3, item 5). Hand-written (non-generator) Riverpod
/// provider, mirroring `fixture_prediction_providers.dart`'s file doc for
/// the same "no Dart SDK to run build_runner" reasoning.
///
/// ## Wiring
/// All networking is the ratified `api_client` via [CompetitionApi]
/// (`core/providers.dart`'s `competitionApiProvider`); `apps/mobile` performs
/// no HTTP itself (ADR-002 §2.8).
///
/// ## Scope
/// [currentMonthFixturesProvider] is the only read this file owns:
/// `GET /feed/current-month-fixtures`, one entry per fixture across every
/// public competition's current-month season. Each entry already carries its
/// own `fixture.seasonId`, so the consuming screen needs no separate season
/// lookup before submitting a prediction.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// `GET /feed/current-month-fixtures` — every fixture across every public
/// competition's current-month season, in server-returned order.
///
/// No competitions, or no current-month season anywhere, is a *legitimate*
/// `Ok(<empty list>)` (mirrors `seasonFixturesProvider`). Any other failure
/// (authorization, transient) is rethrown as the typed [AppError] so the
/// watching widget receives it as `AsyncError` and renders it through
/// `ErrorPresenter`.
final currentMonthFixturesProvider =
    FutureProvider<List<CurrentMonthFixtureItemDto>>((ref) async {
      final api = ref.watch(competitionApiProvider);
      final result = await api.getCurrentMonthFixtures();
      return switch (result) {
        Ok<List<CurrentMonthFixtureItemDto>>(:final value) => value,
        Err<List<CurrentMonthFixtureItemDto>>(:final error) => throw error,
      };
    });
