/// "Which team do you support?" right after a saved prediction (phase 2 of
/// the plan: favourite teams are asked at the first prediction, not hidden
/// in the settings). Once per session, only for a player with no favourite
/// team yet, a bar offers the two teams of the match just predicted; one
/// tap makes it their team. More teams stay in the settings page.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import '../competition/team_registry.dart';

/// Whether this session already offered (or checked) the favourite team.
class FavoriteTeamOffer extends Notifier<bool> {
  @override
  bool build() => false;

  /// True only the first time.
  bool claim() {
    if (state) return false;
    state = true;
    return true;
  }
}

/// See [FavoriteTeamOffer].
final favoriteTeamOfferProvider = NotifierProvider<FavoriteTeamOffer, bool>(
  FavoriteTeamOffer.new,
);

/// Offers [fixture]'s two teams as the player's favourite, when they have
/// none. Queued behind any message already showing, never over it.
Future<void> offerFavoriteTeamAfterSave({
  required BuildContext context,
  required WidgetRef ref,
  required SeasonFixtureCardDto fixture,
}) async {
  final String? homeId = fixture.homeTeamId;
  final String? awayId = fixture.awayTeamId;
  if (homeId == null || awayId == null) return;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (!ref.read(favoriteTeamOfferProvider.notifier).claim()) return;
  final AuthApi api = ref.read(authApiProvider);
  final Result<FavoriteTeamsDto> current = await api.myFavoriteTeams();
  if (current is! Ok<FavoriteTeamsDto> || current.value.teamIds.isNotEmpty) {
    return;
  }

  Future<void> choose(String teamId, String name) async {
    messenger.hideCurrentSnackBar();
    final Result<FavoriteTeamsDto> saved = await api.updateFavoriteTeams(
      teamIds: <String>[teamId],
    );
    messenger.showSnackBar(
      SnackBar(
        key: const Key('favoriteOffer.done'),
        content: Text(
          saved.isOk
              ? 'صار $name فريقك المفضل.'
              : 'تعذّر الحفظ. اختر فريقك من الإعدادات.',
        ),
      ),
    );
  }

  final String home = teamDisplayName(fixture.homeTeam);
  final String away = teamDisplayName(fixture.awayTeam);
  messenger.showSnackBar(
    SnackBar(
      key: const Key('favoriteOffer'),
      duration: const Duration(seconds: 8),
      content: Row(
        children: <Widget>[
          const Expanded(child: Text('أيّ فريق تشجّع؟')),
          TextButton(
            key: const Key('favoriteOffer.home'),
            onPressed: () => unawaited(choose(homeId, home)),
            child: Text(home),
          ),
          TextButton(
            key: const Key('favoriteOffer.away'),
            onPressed: () => unawaited(choose(awayId, away)),
            child: Text(away),
          ),
        ],
      ),
    ),
  );
}
