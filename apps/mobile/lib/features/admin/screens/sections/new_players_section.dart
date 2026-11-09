/// قسم «اللاعبون الجدد» في لوحة المشرف (السكربت 202): كل من سجّل في آخر
/// 7 أيام، الأحدث أولاً، باسمه وبريده ووقت تسجيله، ولماذا قد يكون اسمه
/// مستعاراً، وكم حساباً على هاتفه، وكم توقعاً أرسل. يفتحه إشعار «لاعب
/// جديد» عند الضغط عليه.
///
/// الضغط على لاعب يفتح رسالة جاهزة من «دعم نُخبة» تطلب منه اسمه الحقيقي؛
/// يعدّلها المشرف ثم يرسلها، فتصل اللاعب في محادثة الدعم مع إشعار. الاسم
/// لا يتغير من جهة اللاعب بعد اختياره: يعدّله المشرف من قسم «الأسماء» حين
/// يصله الاسم الحقيقي.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/providers.dart';
import '../../widgets/admin_ui_kit.dart';

/// `GET /admin/new-players` (the last 7 days).
final adminNewPlayersProvider = FutureProvider.autoDispose<NewPlayersDto>((
  ref,
) async {
  return switch (await ref.watch(adminApiProvider).newPlayers()) {
    Ok<NewPlayersDto>(:final value) => value,
    Err<NewPlayersDto>(:final error) => throw error,
  };
});

/// Why a name may be borrowed, as the admin reads it.
String? newPlayerHintLabel(String? hint) => switch (hint) {
  'automatic' => 'لم يختر اسماً (من بريده)',
  'digits' => 'في اسمه أرقام',
  'one_word' => 'اسم من كلمة واحدة',
  'title' => 'لقب لا اسم',
  'latin' => 'اسم بحروف لاتينية',
  _ => null,
};

/// The message support sends, ready for the admin to edit.
String realNameRequest(String name) =>
    'مرحباً، معك دعم نُخبة. اسمك في التطبيق «$name» لا يبدو اسماً '
    'حقيقياً. في نُخبة يُشترط الاسم الحقيقي، ولا يُقبل اسم مستعار أو '
    'منتحَل. أرسل لنا هنا اسمك الأول واسم عائلتك لنعدّله لك.';

String _when(DateTime at) {
  final DateTime local = at.toLocal();
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// The "new players" section of the admin hub.
class NewPlayersSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const NewPlayersSection({super.key});

  @override
  ConsumerState<NewPlayersSection> createState() => _NewPlayersSectionState();
}

class _NewPlayersSectionState extends ConsumerState<NewPlayersSection> {
  final TextEditingController _message = TextEditingController();
  String? _selectedId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _select(NewPlayerDto player) {
    setState(() {
      if (_selectedId == player.user.id) {
        _selectedId = null;
      } else {
        _selectedId = player.user.id;
        _message.text = realNameRequest(
          player.user.displayName.isEmpty
              ? (player.user.email ?? '')
              : player.user.displayName,
        );
      }
      _error = null;
    });
  }

  Future<void> _send(NewPlayerDto player) async {
    final String text = _message.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'اكتب الرسالة أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<SupportMessageDto> result = await ref
        .read(adminApiProvider)
        .messagePlayer(player.user.id, text);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<SupportMessageDto>():
        setState(() => _selectedId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'أُرسلت الرسالة إلى «${player.user.displayName}» في محادثة الدعم',
            ),
          ),
        );
      case Err<SupportMessageDto>(:final error):
        setState(() => _error = ErrorPresenter.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<NewPlayersDto> players = ref.watch(
      adminNewPlayersProvider,
    );
    return ListView(
      key: const Key('admin.newPlayers.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'اللاعبون الجدد',
          subtitle:
              'من سجّل في آخر 7 أيام. اضغط على لاعب لتطلب منه اسمه الحقيقي '
              'في محادثة الدعم.',
        ),
        ...players.when(
          loading: () => <Widget>[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
          error: (Object error, _) => <Widget>[
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    ErrorPresenter.messageOf(error),
                    key: const Key('admin.newPlayers.loadError'),
                    style: TextStyle(color: tokens.errorText),
                  ),
                  TextButton(
                    key: const Key('admin.newPlayers.retry'),
                    onPressed: () => ref.invalidate(adminNewPlayersProvider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ],
          data: (NewPlayersDto data) => <Widget>[
            Text(
              data.players.isEmpty
                  ? 'لم يسجّل أحد في آخر ${data.days} أيام'
                  : 'سجّل ${data.players.length} في آخر ${data.days} أيام',
              key: const Key('admin.newPlayers.summary'),
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final NewPlayerDto player in data.players) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _playerCard(context, player),
            ],
          ],
        ),
      ],
    );
  }

  Widget _playerCard(BuildContext context, NewPlayerDto player) {
    final AppTokens tokens = context.tokens;
    final String? hint = newPlayerHintLabel(player.nameHint);
    final bool selected = _selectedId == player.user.id;
    final bool suspended = player.user.status == 'suspended';
    final String? error = _error;
    return AdminCard(
      key: Key('admin.newPlayers.player.${player.user.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: Key('admin.newPlayers.open.${player.user.id}'),
              onTap: () => _select(player),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    player.user.displayName.isEmpty
                        ? player.user.id
                        : player.user.displayName,
                    style: context.text.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${player.user.email ?? ''} · ${_when(player.joinedAt)}',
                    style: context.text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: <Widget>[
                      if (hint != null)
                        _Chip(
                          key: Key('admin.newPlayers.hint.${player.user.id}'),
                          text: hint,
                          color: tokens.errorText,
                        ),
                      if (player.phoneAccounts > 1)
                        _Chip(
                          key: Key('admin.newPlayers.phone.${player.user.id}'),
                          text: '${player.phoneAccounts} حسابات على هاتفه',
                          color: tokens.errorText,
                        ),
                      if (suspended)
                        _Chip(text: 'موقوف', color: tokens.errorText),
                      _Chip(
                        text: '${player.predictions} توقعاً',
                        color: tokens.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (selected) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('admin.newPlayers.message'),
              controller: _message,
              enabled: !_busy,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'رسالة من دعم نُخبة',
              ),
            ),
            if (error != null)
              Text(
                error,
                key: const Key('admin.newPlayers.error'),
                style: TextStyle(color: tokens.errorText),
              ),
            const SizedBox(height: AppSpacing.xs),
            AdminPrimaryButton(
              key: const Key('admin.newPlayers.send'),
              label: 'إرسال في محادثة الدعم',
              icon: Icons.send_rounded,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_send(player)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: context.text.bodySmall?.copyWith(color: color)),
    );
  }
}
