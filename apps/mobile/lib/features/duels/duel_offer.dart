/// "Challenge a friend" after a saved prediction, without touching the
/// match card's layout: once per fixture per session, a snack bar offers
/// the challenge sheet when the fixture is still far enough from kickoff
/// for the server to accept a challenge (30 minutes, migration 0090).
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'create_duel_sheet.dart';
import 'duels_providers.dart';

/// The lead the server requires, plus a minute so the offer is never made
/// for a challenge it would refuse a moment later.
const Duration duelOfferLead = Duration(minutes: 31);

/// Offers a challenge on [fixture] right after the caller's prediction for
/// it was saved. Queued behind any message already showing, never over it.
void offerDuelAfterSave({
  required BuildContext context,
  required WidgetRef ref,
  required SeasonFixtureCardDto fixture,
  DateTime? now,
}) {
  final String? kickoff = fixture.kickoffAt;
  final DateTime? kickoffAt = kickoff == null
      ? null
      : DateTime.tryParse(kickoff)?.toUtc();
  if (kickoffAt == null) return;
  final DateTime current = (now ?? DateTime.now()).toUtc();
  if (!kickoffAt.isAfter(current.add(duelOfferLead))) return;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  final NavigatorState? navigator = Navigator.maybeOf(context);
  if (messenger == null || navigator == null) return;
  if (!ref.read(duelOfferLogProvider.notifier).claim(fixture.fixtureId)) {
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      key: Key('duelOffer.${fixture.fixtureId}'),
      duration: const Duration(seconds: 6),
      // A button inside the content rather than a SnackBarAction: an
      // action can keep the bar on screen until it is pressed, and this
      // offer must never hold back the messages queued behind it.
      content: Row(
        children: <Widget>[
          const Expanded(child: Text('توقعت المباراة ✅ تحدَّ صديقك عليها ⚔️')),
          TextButton(
            key: Key('duelOffer.${fixture.fixtureId}.open'),
            onPressed: () {
              messenger.hideCurrentSnackBar();
              unawaited(
                showCreateDuelSheet(
                  context: navigator.context,
                  seasonId: fixture.seasonId,
                  fixtureId: fixture.fixtureId,
                  homeTeam: fixture.homeTeam ?? '',
                  awayTeam: fixture.awayTeam ?? '',
                ),
              );
            },
            child: const Text('تحدَّ'),
          ),
        ],
      ),
    ),
  );
}
