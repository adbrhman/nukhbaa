/// The "challenge a friend" sheet: picks how many friends may take the
/// challenge, creates it (`POST /duels/challenges`), then offers the code
/// and link to share.
///
/// The server refuses a challenge without the caller's prediction, inside
/// 30 minutes of kickoff, or beyond ten pending ones; the sheet only says
/// why. A player found by name gets a private challenge (one seat) and a
/// push that opens it (migration 0092).
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import 'duel_texts.dart';
import 'duels_providers.dart';

/// Opens the sheet for one fixture the caller has predicted.
Future<void> showCreateDuelSheet({
  required BuildContext context,
  required String seasonId,
  required String fixtureId,
  required String homeTeam,
  required String awayTeam,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CreateDuelSheet(
      seasonId: seasonId,
      fixtureId: fixtureId,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
    ),
  );
}

/// The sheet body; public so a widget test can pump it directly.
class CreateDuelSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const CreateDuelSheet({
    required this.seasonId,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    super.key,
  });

  /// The fixture's season.
  final String seasonId;

  /// The fixture to challenge on.
  final String fixtureId;

  /// Home side, as the feed names it.
  final String homeTeam;

  /// Away side, as the feed names it.
  final String awayTeam;

  @override
  ConsumerState<CreateDuelSheet> createState() => _CreateDuelSheetState();
}

/// Seat choices: one friend, a few, or a group.
const List<int> _capacities = <int>[1, 3, 5, 10];

class _CreateDuelSheetState extends ConsumerState<CreateDuelSheet> {
  int _capacity = 1;
  bool _busy = false;
  String? _error;
  DuelChallengeDto? _created;

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;
  List<DuelPlayerDto> _players = const <DuelPlayerDto>[];

  /// The player picked by name; null for an open challenge.
  DuelPlayerDto? _target;

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
    // A later keystroke or a pick makes this answer stale.
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _players = switch (result) {
        Ok<DuelPlayersDto>(:final value) => value.players,
        Err<DuelPlayersDto>() => const <DuelPlayerDto>[],
      };
    });
  }

  void _pick(DuelPlayerDto player) {
    _debounce?.cancel();
    _searchSeq++;
    _search.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _target = player;
      _players = const <DuelPlayerDto>[];
      _error = null;
    });
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<DuelChallengeDto> result = await ref
        .read(duelsApiProvider)
        .createChallenge(
          seasonId: widget.seasonId,
          fixtureId: widget.fixtureId,
          capacity: _target == null ? _capacity : 1,
          targetUserId: _target?.userId,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok<DuelChallengeDto>(:final value):
          _created = value;
        case Err<DuelChallengeDto>(:final error):
          _error = duelErrorMessage(error);
      }
    });
    if (result is Ok<DuelChallengeDto>) {
      ref.invalidate(myDuelsProvider);
    }
  }

  Future<void> _share(DuelChallengeDto challenge) async {
    await SharePlus.instance.share(ShareParams(text: duelShareText(challenge)));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('نُسخ')));
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final DuelChallengeDto? created = _created;
    final DuelPlayerDto? target = _target;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('createDuel.sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'تحدَّ صديقك',
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                duelFixtureTitle(widget.homeTeam, widget.awayTeam),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (created == null) ...<Widget>[
                Text(
                  'تحدَّ لاعباً باسمه',
                  style: text.titleSmall?.copyWith(color: tokens.textPrimary),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (target != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: InputChip(
                      key: const Key('createDuel.target'),
                      avatar: const Icon(Icons.person_rounded),
                      label: Text(target.displayName),
                      onDeleted: _busy
                          ? null
                          : () => setState(() => _target = null),
                    ),
                  )
                else ...<Widget>[
                  TextField(
                    key: const Key('createDuel.search'),
                    controller: _search,
                    enabled: !_busy,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      labelText: 'اكتب اسم اللاعب',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  for (final DuelPlayerDto player in _players)
                    ListTile(
                      key: Key('createDuel.player.${player.userId}'),
                      dense: true,
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text(player.displayName),
                      onTap: () => _pick(player),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'أو تحدٍّ مفتوح برابط: كم صديقاً يقبله؟',
                    style: text.titleSmall?.copyWith(color: tokens.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      for (final int seats in _capacities)
                        ChoiceChip(
                          key: Key('createDuel.capacity.$seats'),
                          label: Text(
                            seats == 1 ? 'صديق واحد' : '$seats أصدقاء',
                          ),
                          selected: _capacity == seats,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _capacity = seats),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'كل من يقبل يتوقع بنفسه، ويفوز صاحب النقاط الأعلى في المباراة.',
                  style: text.bodySmall?.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  key: const Key('createDuel.create'),
                  onPressed: _busy ? null : () => unawaited(_create()),
                  child: Text(
                    _busy
                        ? 'جارٍ الإنشاء…'
                        : target == null
                        ? 'أنشئ التحدي'
                        : 'أرسل التحدي إلى ${target.displayName}',
                  ),
                ),
              ] else ...<Widget>[
                if (created.isPrivate) ...<Widget>[
                  Text(
                    'أُرسل التحدي إلى ${target?.displayName ?? 'صديقك'}. '
                    'يصله إشعار يفتح التوقع مباشرة.',
                    key: const Key('createDuel.sent'),
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: tokens.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: AppRadius.brCard,
                    border: Border.all(color: tokens.border),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'رمز المواجهة',
                        style: text.titleSmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SelectableText(
                        created.code,
                        key: const Key('createDuel.code'),
                        style: text.headlineSmall?.copyWith(
                          color: tokens.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('createDuel.share'),
                        onPressed: () => unawaited(_share(created)),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('شارك التحدي'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('createDuel.copy'),
                        onPressed: () => unawaited(_copy(created.code)),
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('نسخ الرمز'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error case final String message) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  message,
                  key: const Key('createDuel.error'),
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: tokens.errorText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
