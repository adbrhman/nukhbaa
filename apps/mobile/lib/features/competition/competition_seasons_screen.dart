/// Browse level 2 — a competition's seasons
/// (`GET /competitions/{id}/seasons`).
///
/// Watches `competitionSeasonsProvider(competitionId)` and renders it via
/// [AsyncListView]. A competition with no seasons (or one that does not exist —
/// the browse read reveals no existence oracle) is a *legitimate* empty list,
/// shown as an empty affordance rather than an error. Selecting a season pushes
/// the round list ([SeasonRoundsScreen]).
///
/// A competition with **exactly one** season is a common case today (a single
/// "2026/27" season per competition) and forcing the user through an
/// intermediate list of one is pure friction. In that case this screen
/// auto-advances straight into [SeasonRoundsScreen] via [Navigator.pushReplacement]
/// — replacing itself in the stack so "back" from the rounds screen returns to
/// the competition list, not to a seasons screen the user never meaningfully
/// saw. Multiple seasons still render as a normal, tappable list.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'competition_providers.dart';
import 'season_rounds_screen.dart';
import 'widgets/async_list_view.dart';

/// The season-list screen for a single competition.
class CompetitionSeasonsScreen extends ConsumerStatefulWidget {
  /// Creates the seasons screen for [competitionId].
  const CompetitionSeasonsScreen({
    required this.competitionId,
    required this.competitionName,
    super.key,
  });

  /// The owning competition id whose seasons are listed.
  final String competitionId;

  /// The competition's display name (for the app bar; passed from level 1 so no
  /// extra fetch is needed just to title this screen).
  final String competitionName;

  @override
  ConsumerState<CompetitionSeasonsScreen> createState() =>
      _CompetitionSeasonsScreenState();
}

class _CompetitionSeasonsScreenState
    extends ConsumerState<CompetitionSeasonsScreen> {
  // Guards against scheduling the auto-advance more than once across
  // rebuilds (e.g. a provider re-emitting the same single-season list on
  // refresh) — pushReplacement must fire exactly once per screen instance.
  bool _autoAdvanced = false;

  void _maybeAutoAdvance(List<SeasonDto> seasons) {
    if (_autoAdvanced || seasons.length != 1) return;
    _autoAdvanced = true;
    final SeasonDto season = seasons.single;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SeasonRoundsScreen(
            seasonId: season.id,
            seasonLabel: season.label,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final seasons = ref.watch(competitionSeasonsProvider(widget.competitionId));
    seasons.whenData(_maybeAutoAdvance);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.competitionName, key: const Key('seasons.title')),
      ),
      body: AsyncListView<SeasonDto>(
        value: seasons,
        emptyMessage: l10n.competitionSeasonsEmpty,
        onRetry: () =>
            ref.invalidate(competitionSeasonsProvider(widget.competitionId)),
        itemBuilder: (context, season) => ListTile(
          key: Key('seasons.item.${season.id}'),
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text(season.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SeasonRoundsScreen(
                seasonId: season.id,
                seasonLabel: season.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
