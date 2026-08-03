/// Browse level 1 — the public competition catalogue (`GET /competitions`).
///
/// Watches `competitionListProvider` and renders it via [AsyncListView]
/// (loading / error / legitimate-empty / data). Selecting a competition pushes
/// the season list ([CompetitionSeasonsScreen]) for that competition — the first
/// step of the browse drill-down. This screen is read-only (Core scope: browse
/// only) and performs no HTTP itself; all data comes through the ratified
/// `api_client` behind `competitionListProvider`.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

import 'competition_providers.dart';
import 'competition_seasons_screen.dart';
import 'widgets/async_list_view.dart';

/// The top-level competition catalogue screen.
class CompetitionListScreen extends ConsumerWidget {
  /// Creates the competition list screen.
  const CompetitionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final competitions = ref.watch(competitionListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.competitions, key: const Key('competitions.title')),
      ),
      body: AsyncListView<CompetitionDto>(
        value: competitions,
        emptyMessage: l10n.competitionsEmpty,
        onRetry: () => ref.invalidate(competitionListProvider),
        itemBuilder: (context, competition) => ListTile(
          key: Key('competitions.item.${competition.id}'),
          leading: const Icon(Icons.emoji_events_outlined),
          title: Text(competition.name),
          subtitle: Text(
            '${_formatLabel(competition.format)} · '
            '${_visibilityLabel(competition.visibility, l10n)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CompetitionSeasonsScreen(
                competitionId: competition.id,
                competitionName: competition.name,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Humanises a format token (e.g. `football_scoreline` → "Football scoreline").
String _formatLabel(String token) {
  if (token.isEmpty) return token;
  final words = token.split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return token;
  final first = words.first;
  final head = '${first[0].toUpperCase()}${first.substring(1)}';
  return <String>[head, ...words.skip(1)].join(' ');
}

/// Humanises a visibility token.
String _visibilityLabel(String token, AppLocalizations l10n) => switch (token) {
  'public' => l10n.visibilityPublic,
  'private' => l10n.visibilityPrivate,
  _ => token,
};
