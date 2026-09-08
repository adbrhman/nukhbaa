/// The caller's own season-by-season record -- the single read behind both
/// the championship record list and the elite card.
///
/// Hand-written rather than `@riverpod`-generated, following
/// `currentMonthFixturesProvider`: one unparameterised future needs no
/// generated family, and a generated part file would make this feature depend
/// on a build_runner pass to compile at all.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// `GET /me/seasons`, newest season first as the server orders it.
///
/// A caller who has never scored yields an empty list -- a legitimate "no
/// record yet", rendered as an empty affordance rather than an error. Any
/// other failure is rethrown as the typed [AppError] so the watching widget
/// renders it through `ErrorPresenter`.
final mySeasonRecordsProvider = FutureProvider<List<MySeasonRecordDto>>((
  ref,
) async {
  final api = ref.watch(leaderboardsApiProvider);
  final result = await api.mySeasons();
  return switch (result) {
    Ok<List<MySeasonRecordDto>>(:final value) => value,
    Err<List<MySeasonRecordDto>>(:final error) => throw error,
  };
});
