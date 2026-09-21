/// The favorite-teams page (plan P3-1): up to three teams the player follows,
/// read from and written to `/me/favorite-teams`, chosen from the team
/// catalog (`GET /teams`).
///
/// Like the notification switches, the server is the record: each tap
/// writes the whole set and the page shows what the server answered. A write
/// that fails leaves the selection where it was, with a message.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../competition/teams_providers.dart';
import '../competition/widgets/async_list_view.dart';

/// `GET /me/favorite-teams` -- the caller's teams, empty if none chosen.
final favoriteTeamsProvider = FutureProvider.autoDispose<FavoriteTeamsDto>((
  ref,
) async {
  final api = ref.watch(authApiProvider);
  return switch (await api.myFavoriteTeams()) {
    Ok<FavoriteTeamsDto>(:final value) => value,
    Err<FavoriteTeamsDto>(:final error) => throw error,
  };
});

/// The most teams a player may follow; the server refuses more.
const int maxFavoriteTeams = 3;

/// The favorite-teams page.
class FavoriteTeamsScreen extends ConsumerStatefulWidget {
  /// Creates the page.
  const FavoriteTeamsScreen({super.key});

  @override
  ConsumerState<FavoriteTeamsScreen> createState() =>
      _FavoriteTeamsScreenState();
}

class _FavoriteTeamsScreenState extends ConsumerState<FavoriteTeamsScreen> {
  /// What the last successful write stored; null until one succeeds, when
  /// the page shows what the read answered.
  List<String>? _stored;

  /// True while a write is in flight: every box is disabled so two taps
  /// cannot race each other to the server.
  bool _saving = false;

  String _query = '';

  Future<void> _toggle(List<String> current, String teamId) async {
    final List<String> next = current.contains(teamId)
        ? <String>[
            for (final id in current)
              if (id != teamId) id,
          ]
        : <String>[...current, teamId];
    setState(() => _saving = true);
    final Result<FavoriteTeamsDto> result = await ref
        .read(authApiProvider)
        .updateFavoriteTeams(teamIds: next);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok<FavoriteTeamsDto>(:final value):
        setState(() {
          _stored = value.teamIds;
          _saving = false;
        });
      case Err<FavoriteTeamsDto>():
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).notificationSettingsSaveFailed,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.favoriteTeamsTitle,
          key: const Key('favoriteTeams.title'),
        ),
      ),
      body: AsyncObjectView<FavoriteTeamsDto>(
        value: ref.watch(favoriteTeamsProvider),
        onRetry: () => ref.invalidate(favoriteTeamsProvider),
        builder: (context, favorites) => AsyncObjectView<List<TeamDto>>(
          value: ref.watch(teamCatalogProvider),
          onRetry: () => ref.invalidate(teamCatalogProvider),
          builder: (context, catalog) => _body(context, favorites, catalog),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    FavoriteTeamsDto favorites,
    List<TeamDto> catalog,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final List<String> chosen = _stored ?? favorites.teamIds;
    final bool full = chosen.length >= maxFavoriteTeams;
    final String query = _query.trim().toLowerCase();
    final List<TeamDto> shown =
        <TeamDto>[
          for (final team in catalog)
            if (query.isEmpty || team.name.toLowerCase().contains(query)) team,
        ]..sort((a, b) {
          final int aRank = chosen.contains(a.id) ? 0 : 1;
          final int bRank = chosen.contains(b.id) ? 0 : 1;
          return aRank != bRank ? aRank - bRank : a.name.compareTo(b.name);
        });
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            full ? l10n.favoriteTeamsLimitReached : l10n.favoriteTeamsHint,
            key: const Key('favoriteTeams.hint'),
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TextField(
            key: const Key('favoriteTeams.search'),
            decoration: InputDecoration(
              hintText: l10n.favoriteTeamsSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final TeamDto team = shown[index];
              final bool on = chosen.contains(team.id);
              return CheckboxListTile(
                key: Key('favoriteTeams.team.${team.id}'),
                value: on,
                title: Text(team.name),
                onChanged: _saving || (!on && full)
                    ? null
                    : (_) => _toggle(chosen, team.id),
              );
            },
          ),
        ),
      ],
    );
  }
}
