/// «رسائل الدعم»: the admins' inbox of the support chat (migration 0187,
/// script 167). Every admin reads the same inbox and answers as one name,
/// «دعم نُخبة».
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_sizes.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../../../core/ui/app_badge.dart';
import '../../../../core/ui/app_empty_state.dart';
import '../../../../core/ui/app_error_state.dart';
import '../../../../core/ui/app_skeleton.dart';
import '../../../../core/ui/segmented_pills.dart';
import '../../admin_support_providers.dart';
import '../admin_support_conversation_screen.dart';

/// The inbox: conversations by their last message, newest first, with the
/// filters «الكل / غير مقروءة / مفتوحة / مغلقة» and a search by the
/// player's name. Read again every [pollEvery] while it is on screen.
class AdminSupportSection extends ConsumerStatefulWidget {
  const AdminSupportSection({
    super.key,
    this.pollEvery = const Duration(seconds: 15),
  });

  /// How often the open inbox is read again.
  final Duration pollEvery;

  /// The filters, in the order of the pills.
  static const List<String> filters = <String>[
    'all',
    'unread',
    'open',
    'closed',
  ];

  @override
  ConsumerState<AdminSupportSection> createState() =>
      _AdminSupportSectionState();
}

class _AdminSupportSectionState extends ConsumerState<AdminSupportSection> {
  final TextEditingController _search = TextEditingController();
  int _filter = 0;
  SupportInboxDto? _inbox;
  AppError? _error;
  bool _loading = true;
  Timer? _poll;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(widget.pollEvery, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Reads the inbox for the filter and search shown now; an older answer
  /// that arrives after a newer request is dropped.
  Future<void> _load() async {
    final int generation = ++_generation;
    final Result<SupportInboxDto> result = await ref
        .read(adminApiProvider)
        .supportInbox(
          filter: AdminSupportSection.filters[_filter],
          search: _search.text,
        );
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok<SupportInboxDto>(:final value):
          _inbox = value;
          _error = null;
        case Err<SupportInboxDto>(:final error):
          // A failed poll keeps the list it has.
          if (_inbox == null) _error = error;
      }
    });
    ref.invalidate(adminSupportWaitingProvider);
  }

  void _onFilter(int index) {
    setState(() {
      _filter = index;
      _loading = true;
      _inbox = null;
    });
    unawaited(_load());
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_load());
    });
  }

  Future<void> _open(SupportConversationDto c) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AdminSupportConversationScreen(
          conversationId: c.id,
          playerName: c.playerName,
        ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final SupportInboxDto? inbox = _inbox;
    return Column(
      key: const Key('admin.support'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: SegmentedPills(
            key: const Key('admin.support.filters'),
            keyPrefix: 'admin.support.filter',
            labels: <String>[
              'الكل',
              inbox == null || inbox.unreadConversations == 0
                  ? 'غير مقروءة'
                  : 'غير مقروءة (${inbox.unreadConversations})',
              'مفتوحة',
              'مغلقة',
            ],
            selectedIndex: _filter,
            onSelected: _onFilter,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TextField(
            key: const Key('admin.support.search'),
            controller: _search,
            onChanged: _onSearch,
            decoration: const InputDecoration(
              hintText: 'ابحث باسم اللاعب',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(child: _list(inbox)),
      ],
    );
  }

  Widget _list(SupportInboxDto? inbox) {
    if (_loading && inbox == null) {
      return ListView(
        key: const Key('admin.support.loading'),
        children: const <Widget>[
          AppSkeletonListTile(),
          AppSkeletonListTile(),
          AppSkeletonListTile(),
        ],
      );
    }
    final AppError? error = _error;
    if (inbox == null) {
      return AppErrorState(
        message: error == null ? null : ErrorPresenter.message(error),
        onRetry: () => unawaited(_load()),
      );
    }
    if (inbox.conversations.isEmpty) {
      return AppEmptyState(
        key: const Key('admin.support.empty'),
        icon: Icons.mark_chat_read_rounded,
        title: _filter == 0 && _search.text.trim().isEmpty
            ? 'لا رسائل من اللاعبين بعد'
            : 'لا محادثات هنا',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('admin.support.list'),
        padding: const EdgeInsets.only(bottom: AppSpacing.x3l),
        itemCount: inbox.conversations.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int i) {
          final SupportConversationDto c = inbox.conversations[i];
          return _ConversationTile(conversation: c, onTap: () => _open(c));
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final SupportConversationDto conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final SupportConversationDto c = conversation;
    final bool waiting = c.supportUnread > 0;
    final String name = c.playerName.trim().isEmpty ? 'لاعب' : c.playerName;
    final String status = switch (c.status) {
      'closed' => 'مغلقة',
      'archived' => 'مؤرشفة',
      _ => 'مفتوحة',
    };
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: Key('admin.support.conversation.${c.id}'),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: tokens.primary.withValues(alpha: 0.14),
          child: Text(
            name.characters.first,
            style: text.titleMedium?.copyWith(color: tokens.primaryText),
          ),
        ),
        title: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: text.bodyLarge?.copyWith(
            color: tokens.textPrimary,
            fontWeight: waiting ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (c.lastSender == 'support')
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: AppSpacing.xs,
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        size: AppSizes.iconXs,
                        color: tokens.textMuted,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      c.lastMessagePreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: waiting
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (waiting)
                    AppBadge(
                      key: Key('admin.support.unread.${c.id}'),
                      label: c.supportUnread > 9 ? '9+' : '${c.supportUnread}',
                      tone: AppBadgeTone.danger,
                    )
                  else
                    AppBadge(
                      label: status,
                      tone: c.status == 'open'
                          ? AppBadgeTone.primary
                          : AppBadgeTone.muted,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                formatDayAndTime(context, c.lastMessageAt),
                style: text.labelSmall?.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
