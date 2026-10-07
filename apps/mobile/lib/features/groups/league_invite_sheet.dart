/// Inviting to a friends' league (decided 2026-10-07): by the link, as
/// before, or by finding a player by name in the app. A player invited by
/// name is told in the inbox and by push, and accepts or declines there
/// (migration 0097).
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/design/app_typography.dart';
import '../../core/providers.dart';
import '../duels/duels_providers.dart';
import 'league_invite.dart';

/// Opens the invitation sheet for [group].
Future<void> showLeagueInviteSheet(BuildContext context, GroupDto group) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LeagueInviteSheet(group: group),
    );

/// Where one player of the search stands.
enum _Invite { sending, sent, already, member, failed }

/// The sheet body; public so a widget test can find it.
class LeagueInviteSheet extends ConsumerStatefulWidget {
  /// Creates the sheet for [group].
  const LeagueInviteSheet({required this.group, super.key});

  /// The league invited to.
  final GroupDto group;

  @override
  ConsumerState<LeagueInviteSheet> createState() => _LeagueInviteSheetState();
}

class _LeagueInviteSheetState extends ConsumerState<LeagueInviteSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;
  List<DuelPlayerDto> _players = const <DuelPlayerDto>[];
  final Map<String, _Invite> _invites = <String, _Invite>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Searches once typing pauses; the server answers nothing for fewer
  /// than two characters, so those are not sent.
  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _searchSeq++;
    final String query = text.trim();
    if (query.length < 2) {
      setState(() => _players = const <DuelPlayerDto>[]);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_runSearch(query)),
    );
  }

  Future<void> _runSearch(String query) async {
    final int seq = ++_searchSeq;
    final Result<DuelPlayersDto> result = await ref
        .read(duelsApiProvider)
        .searchPlayers(query);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _players = switch (result) {
        Ok<DuelPlayersDto>(:final value) => value.players,
        Err<DuelPlayersDto>() => const <DuelPlayerDto>[],
      };
    });
  }

  Future<void> _invite(DuelPlayerDto player) async {
    setState(() => _invites[player.userId] = _Invite.sending);
    final GroupsApi api = ref.read(groupsApiProvider);
    final Result<bool> result = await api.invite(
      widget.group.id,
      player.userId,
    );
    if (!mounted) return;
    setState(() {
      _invites[player.userId] = switch (result) {
        Ok<bool>(:final value) => value ? _Invite.sent : _Invite.already,
        Err<bool>(:final error) when error.code == 'group.already_member' =>
          _Invite.member,
        Err<bool>() => _Invite.failed,
      };
    });
  }

  Future<void> _shareLink() async {
    await SharePlus.instance.share(
      ShareParams(text: leagueShareText(widget.group)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const Key('leagueInvite'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'ادعُ إلى دوري «${widget.group.name}»',
              textAlign: TextAlign.center,
              style: context.text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const Key('leagueInvite.share'),
              onPressed: () => unawaited(_shareLink()),
              icon: const Icon(Icons.link_rounded),
              label: const Text('مشاركة رابط الدعوة'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('leagueInvite.search'),
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'ابحث عن لاعب باسمه',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final DuelPlayerDto player in _players)
                    _PlayerRow(
                      player: player,
                      state: _invites[player.userId],
                      onInvite: () => unawaited(_invite(player)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.state,
    required this.onInvite,
  });

  final DuelPlayerDto player;
  final _Invite? state;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String id = player.userId;
    final Widget trailing = switch (state) {
      _Invite.sent => Text(
        'أُرسلت الدعوة',
        key: Key('leagueInvite.sent.$id'),
        style: TextStyle(
          color: tokens.successText,
          fontSize: AppFontSize.s12,
          fontWeight: FontWeight.w700,
        ),
      ),
      _Invite.already => Text(
        'دُعي من قبل',
        key: Key('leagueInvite.already.$id'),
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: AppFontSize.s12,
        ),
      ),
      _Invite.member => Text(
        'في الدوري',
        key: Key('leagueInvite.member.$id'),
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: AppFontSize.s12,
        ),
      ),
      _Invite.sending => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      _Invite.failed || null => TextButton(
        key: Key('leagueInvite.invite.$id'),
        onPressed: onInvite,
        child: Text(state == _Invite.failed ? 'أعد المحاولة' : 'ادعُ'),
      ),
    };
    return ListTile(
      key: Key('leagueInvite.player.$id'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.person_outline_rounded, color: tokens.textSecondary),
      title: Text(
        player.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.textPrimary),
      ),
      trailing: trailing,
    );
  }
}
