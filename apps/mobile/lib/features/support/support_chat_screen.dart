/// The player's private chat with Nukhbaa support (migration 0187, script
/// 166): he writes from inside the app and reads the answer here, with no
/// WhatsApp and no e-mail, so no phone number is ever shown.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_empty_state.dart';
import '../../core/ui/app_skeleton.dart';
import '../notifications/notifications_screen.dart';
import 'support_chat_widgets.dart';
import 'support_providers.dart';

/// Nukhbaa's support address: the way out of the chat when the server
/// cannot be reached (script 164). Never a phone number.
const String nukhbaaSupportEmail = 'nukhbaa.app@gmail.com';

/// A new mail to [nukhbaaSupportEmail] with the subject 'دعم نُخبة',
/// percent-encoded here (a space as %20, not +, which mail apps show).
final Uri nukhbaaSupportUri = Uri.parse(
  'mailto:$nukhbaaSupportEmail'
  '?subject=%D8%AF%D8%B9%D9%85%20%D9%86%D9%8F%D8%AE%D8%A8%D8%A9',
);

/// The one name the player sees for support, whichever admin answers.
const String supportName = 'دعم نُخبة';

/// The chat: support's answers on one side, the player's messages on the
/// other, newest at the bottom, and a box to write in.
///
/// The page is read again every [pollEvery] while it is open and in the
/// foreground (no realtime channel: the server is the only way in), and
/// support's answers are marked read as soon as they are on screen.
class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({
    super.key,
    this.pollEvery = const Duration(seconds: 8),
  });

  /// How often the open chat asks for new answers.
  final Duration pollEvery;

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

/// A message the player sent that the server has not taken yet.
final class _Pending {
  _Pending(this.localId, this.body);

  final int localId;
  final String body;
  bool sending = true;
  String? error;
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final List<SupportMessageDto> _messages = <SupportMessageDto>[];
  final List<_Pending> _pending = <_Pending>[];
  int _nextLocalId = 1;
  bool _loading = true;
  AppError? _loadError;
  bool _offline = false;
  bool _hasMore = false;
  bool _loadingOlder = false;
  String? _status;
  Timer? _poll;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(_onInput);
    unawaited(_load());
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _input
      ..removeListener(_onInput)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(widget.pollEvery, (_) => unawaited(_refresh()));
  }

  void _onInput() => setState(() {});

  /// The first page; support's unread answers are marked read.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final Result<SupportThreadDto> result = await ref
        .read(supportApiProvider)
        .thread();
    if (!mounted) return;
    switch (result) {
      case Ok<SupportThreadDto>(:final value):
        setState(() {
          _loading = false;
          _offline = false;
          _messages
            ..clear()
            ..addAll(value.messages);
          _hasMore = value.hasMore;
          _status = value.status;
        });
        if (value.unread > 0) unawaited(_markRead());
      case Err<SupportThreadDto>(:final error):
        setState(() {
          _loading = false;
          _loadError = error;
        });
    }
  }

  /// The newest page again: new messages are added, read marks updated.
  Future<void> _refresh() async {
    if (_loading || _loadError != null || _refreshing) return;
    _refreshing = true;
    final Result<SupportThreadDto> result = await ref
        .read(supportApiProvider)
        .thread();
    _refreshing = false;
    if (!mounted) return;
    switch (result) {
      case Ok<SupportThreadDto>(:final value):
        setState(() {
          _offline = false;
          _merge(value.messages);
          _status = value.status;
        });
        if (value.unread > 0) unawaited(_markRead());
      case Err<SupportThreadDto>():
        setState(() => _offline = true);
    }
  }

  /// Puts [page] into the messages by id: a newer copy (now read) replaces
  /// the old one, a new id joins in order.
  void _merge(List<SupportMessageDto> page) {
    final Map<int, SupportMessageDto> byId = <int, SupportMessageDto>{
      for (final SupportMessageDto m in _messages) m.id: m,
      for (final SupportMessageDto m in page) m.id: m,
    };
    final List<SupportMessageDto> merged = byId.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    _messages
      ..clear()
      ..addAll(merged);
  }

  Future<void> _markRead() async {
    await ref.read(supportApiProvider).markRead();
    if (!mounted) return;
    ref.invalidate(supportUnreadProvider);
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    final Result<SupportThreadDto> result = await ref
        .read(supportApiProvider)
        .thread(before: _messages.first.id);
    if (!mounted) return;
    setState(() {
      _loadingOlder = false;
      if (result case Ok<SupportThreadDto>(:final value)) {
        _merge(value.messages);
        _hasMore = value.hasMore;
      }
    });
  }

  void _send() {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    final _Pending pending = _Pending(_nextLocalId++, text);
    setState(() {
      _pending.add(pending);
      _input.clear();
    });
    unawaited(_deliver(pending));
  }

  Future<void> _deliver(_Pending pending) async {
    setState(() {
      pending
        ..sending = true
        ..error = null;
    });
    final Result<SupportMessageDto> result = await ref
        .read(supportApiProvider)
        .send(pending.body);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case Ok<SupportMessageDto>(:final value):
          _pending.remove(pending);
          _merge(<SupportMessageDto>[value]);
          _status = 'open';
          _offline = false;
        case Err<SupportMessageDto>(:final error):
          pending
            ..sending = false
            ..error = ErrorPresenter.message(error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(titleSpacing: 0, title: const _SupportTitle()),
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
            if (_status == 'closed' || _status == 'archived')
              const SupportStrip(
                key: Key('support.closed'),
                text: 'أُغلقت هذه المحادثة. اكتب رسالة جديدة إن احتجت إلينا.',
              ),
            Expanded(child: _body(context)),
            SupportComposer(
              controller: _input,
              onSend: _input.text.trim().isEmpty ? null : _send,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const _ChatSkeleton();
    final AppError? error = _loadError;
    if (error != null) {
      return _LoadFailed(
        message: ErrorPresenter.message(error),
        onRetry: _load,
      );
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return const AppEmptyState(
        key: Key('support.empty'),
        icon: Icons.support_agent_rounded,
        title: 'كيف نساعدك؟',
        subtitle:
            'اكتب مشكلتك أو شكواك هنا، وسيرد عليك فريق نُخبة في هذه '
            'المحادثة. لا يظهر رقم هاتف لأحد.',
      );
    }
    // Newest at the bottom: the list runs upwards from the composer, so it
    // opens on the last message and a new one appears in view.
    final List<Widget> items = <Widget>[
      for (final _Pending p in _pending.reversed)
        SupportBubble(
          key: Key('support.pending.${p.localId}'),
          mine: true,
          body: p.body,
          senderLabel: 'أنت',
          delivery: p.sending
              ? SupportDelivery.sending
              : SupportDelivery.failed,
          error: p.error,
          onRetry: p.sending ? null : () => unawaited(_deliver(p)),
        ),
      for (final SupportMessageDto m in _messages.reversed)
        SupportBubble(
          key: Key('support.message.${m.id}'),
          mine: m.sender == 'player',
          body: m.body,
          senderLabel: m.sender == 'player' ? 'أنت' : supportName,
          createdAt: m.createdAt,
          delivery: m.sender != 'player'
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
    ];
    return ListView(
      key: const Key('support.list'),
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      children: items,
    );
  }
}

class _SupportTitle extends StatelessWidget {
  const _SupportTitle();

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 18,
          backgroundColor: tokens.primary.withValues(alpha: 0.14),
          child: Icon(
            Icons.support_agent_rounded,
            color: tokens.primary,
            size: AppSizes.iconMd,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      supportName,
                      key: const Key('support.title'),
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const AppBadge(
                    key: Key('support.official'),
                    label: 'رسمي',
                    tone: AppBadgeTone.primary,
                    icon: Icons.verified_rounded,
                  ),
                ],
              ),
              Text(
                'الحساب الرسمي · نرد في أقرب وقت',
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The first page failed: the reason, a retry, and the e-mail as the way
/// out.
class _LoadFailed extends ConsumerWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Center(
      child: SingleChildScrollView(
        key: const Key('support.loadFailed'),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: AppSizes.iconStateLg,
              color: tokens.textMuted,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('support.retry'),
              onPressed: () => unawaited(onRetry()),
              child: const Text('إعادة المحاولة'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              key: const Key('support.email'),
              onPressed: () => unawaited(_openEmail(context, ref)),
              child: const Text(
                'أو راسلنا على $nukhbaaSupportEmail',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [nukhbaaSupportUri] in the phone's mail app through the app's one
/// link opener; when nothing could open it, a line names the address.
Future<void> _openEmail(BuildContext context, WidgetRef ref) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  bool opened;
  try {
    opened = await ref.read(notificationLinkOpenerProvider)(nukhbaaSupportUri);
  } on Object {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(
        key: Key('support.email.failed'),
        content: Text(
          'تعذّر فتح تطبيق البريد، راسلنا على $nukhbaaSupportEmail',
        ),
      ),
    );
  }
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('support.loading'),
      reverse: true,
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
