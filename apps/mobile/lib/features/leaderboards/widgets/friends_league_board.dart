/// The friends' league tab of the leaderboard (phase 2 of the plan): the
/// month's board of the player's own league, ranked among its members by
/// the server with the month board's points, a one-tap invitation link,
/// and -- before any league -- a start that names the players they duel
/// most.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../duels/duels_providers.dart';
import '../../groups/create_group_screen.dart';
import '../../groups/groups_providers.dart';
import '../../groups/join_group_screen.dart';
import '../../groups/league_invite.dart';
import '../../groups/league_invite_sheet.dart';
import 'fixture_standings_board.dart';

/// The tab's body for the month contest [seasonId].
class FriendsLeagueBoard extends ConsumerStatefulWidget {
  /// Creates the board.
  const FriendsLeagueBoard({
    required this.seasonId,
    required this.keyPrefix,
    this.myDisplayName,
    super.key,
  });

  /// The month contest.
  final String seasonId;

  /// The widget-test key namespace.
  final String keyPrefix;

  /// The viewer's name, the fallback to find their row.
  final String? myDisplayName;

  @override
  ConsumerState<FriendsLeagueBoard> createState() => _FriendsLeagueBoardState();
}

class _FriendsLeagueBoardState extends ConsumerState<FriendsLeagueBoard> {
  String? _groupId;

  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push<Object?>(MaterialPageRoute<Object?>(builder: (_) => screen));
    if (mounted) ref.invalidate(myGroupsProvider);
  }

  /// By the link, or by finding a player by name (decided 2026-10-07).
  Future<void> _invite(GroupDto group) => showLeagueInviteSheet(context, group);

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String k = widget.keyPrefix;
    return ref
        .watch(myGroupsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: TextButton(
              key: Key('$k.retry'),
              onPressed: () => ref.invalidate(myGroupsProvider),
              child: const Text('تعذّر تحميل دورياتك. أعد المحاولة.'),
            ),
          ),
          data: (mine) {
            if (mine.groups.isEmpty) {
              return _StartLeague(
                keyPrefix: k,
                onCreate: () => unawaited(_open(const CreateGroupScreen())),
                onJoin: () => unawaited(_open(const JoinGroupScreen())),
              );
            }
            final GroupDto group = <MyGroupEntryDto>[
              for (final MyGroupEntryDto e in mine.groups)
                if (e.group.id == _groupId) e,
              mine.groups.first,
            ].first.group;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (mine.groups.length > 1)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Row(
                      children: <Widget>[
                        for (final MyGroupEntryDto e in mine.groups)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: AppSpacing.xs,
                            ),
                            child: ChoiceChip(
                              key: Key('$k.group.${e.group.id}'),
                              label: Text(e.group.name),
                              selected: e.group.id == group.id,
                              onSelected: (_) =>
                                  setState(() => _groupId = e.group.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${group.name} · ${group.memberCount} أعضاء',
                          key: Key('$k.name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: Key('$k.invite'),
                        onPressed: () => unawaited(_invite(group)),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('ادعُ'),
                      ),
                      IconButton(
                        key: Key('$k.create'),
                        tooltip: 'دوري جديد',
                        onPressed: () =>
                            unawaited(_open(const CreateGroupScreen())),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FixtureStandingsBoard(
                    key: ValueKey<String>('$k.board.${group.id}'),
                    seasonId: widget.seasonId,
                    groupId: group.id,
                    keyPrefix: k,
                    myDisplayName: widget.myDisplayName,
                    showHeader: true,
                    emptyMessage:
                        'لم يسجّل أعضاء هذا الدوري نقاطاً هذا الشهر بعد.',
                  ),
                ),
              ],
            );
          },
        );
  }
}

/// Before any league: what it is, who to invite, and the two ways in.
class _StartLeague extends ConsumerWidget {
  const _StartLeague({
    required this.keyPrefix,
    required this.onCreate,
    required this.onJoin,
  });

  final String keyPrefix;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final MyDuelsDto? duels = ref.watch(myDuelsProvider).value;
    final List<String> rivals = duels == null
        ? const <String>[]
        : frequentOpponents(duels);
    return ListView(
      key: Key('$keyPrefix.start'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: AppRadius.brCard,
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'دوري أصدقائك',
                style: text.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'ترتيب خاص بك وبمن تدعوهم، بنقاط الشهر نفسها. أنشئ دورياً '
                'وأرسل رابطه، فينضم صديقك بضغطة.',
                style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              if (rivals.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'تواجه كثيراً: ${rivals.join('، ')}. اجمعهم في دوري.',
                  key: Key('$keyPrefix.rivals'),
                  style: text.bodyMedium?.copyWith(color: tokens.primaryText),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                key: Key('$keyPrefix.start.create'),
                onPressed: onCreate,
                child: const Text('أنشئ دورياً'),
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton(
                key: Key('$keyPrefix.start.join'),
                onPressed: onJoin,
                child: const Text('عندي رمز دوري'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
