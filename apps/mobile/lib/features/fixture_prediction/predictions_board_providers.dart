/// The players' predictions board of a day in one request (2026-10-11):
/// `GET /seasons/{id}/predictions-board?fixtures=` answers, for every
/// started match, everyone's predictions, the scores and the reactions --
/// what the board used to ask for with three requests per match (63 for a
/// day of 21), which on 2026-10-10 held the server for over ten seconds.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// One board read: a season and its started fixtures of the day, in
/// kickoff order, comma separated (a record of strings compares by value).
typedef PredictionsBoardKey = ({String seasonId, String fixtureIds});

/// The board of [PredictionsBoardKey]. A passing failure (a timeout, a
/// 503) is asked again a little later, up to three times; a refusal is
/// shown at once.
final predictionsBoardProvider = FutureProvider.autoDispose
    .family<PredictionsBoardDto, PredictionsBoardKey>((ref, key) async {
      final api = ref.watch(predictionApiProvider);
      final result = await api.predictionsBoard(
        seasonId: key.seasonId,
        fixtureIds: key.fixtureIds.split(','),
      );
      return switch (result) {
        Ok<PredictionsBoardDto>(:final value) => value,
        Err<PredictionsBoardDto>(:final error) => throw error,
      };
    }, retry: predictionsBoardRetry);

/// The most fixtures one board read may ask for (the server's limit).
const int predictionsBoardMaxFixtures = 40;

/// The board read each of [fixtures] belongs to, by `seasonId/fixtureId`:
/// one per season, in the order given, split every
/// [predictionsBoardMaxFixtures] fixtures.
Map<String, PredictionsBoardKey> predictionsBoardKeys(
  List<SeasonFixtureCardDto> fixtures,
) {
  final Map<String, List<String>> bySeason = <String, List<String>>{};
  for (final SeasonFixtureCardDto fixture in fixtures) {
    final List<String> ids = bySeason.putIfAbsent(
      fixture.seasonId,
      () => <String>[],
    );
    if (!ids.contains(fixture.fixtureId)) ids.add(fixture.fixtureId);
  }
  final Map<String, PredictionsBoardKey> keys = <String, PredictionsBoardKey>{};
  for (final MapEntry<String, List<String>> season in bySeason.entries) {
    final List<String> ids = season.value;
    for (
      var start = 0;
      start < ids.length;
      start += predictionsBoardMaxFixtures
    ) {
      final int end = start + predictionsBoardMaxFixtures < ids.length
          ? start + predictionsBoardMaxFixtures
          : ids.length;
      final List<String> chunk = ids.sublist(start, end);
      final PredictionsBoardKey key = (
        seasonId: season.key,
        fixtureIds: chunk.join(','),
      );
      for (final String id in chunk) {
        keys['${season.key}/$id'] = key;
      }
    }
  }
  return keys;
}

/// When to ask for the board again after [error]: only a passing failure,
/// at most three times, two, four and six seconds later.
Duration? predictionsBoardRetry(int retryCount, Object error) {
  if (retryCount >= 3) return null;
  if (error is AppError && error.kind == ErrorKind.transient) {
    return Duration(seconds: 2 * (retryCount + 1));
  }
  return null;
}

/// Why a column of the board shows no predictions, in Arabic: the server's
/// refusal [code] for that match, or the whole read's [error].
String predictionsBoardErrorText(Object? error, String? code) {
  final String? reason = code ?? (error is AppError ? error.code : null);
  return switch (reason) {
    'prediction.fixture_not_started' => 'لم تبدأ المباراة بعد.',
    'prediction.fixture_unavailable' => 'هذه المباراة غير متاحة.',
    'prediction.fixture_not_in_season' => 'المباراة ليست ضمن هذا الشهر.',
    'prediction.not_a_participant' => 'لست مشاركاً في هذا الشهر.',
    _ => 'تعذّر تحميل التوقعات. اضغط لإعادة المحاولة.',
  };
}
