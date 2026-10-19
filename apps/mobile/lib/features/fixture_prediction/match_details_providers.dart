library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// `GET /fixtures/{id}/details` — the story of a finished match for its
/// details page (script 118). Dropped when the page closes, so a match whose
/// details were not in yet is asked for again the next time it opens. A
/// failure is rethrown as the typed [AppError] for `ErrorPresenter`.
final matchDetailsProvider = FutureProvider.autoDispose
    .family<MatchDetailsDto, String>((ref, String fixtureId) async {
      final api = ref.watch(competitionApiProvider);
      final result = await api.getMatchDetails(fixtureId);
      return switch (result) {
        Ok<MatchDetailsDto>(:final value) => value,
        Err<MatchDetailsDto>(:final error) => throw error,
      };
    });
