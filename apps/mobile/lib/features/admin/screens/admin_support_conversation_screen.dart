/// One player's support conversation as an admin answers it (migration
/// 0187, script 167): the same chat the player sees, mirrored -- the
/// admin's answers are "mine" and go out as «دعم نُخبة».
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/providers.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/app_error_state.dart';
import '../../../core/ui/app_skeleton.dart';
import '../../support/support_chat_widgets.dart';
import '../admin_support_providers.dart';

/// The conversation: the player's messages, the answers, a box to answer,
/// and the status (open, closed, archived) in the bar's menu. The
/// player's messages are marked read when they are on screen; the page is
/// read again every [pollEvery].
class AdminSupportConversationScreen extends ConsumerStatefulWidget {
  const AdminSupportConversationScreen({
    super.key,
    required this.conversationId,
    required this.playerName,
    this.pollEvery = const Duration(seconds: 8),
  });

  final String conversationId;
  final String playerName;
  final Duration pollEvery;

  @override
  ConsumerState<AdminSupportConversationScreen> createState() =>
      _AdminSupportConversationScreenState();
}

final class _PendingReply {
  _PendingReply(this.localId, this.body);

  final int localId;
  final String body;
  bool sending = true;
  String? error;
}

class _AdminSupportConversationScreenState
    extends ConsumerState<AdminSupportConversationScreen> {
  final TextEditingController _input = TextEditingController();
  final List<SupportMessageDto> _messages = <SupportMessageDto>[];
  final List<_PendingReply> _pending = <_PendingReply>[];
  SupportConversationDto? _conversation;
  AppError? _loadError;
  bool _loading = true;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _offline = false;
  bool _refreshing = false;
  int _nextLocalId = 1;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInput);
    unawaited(_load(first: true));
    _poll = Timer.periodic(widget.pollEvery, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input
      ..removeListener(_onInput)
      ..dispose();
    super.dispose();
  }

  void _onInput() => setState(() {});

  Future<void> _load({bool first = false}) async {
    if (_refreshing) return;
    if (!first && _loadError != null) return;
    _refreshing = true;
    final Result<SupportConversationPageDto> result = await ref
        .read(adminApiProvider)
        .supportConversation(widget.conversationId);
    _refreshing = false;
    if (!mounted) return;
    switch (result) {
      case Ok<SupportConversationPageDto>(:final value):
        setState(() {
          _loading = false;
          _loadError = null;
          _offline = false;
          _conversation = value.conversation;
          if (first) _hasMore = value.thread.hasMore;
          _merge(value.thread.messages);
        });
        if (value.thread.unread > 0) unawaited(_markRead());
      case Err<SupportConversationPageDto>(:final error):
        setState(() {
          _loading = false;
          if (_conversation == null) {
            _loadError = error;
          } else {
            _offline = true;
          }
        });
    }
  }

  void _merge(List<SupportMessageDto> page) {
    final Map<int, SupportMessageDto> byId = <int, SupportMessageDto>{
      for (final SupportMessageDto m in _messages) m.id: m,
      for (final SupportMessageDto m in page) m.id: m,
    };
    _messages
      ..clear()
      ..addAll(byId.values.toList()..sort((a, b) => a.id.compareTo(b.id)));
  }

  Future<void> _markRead() async {
    await ref.read(adminApiProvider).markSupportRead(widget.conversationId);
    if (mounted) ref.invalidate(adminSupportWaitingProvider);
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    final Result<SupportConversationPageDto> result = await ref
        .read(adminApiProvider)
        .supportConversation(widget.conversationId, before: _messages.first.id);
    if (!mounted) return;
    setState(() {
      _loadingOlder = false;
      if (result case Ok<SupportConversationPageDto>(:final value)) {
        _merge(value.thread.messages);
        _hasMore = value.thread.hasMore;
      }
    });
  }

  void _send() {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    final _PendingReply reply = _PendingReply(_nextLocalId++, text);
    setState(() {
      _pending.add(reply);
      _input.clear();
    });
    unawaited(_deliver(reply));
  }

  Future<void> _deliver(_PendingReply reply) async {
    setState(() {
      reply
        ..sending = true
        ..error = null;
    });
    final Result<SupportMessageDto> result = await ref
        .read(adminApiProvider)
        .replySupport(widget.conversationId, reply.body);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case Ok<SupportMessageDto>(:final value):
          _pending.remove(reply);
          _merge(<SupportMessageDto>[value]);
        case Err<SupportMessageDto>(:final error):
          reply
            ..sending = false
            ..error = ErrorPresenter.message(error);
      }
    });
  }

  Future<void> _setStatus(String status) async {
    if (status != 'open') {
      final bool? sure = await AppDialog.confirm(
        context,
        title: status == 'closed' ? 'إغلاق المحادثة؟' : 'أرشفة المحادثة؟',
        message:
            'تبقى الرسائل كما هي، ويعيد اللاعب فتحها إن كتب رسالة '
            'جديدة.',
        confirmLabel: status == 'closed' ? 'إغلاق' : 'أرشفة',
        cancelLabel: 'إلغاء',
      );
      if (sure != true || !mounted) return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Result<String> result = await ref
        .read(adminApiProvider)
        .setSupportStatus(widget.conversationId, status);
    if (!mounted) return;
    switch (result) {
      case Ok<String>():
        await _load();
      case Err<String>(:final error):
        messenger.showSnackBar(
          SnackBar(content: Text(ErrorPresenter.message(error))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final SupportConversationDto? c = _conversation;
    final String status = c?.status ?? 'open';
    final String name = (c?.playerName ?? widget.playerName).trim().isEmpty
        ? 'لاعب'
        : (c?.playerName ?? widget.playerName);
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(name, key: const Key('admin.support.thread.title')),
        actions: <Widget>[
          if (c != null)
            PopupMenuButton<String>(
              key: const Key('admin.support.thread.menu'),
              tooltip: 'حالة المحادثة',
              onSelected: (String s) => unawaited(_setStatus(s)),
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                if (status != 'open')
                  const PopupMenuItem<String>(
                    key: Key('admin.support.thread.reopen'),
                    value: 'open',
                    child: Text('إعادة فتح'),
                  ),
                if (status != 'closed')
                  const PopupMenuItem<String>(
                    key: Key('admin.support.thread.close'),
                    value: 'closed',
                    child: Text('إغلاق'),
                  ),
                if (status != 'archived')
                  const PopupMenuItem<String>(
                    key: Key('admin.support.thread.archive'),
                    value: 'archived',
                    child: Text('أرشفة'),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            if (_offline)
              const SupportStrip(
                key: Key('support.offline'),
                text: 'لا اتصال بالخادم الآن. نعيد المحاولة تلقائيًا.',
                danger: true,
              ),
            if (status == 'closed' || status == 'archived')
              SupportStrip(
                key: const Key('admin.support.thread.status'),
                text: status == 'closed'
                    ? 'المحادثة مغلقة. تُفتح من جديد إن كتب اللاعب.'
                    : 'المحادثة مؤرشفة. تُفتح من جديد إن كتب اللاعب.',
              ),
            Expanded(child: _body()),
            if (c != null)
              SupportComposer(
                controller: _input,
                onSend: _input.text.trim().isEmpty ? null : _send,
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: AppSkeleton(width: 220, height: 44));
    }
    final AppError? error = _loadError;
    if (error != null) {
      return AppErrorState(
        message: ErrorPresenter.message(error),
        onRetry: () {
          setState(() {
            _loading = true;
            _loadError = null;
          });
          unawaited(_load(first: true));
        },
      );
    }
    return ListView(
      key: const Key('admin.support.thread.list'),
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      children: <Widget>[
        for (final _PendingReply p in _pending.reversed)
          SupportBubble(
            key: Key('support.pending.${p.localId}'),
            mine: true,
            body: p.body,
            senderLabel: 'دعم نُخبة',
            delivery: p.sending
                ? SupportDelivery.sending
                : SupportDelivery.failed,
            error: p.error,
            onRetry: p.sending ? null : () => unawaited(_deliver(p)),
          ),
        for (final SupportMessageDto m in _messages.reversed)
          SupportBubble(
            key: Key('support.message.${m.id}'),
            mine: m.sender == 'support',
            body: m.body,
            senderLabel: m.sender == 'support' ? 'دعم نُخبة' : 'اللاعب',
            createdAt: m.createdAt,
            delivery: m.sender != 'support'
                ? null
                : (m.readAt == null
                      ? SupportDelivery.sent
                      : SupportDelivery.read),
          ),
        if (_hasMore)
          Center(
            child: TextButton(
              key: const Key('support.older'),
              onPressed: _loadingOlder ? null : () => unawaited(_loadOlder()),
              child: Text(_loadingOlder ? 'جارٍ التحميل…' : 'رسائل أقدم'),
            ),
          ),
      ],
    );
  }
}
