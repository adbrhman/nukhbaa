/// Where the viewer stands while their matches are in play (phase 5 of the
/// plan: the match is live inside the app).
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// How often a watched standing is read again: the server's running scores
/// follow the provider's poll, about a minute apart.
const Duration liveStandingRefresh = Duration(seconds: 60);

/// `GET /seasons/{id}/live`, read again every [liveStandingRefresh] while
/// something watches it. A failed read shows nothing rather than retrying
/// behind it: the card is an extra, never the score.
final liveStandingProvider = FutureProvider.autoDispose
    .family<LiveStandingDto, String>((ref, seasonId) async {
      final Timer again = Timer(liveStandingRefresh, ref.invalidateSelf);
      ref.onDispose(again.cancel);
      final api = ref.watch(leaderboardsApiProvider);
      final result = await api.seasonLive(seasonId);
      return switch (result) {
        Ok<LiveStandingDto>(:final value) => value,
        Err<LiveStandingDto>(:final error) => throw error,
      };
    }, retry: (_, _) => null);
