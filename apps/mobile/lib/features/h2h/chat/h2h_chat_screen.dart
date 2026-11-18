/// The chat of the player's own head-to-head group (migration 0216, script
/// 282).
///
/// Only the members of the group write in it; the server finds the group by
/// the signed-in player. A player accepts the rules before he reads or
/// writes. Reporting and blocking are script 225's: a long press on another
/// player's message offers to report it (it reaches the owner through the
/// support chat, with the message quoted) and to block the player (kept on
/// this phone; his messages disappear from this chat).
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_error_state.dart';
import '../../../core/ui/app_skeleton.dart';
import '../../moderation/blocked_players.dart';
import '../../moderation/player_actions.dart';
import '../../support/support_providers.dart';
import 'h2h_chat_providers.dart';
import 'h2h_chat_texts.dart';
import 'h2h_chat_widgets.dart';

enum _MessageAction { report, block, unblock }

class _Pending {
  _Pending({required this.localId, required this.body});

  final int localId;
  final String body;
  bool sending = true;
  String? error;
}

/// The chat of the player's own group.
class H2hChatScreen extends ConsumerStatefulWidget {
  const H2hChatScreen({super.key, this.pollEvery = const Duration(seconds: 8)});

  /// How often the newest messages are fetched while the screen is open.
  final Duration pollEvery;

  @override
  ConsumerState<H2hChatScreen> createState() => _H2hChatScreenState();
}

class _H2hChatScreenState extends ConsumerState<H2hChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final List<H2hChatMessageDto> _messages = <H2hChatMessageDto>[];
  final List<_Pending> _pending = <_Pending>[];
  int _nextLocalId = 1;
  bool _loading = true;
  AppError? _loadError;
  bool _hasGroup = true;
  bool _muted = false;
  bool _rulesAccepted = false;
  bool _accepting = false;
  bool _offline = false;
  bool _refreshing = false;
  bool _foreground = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(() => setState(() {}));
    unawaited(_load());
    _timer = Timer.periodic(widget.pollEvery, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
  }

  H2hChatApi get _api => ref.read(h2hChatApiProvider);

  void _apply(H2hChatPageDto page, {required bool replace}) {
    _hasGroup = page.hasGroup;
    _muted = page.muted;
    _rulesAccepted = page.rulesAccepted;
    if (replace) {
      _messages
        ..clear()
        ..addAll(page.messages);
    } else {
      final Set<int> have = <int>{
        for (final H2hChatMessageDto m in _messages) m.id,
      };
      _messages.addAll(
        page.messages.where((H2hChatMessageDto m) => !have.contains(m.id)),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final Result<H2hChatPageDto> result = await _api.page();
    if (!mounted) return;
    switch (result) {
      case Ok<H2hChatPageDto>(:final value):
        setState(() {
          _apply(value, replace: true);
          _loading = false;
          _offline = false;
        });
        if (value.unread > 0 && value.rulesAccepted) unawaited(_api.markRead());
      case Err<H2hChatPageDto>(:final error):
        setState(() {
          _loadError = error;
          _loading = false;
        });
    }
  }

  Future<void> _refresh() async {
    if (!mounted || !_foreground || _refreshing) return;
    if (_loading || _loadError != null || !_hasGroup || !_rulesAccepted) return;
    _refreshing = true;
    final int? after = _messages.isEmpty ? null : _messages.last.id;
    final Result<H2hChatPageDto> result = await _api.page(after: after);
    _refreshing = false;
    if (!mounted) return;
    switch (result) {
      case Ok<H2hChatPageDto>(:final value):
        final int before = _messages.length;
        setState(() {
          _apply(value, replace: false);
          _offline = false;
        });
        if (_messages.length > before) unawaited(_api.markRead());
      case Err<H2hChatPageDto>():
        setState(() => _offline = true);
    }
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    final Result<void> result = await _api.acceptRules();
    if (!mounted) return;
    switch (result) {
      case Ok<void>():
        setState(() {
          _accepting = false;
          _rulesAccepted = true;
        });
      case Err<void>(:final error):
        setState(() => _accepting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorPresenter.message(error))));
    }
  }

  void _send() {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    final _Pending pending = _Pending(localId: _nextLocalId++, body: text);
    setState(() => _pending.add(pending));
    _input.clear();
    unawaited(_deliver(pending));
  }

  Future<void> _deliver(_Pending pending) async {
    setState(() {
      pending
        ..sending = true
        ..error = null;
    });
    final Result<H2hChatMessageDto> result = await _api.send(pending.body);
    if (!mounted) return;
    switch (result) {
      case Ok<H2hChatMessageDto>(:final value):
        setState(() {
          _pending.remove(pending);
          if (!_messages.any((H2hChatMessageDto m) => m.id == value.id)) {
            _messages.add(value);
          }
        });
      case Err<H2hChatMessageDto>(:final error):
        setState(() {
          if (error.code == 'h2h.chat_rules_not_accepted') {
            _rulesAccepted = false;
            _pending.remove(pending);
          } else if (error.code == 'h2h.chat_muted') {
            _muted = true;
            _pending.remove(pending);
          } else {
            pending
              ..sending = false
              ..error = ErrorPresenter.message(error);
          }
        });
    }
  }

  Future<void> _openMenu(H2hChatMessageDto message) async {
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool blocked = container
        .read(blockedPlayersProvider)
        .containsKey(blockKeyOf(message.senderName));
    final _MessageAction? action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) =>
          _MessageSheet(name: message.senderName, blocked: blocked),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MessageAction.block:
        await container
            .read(blockedPlayersProvider.notifier)
            .block(message.senderName);
        messenger.showSnackBar(
          const SnackBar(content: Text(playerBlockedMessage)),
        );
      case _MessageAction.unblock:
        await container
            .read(blockedPlayersProvider.notifier)
            .unblock(blockKeyOf(message.senderName));
        messenger.showSnackBar(
          const SnackBar(content: Text(playerUnblockedMessage)),
        );
      case _MessageAction.report:
        final String? reason = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheet) => const _ReasonSheet(),
        );
        if (reason == null) return;
        final Result<SupportMessageDto> result = await container
            .read(supportApiProvider)
            .send(
              h2hChatReportMessage(
                displayName: message.senderName,
                senderId: message.senderId,
                messageId: message.id,
                body: message.body,
                reason: reason,
              ),
            );
        messenger.showSnackBar(
          SnackBar(
            content: Text(switch (result) {
              Ok<SupportMessageDto>() => reportSentMessage,
              Err<SupportMessageDto>(:final error) => ErrorPresenter.message(
                error,
              ),
            }),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool chatOpen =
        !_loading && _loadError == null && _hasGroup && _rulesAccepted;
    return Scaffold(
      appBar: AppBar(
        title: const Text(h2hChatTitle, key: Key('h2hChat.title')),
      ),
      body: Column(
        children: <Widget>[
          if (_offline)
            const H2hChatStrip(
              key: Key('h2hChat.offline'),
              text: 'لا يوجد اتصال، نحاول مرة أخرى…',
              danger: true,
            ),
          Expanded(child: _body(context)),
          if (chatOpen)
            SafeArea(
              top: false,
              child: _muted
                  ? const H2hChatStrip(
                      key: Key('h2hChat.muted'),
                      text:
                          'منعتك إدارة نُخبة من الكتابة في الدردشة. '
                          'يمكنك القراءة فقط.',
                    )
                  : H2hChatComposer(
                      controller: _input,
                      onSend: _input.text.trim().isEmpty ? null : _send,
                    ),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const _ChatSkeleton();
    final AppError? error = _loadError;
    if (error != null) {
      return AppErrorState(
        key: const Key('h2hChat.loadFailed'),
        message: ErrorPresenter.message(error),
        onRetry: _load,
      );
    }
    if (!_hasGroup) {
      return const AppEmptyState(
        key: Key('h2hChat.noGroup'),
        icon: Icons.forum_outlined,
        title: 'لا توجد دردشة بعد',
        subtitle: 'تفتح الدردشة عندما يكون لك مقعد في مجموعة هذا الشهر.',
      );
    }
    if (!_rulesAccepted) {
      return H2hChatRulesGate(onAccept: _accept, accepting: _accepting);
    }
    final Map<String, String> blocked = ref.watch(blockedPlayersProvider);
    final List<H2hChatMessageDto> visible = <H2hChatMessageDto>[
      for (final H2hChatMessageDto m in _messages)
        if (m.mine || !blocked.containsKey(blockKeyOf(m.senderName))) m,
    ];
    if (visible.isEmpty && _pending.isEmpty) {
      return const AppEmptyState(
        key: Key('h2hChat.empty'),
        icon: Icons.forum_outlined,
        title: 'ابدأ الدردشة',
        subtitle: 'لا رسائل بعد. اكتب أول رسالة لمجموعتك.',
      );
    }
    // Newest at the bottom: the list runs upwards from the composer, so it
    // opens on the last message and a new one appears in view.
    final List<Widget> items = <Widget>[
      for (final _Pending p in _pending.reversed)
        H2hChatBubble(
          key: Key('h2hChat.pending.${p.localId}'),
          mine: true,
          body: p.body,
          delivery: p.sending
              ? H2hChatDelivery.sending
              : H2hChatDelivery.failed,
          error: p.error,
          onRetry: p.sending ? null : () => unawaited(_deliver(p)),
        ),
      for (final H2hChatMessageDto m in visible.reversed)
        H2hChatBubble(
          key: Key('h2hChat.message.${m.id}'),
          mine: m.mine,
          body: m.body,
          senderName: m.senderName,
          createdAt: m.createdAt,
          delivery: m.mine ? H2hChatDelivery.sent : null,
          onMenu: m.mine ? null : () => unawaited(_openMenu(m)),
        ),
    ];
    return ListView(
      key: const Key('h2hChat.list'),
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: items,
    );
  }
}

class _MessageSheet extends StatelessWidget {
  const _MessageSheet({required this.name, required this.blocked});

  final String name;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              name,
              key: const Key('h2hChat.menu.name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ListTile(
            key: const Key('h2hChat.menu.report'),
            leading: const Icon(Icons.flag_outlined),
            title: const Text('الإبلاغ عن هذه الرسالة'),
            subtitle: const Text('يصل بلاغك إلى فريق نُخبة'),
            onTap: () => Navigator.of(context).pop(_MessageAction.report),
          ),
          if (blocked)
            ListTile(
              key: const Key('h2hChat.menu.unblock'),
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('إلغاء حظر اللاعب'),
              onTap: () => Navigator.of(context).pop(_MessageAction.unblock),
            )
          else
            ListTile(
              key: const Key('h2hChat.menu.block'),
              leading: const Icon(Icons.block_outlined),
              title: const Text('حظر اللاعب'),
              subtitle: const Text('تختفي رسائله من هذه الدردشة'),
              onTap: () => Navigator.of(context).pop(_MessageAction.block),
            ),
        ],
      ),
    );
  }
}

class _ReasonSheet extends StatelessWidget {
  const _ReasonSheet();

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'ما سبب البلاغ؟',
              style: context.text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (int i = 0; i < playerReportReasons.length; i++)
            ListTile(
              key: Key('h2hChat.reason.$i'),
              title: Text(playerReportReasons[i]),
              onTap: () => Navigator.of(context).pop(playerReportReasons[i]),
            ),
        ],
      ),
    );
  }
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('h2hChat.skeleton'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        for (int i = 0; i < 5; i++)
          Align(
            alignment: i.isEven
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: AppSkeleton(
                width: i.isEven ? 200 : 150,
                height: 44,
                borderRadius: AppRadius.brLg,
              ),
            ),
          ),
      ],
    );
  }
}
