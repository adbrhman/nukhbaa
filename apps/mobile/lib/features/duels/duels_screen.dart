/// The Duels page (migration 0090), opened from the account tab: a code
/// field to open a friend's challenge, the private invitations waiting for
/// the caller, the caller's open challenges, and their duels with the
/// result once both scores are final.
///
/// The opponent's prediction appears only from kickoff on: the server
/// leaves it out before, and this page says so instead of drawing a blank.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/format/timestamps.dart';
import '../competition/widgets/async_list_view.dart';
import 'accept_duel_sheet.dart';
import 'duel_texts.dart';
import 'duels_providers.dart';

/// The Duels page.
class DuelsScreen extends ConsumerStatefulWidget {
  /// Creates the page.
  const DuelsScreen({this.openCode, super.key});

  /// A challenge to open at once, as if its code had been typed: the
  /// code of a tapped `duel:CODE` push.
  final String? openCode;

  @override
  ConsumerState<DuelsScreen> createState() => _DuelsScreenState();
}

class _DuelsScreenState extends ConsumerState<DuelsScreen> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final String? code = widget.openCode;
    if (code != null && code.isNotEmpty) {
      _code.text = code;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openCode());
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCode() async {
    final String code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    final Result<DuelChallengeDto> found = await ref
        .read(duelsApiProvider)
        .challengeByCode(code);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (found) {
      case Err<DuelChallengeDto>(:final error):
        _say(duelErrorMessage(error));
      case Ok<DuelChallengeDto>(:final value):
        if (value.isMine) {
          _say('هذا تحديك أنت. شاركه مع أصدقائك.');
        } else if (value.state != 'open') {
          _say('التحدي ${duelChallengeStateLabel(value.state)}.');
        } else {
          await _accept(value);
        }
    }
  }

  Future<void> _accept(DuelChallengeDto challenge) async {
    final bool? accepted = await showAcceptDuelSheet(
      context: context,
      challenge: challenge,
    );
    if (!mounted || accepted != true) return;
    _code.clear();
    _say('قُبل التحدي. بالتوفيق!');
  }

  Future<void> _decline(DuelChallengeDto challenge) async {
    final Result<String> result = await ref
        .read(duelsApiProvider)
        .declineChallenge(challenge.id);
    if (!mounted) return;
    switch (result) {
      case Ok<String>():
        ref.invalidate(myDuelsProvider);
        _say('رفضت التحدي.');
      case Err<String>(:final error):
        _say(duelErrorMessage(error));
    }
  }

  Future<void> _cancel(DuelChallengeDto challenge) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('إلغاء التحدي؟'),
        content: const Text(
          'لن يستطيع أحد قبوله بعد الآن. المواجهات المقبولة منه تبقى.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('تراجع'),
          ),
          TextButton(
            key: const Key('duels.cancel.confirm'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('ألغِ التحدي'),
          ),
        ],
      ),
    );
    if (!mounted || sure != true) return;
    final Result<String> result = await ref
        .read(duelsApiProvider)
        .cancelChallenge(challenge.id);
    if (!mounted) return;
    switch (result) {
      case Ok<String>():
        ref.invalidate(myDuelsProvider);
        _say('أُلغي التحدي.');
      case Err<String>(:final error):
        _say(duelErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Scaffold(
      key: const Key('duels.screen'),
      backgroundColor: tokens.background,
      appBar: AppBar(centerTitle: true, title: const Text('المواجهات')),
      body: AsyncObjectView<MyDuelsDto>(
        value: ref.watch(myDuelsProvider),
        onRetry: () => ref.invalidate(myDuelsProvider),
        builder: (BuildContext context, MyDuelsDto mine) {
          final List<DuelChallengeDto> invitations = <DuelChallengeDto>[
            for (final DuelChallengeDto c in mine.challenges)
              if (c.isForMe) c,
          ];
          final List<DuelChallengeDto> own = <DuelChallengeDto>[
            for (final DuelChallengeDto c in mine.challenges)
              if (c.isMine) c,
          ];
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myDuelsProvider.future),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
              ),
              children: <Widget>[
                _Card(
                  children: <Widget>[
                    const _Heading('لديك رمز مواجهة؟'),
                    TextField(
                      key: const Key('duels.codeField'),
                      controller: _code,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => unawaited(_openCode()),
                      decoration: const InputDecoration(
                        labelText: 'رمز المواجهة',
                      ),
                    ),
                    FilledButton.tonal(
                      key: const Key('duels.openCode'),
                      onPressed: _busy ? null : () => unawaited(_openCode()),
                      child: const Text('افتح التحدي'),
                    ),
                  ],
                ),
                if (invitations.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  _Card(
                    children: <Widget>[
                      const _Heading('تحديات بانتظارك'),
                      for (final DuelChallengeDto c in invitations)
                        _InvitationTile(
                          challenge: c,
                          onAccept: () => unawaited(_accept(c)),
                          onDecline: () => unawaited(_decline(c)),
                        ),
                    ],
                  ),
                ],
                if (own.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  _Card(
                    children: <Widget>[
                      const _Heading('تحدياتي المفتوحة'),
                      for (final DuelChallengeDto c in own)
                        _OwnChallengeTile(
                          challenge: c,
                          onShare: () => unawaited(
                            SharePlus.instance.share(
                              ShareParams(text: duelShareText(c)),
                            ),
                          ),
                          onCancel: () => unawaited(_cancel(c)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _Card(
                  children: <Widget>[
                    const _Heading('مواجهاتي'),
                    if (mine.duels.isEmpty)
                      Text(
                        'لا مواجهات بعد. توقّع مباراة، ثم اختر «تحدَّ» من '
                        'الشريط الذي يظهر بعد حفظ توقعك.',
                        key: const Key('duels.empty'),
                        style: context.text.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    for (final DuelSummaryDto d in mine.duels)
                      _DuelTile(duel: d),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.brCard,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: context.text.titleSmall?.copyWith(
        color: context.tokens.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FixtureLine extends StatelessWidget {
  const _FixtureLine({
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
  });

  final String homeTeam;
  final String awayTeam;
  final String kickoffAt;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          duelFixtureTitle(homeTeam, awayTeam),
          style: context.text.bodyLarge?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          formatDayAndTime(context, kickoffAt),
          style: context.text.bodySmall?.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({
    required this.challenge,
    required this.onAccept,
    required this.onDecline,
  });

  final DuelChallengeDto challenge;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('duels.invitation.${challenge.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${challenge.challengerName} يتحداك',
          style: context.text.bodyMedium?.copyWith(
            color: context.tokens.textSecondary,
          ),
        ),
        _FixtureLine(
          homeTeam: challenge.homeTeam,
          awayTeam: challenge.awayTeam,
          kickoffAt: challenge.kickoffAt,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                key: Key('duels.accept.${challenge.id}'),
                onPressed: onAccept,
                child: const Text('اقبل'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                key: Key('duels.decline.${challenge.id}'),
                onPressed: onDecline,
                child: const Text('ارفض'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OwnChallengeTile extends StatelessWidget {
  const _OwnChallengeTile({
    required this.challenge,
    required this.onShare,
    required this.onCancel,
  });

  final DuelChallengeDto challenge;
  final VoidCallback onShare;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Column(
      key: Key('duels.own.${challenge.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _FixtureLine(
          homeTeam: challenge.homeTeam,
          awayTeam: challenge.awayTeam,
          kickoffAt: challenge.kickoffAt,
        ),
        Text(
          'الرمز ${challenge.code} · قبِل '
          '${challenge.acceptedCount} من ${challenge.capacity}',
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonalIcon(
                key: Key('duels.share.${challenge.id}'),
                onPressed: onShare,
                icon: const Icon(Icons.share_rounded),
                label: const Text('شارك'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                key: Key('duels.cancel.${challenge.id}'),
                onPressed: onCancel,
                child: const Text('ألغِ'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DuelTile extends StatelessWidget {
  const _DuelTile({required this.duel});

  final DuelSummaryDto duel;

  String _pick(int? home, int? away, bool? isDouble) {
    if (home == null || away == null) return '—';
    return isDouble == true ? '$home-$away ×2' : '$home-$away';
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final String? outcome = duel.outcome;
    final Color outcomeColor = switch (outcome) {
      'won' => tokens.gold,
      'lost' => tokens.errorText,
      _ => tokens.textSecondary,
    };
    final bool hidden = duel.state == 'upcoming';
    return Container(
      key: Key('duels.duel.${duel.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _FixtureLine(
                  homeTeam: duel.homeTeam,
                  awayTeam: duel.awayTeam,
                  kickoffAt: duel.kickoffAt,
                ),
              ),
              Text(
                outcome == null
                    ? duelStateLabel(duel.state)
                    : duelOutcomeLabel(outcome),
                key: Key('duels.duel.${duel.id}.status'),
                style: text.labelLarge?.copyWith(
                  color: outcomeColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'أنت: ${_pick(duel.myHomeGoals, duel.myAwayGoals, duel.myIsDouble)}'
                  '${duel.myPoints == null ? '' : ' · ${duel.myPoints} ن'}',
                  style: text.bodyMedium?.copyWith(color: tokens.textPrimary),
                ),
              ),
              Expanded(
                child: Text(
                  hidden
                      ? '${duel.opponentName}: يُكشف عند الانطلاق'
                      : '${duel.opponentName}: '
                            '${_pick(duel.opponentHomeGoals, duel.opponentAwayGoals, duel.opponentIsDouble)}'
                            '${duel.opponentPoints == null ? '' : ' · ${duel.opponentPoints} ن'}',
                  key: Key('duels.duel.${duel.id}.opponent'),
                  textAlign: TextAlign.end,
                  style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
