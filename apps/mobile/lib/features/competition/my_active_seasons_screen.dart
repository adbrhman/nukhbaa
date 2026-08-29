/// "My active seasons" -- every season the caller is an active participant
/// in right now (`GET /me/active-seasons`; docs/project-context.md, Axiom 4
/// Amendment). Tapping a season pushes [FixturePredictionScreen] directly,
/// the same target [CompetitionSeasonsScreen] pushes to.
///
/// A caller with no active participation yet (a brand-new user who has not
/// made a first prediction) sees a legitimate empty state, never an error --
/// there is deliberately no "browse competitions" CTA here yet: no
/// top-level competitions list screen exists in mobile today
/// (`competitionListProvider` is otherwise only consumed by the admin
/// picker), so wiring one is left out of scope for this batch rather than
/// improvised.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../fixture_prediction/fixture_prediction_screen.dart';
import 'competition_providers.dart';
import 'widgets/async_list_view.dart';

/// Lists the caller's active seasons across every competition.
class MyActiveSeasonsScreen extends ConsumerWidget {
  /// Creates the "my active seasons" screen.
  const MyActiveSeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final seasons = ref.watch(activeSeasonsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.myActiveSeasons,
          key: const Key('activeSeasons.title'),
        ),
      ),
      body: AsyncListView<ActiveSeasonDto>(
        value: seasons,
        emptyMessage: l10n.myActiveSeasonsEmpty,
        onRetry: () => ref.invalidate(activeSeasonsProvider),
        itemBuilder: (context, season) => ListTile(
          key: Key('activeSeasons.item.${season.seasonId}'),
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text(season.competitionName),
          subtitle: Text(season.seasonLabel),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FixturePredictionScreen(
                seasonId: season.seasonId,
                seasonLabel: season.seasonLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
