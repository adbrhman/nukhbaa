/// Browse level 4 — a round's fixtures (`GET /rounds/{id}` for the header +
/// `GET /rounds/{id}/fixtures` for the list).
///
/// The deepest hop of the browse navigation. Two reads compose here:
///   * `roundDetailProvider(roundId)` — the round header (sequence / status /
///     deadline / ruleset version). A missing round is `Err(invariant,
///     code: competition.round_not_found)`, rendered as a "not found" message.
///   * `roundFixturesProvider(roundId)` — the fixture links in display order. A
///     round with no fixtures (or one that does not exist) is a *legitimate*
///     empty list.
///
/// Browse-only: fixtures are shown as their stable ids in presentation order
/// (the fixture aggregate carries no competition ref — Axiom 3 — and the browse
/// contract exposes only the round↔fixture link). No prediction/submission
/// affordance appears here; Prediction is the next, separate screen.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_round_header.dart';
import '../../l10n/app_localizations.dart';
import '../prediction/prediction_screen.dart';
import 'competition_providers.dart';
import 'season_rounds_screen.dart' show roundStatusLabel;
import 'widgets/async_list_view.dart';

/// The fixture-list screen for a single round.
class RoundFixturesScreen extends ConsumerWidget {
  /// Creates the fixtures screen for [roundId].
  const RoundFixturesScreen({required this.roundId, super.key});

  /// The round whose fixtures (and header) are shown.
  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final round = ref.watch(roundDetailProvider(roundId));
    final fixtures = ref.watch(roundFixturesProvider(roundId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.roundFixturesTitle, key: const Key('fixtures.title')),
      ),
      body: Column(
        children: <Widget>[
          // The round header. A not-found round surfaces here (the fixtures
          // list below would otherwise just be a legitimate empty list).
          AsyncObjectView<RoundDto>(
            value: round,
            onRetry: () => ref.invalidate(roundDetailProvider(roundId)),
            builder: (context, r) => AppRoundHeader(
              key: const Key('fixtures.roundHeader'),
              round: r,
              statusLine: l10n.roundRulesLine(
                roundStatusLabel(l10n, r.status),
                r.rulesetVersion,
              ),
              trailing: r.status == 'open'
                  ? FilledButton.icon(
                      key: const Key('fixtures.predict'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PredictionScreen(roundId: r.id),
                        ),
                      ),
                      icon: const Icon(Icons.sports_soccer),
                      label: Text(l10n.predictRoundButton),
                    )
                  : null,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncListView<RoundFixtureCardDto>(
              value: fixtures,
              emptyMessage: l10n.roundFixturesEmpty,
              onRetry: () => ref.invalidate(roundFixturesProvider(roundId)),
              itemBuilder: (context, fixture) => ListTile(
                key: Key('fixtures.item.${fixture.fixtureId}'),
                leading: CircleAvatar(
                  child: Text('${fixture.displayOrder + 1}'),
                ),
                title: Text(l10n.fixtureItemTitle(fixture.fixtureId)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
