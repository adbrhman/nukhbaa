/// The "challenge a friend" sheet: picks how many friends may take the
/// challenge, creates it (`POST /duels/challenges`), then offers the code
/// and link to share.
///
/// The server refuses a challenge without the caller's prediction, inside
/// 30 minutes of kickoff, or beyond ten pending ones; the sheet only says
/// why. Private (named-player) challenges stay server-only for now: the
/// app has no player search to pick from.
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
          capacity: _capacity,
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const Key('createDuel.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '⚔️ تحدَّ صديقك',
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
                'كم صديقاً يقبل التحدي؟',
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
                      label: Text(seats == 1 ? 'صديق واحد' : '$seats أصدقاء'),
                      selected: _capacity == seats,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _capacity = seats),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'كل من يقبل يتوقع بنفسه، ويفوز صاحب النقاط الأعلى في المباراة.',
                style: text.bodySmall?.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('createDuel.create'),
                onPressed: _busy ? null : () => unawaited(_create()),
                child: Text(_busy ? 'جارٍ الإنشاء…' : 'أنشئ التحدي'),
              ),
            ] else ...<Widget>[
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
    );
  }
}
