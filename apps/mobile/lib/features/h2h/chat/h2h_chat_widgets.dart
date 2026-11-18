/// The pieces of the group chat's screen (migration 0216, script 282): a
/// message bubble, the rules every player accepts first, and the box to
/// write in.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/format/timestamps.dart';
import 'h2h_chat_texts.dart';

/// Where a message of the reader's own stands.
enum H2hChatDelivery {
  /// On its way to the server.
  sending,

  /// The server refused it, or could not be reached.
  failed,

  /// Stored.
  sent,
}

/// One message: the reader's own on the start side (the right, in Arabic),
/// the others' on the end side with the sender's name above. A long press
/// on another player's message opens its menu (report, block).
class H2hChatBubble extends StatelessWidget {
  const H2hChatBubble({
    super.key,
    required this.mine,
    required this.body,
    this.senderName,
    this.createdAt,
    this.delivery,
    this.error,
    this.onRetry,
    this.onMenu,
  });

  /// Whether the reader wrote it.
  final bool mine;

  /// The text.
  final String body;

  /// Who wrote it; shown above the text of another player's message.
  final String? senderName;

  /// When it was sent (ISO-8601); null while it is not stored.
  final String? createdAt;

  /// Where the reader's own message stands; null for the others'.
  final H2hChatDelivery? delivery;

  /// Why it failed, shown with a resend.
  final String? error;

  /// Sends a failed message again.
  final VoidCallback? onRetry;

  /// Opens the message's menu; null for the reader's own.
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final Color fill = mine ? tokens.primary : tokens.surfaceElevated;
    final Color ink = mine ? tokens.onPrimary : tokens.textPrimary;
    final Color meta = mine
        ? tokens.onPrimary.withValues(alpha: 0.8)
        : tokens.textSecondary;
    final double maxWidth = MediaQuery.sizeOf(context).width * 0.78;
    final String? at = createdAt;
    final String when = switch (delivery) {
      H2hChatDelivery.sending => 'جارٍ الإرسال',
      H2hChatDelivery.failed => 'لم تُرسل',
      _ => at == null ? '' : formatDayAndTime(context, at),
    };
    final String? name = mine ? null : senderName;

    return Align(
      alignment: mine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: <Widget>[
              GestureDetector(
                onLongPress: onMenu,
                child: Semantics(
                  label: mine ? 'أنت' : (senderName ?? ''),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadiusDirectional.only(
                        topStart: const Radius.circular(AppRadius.lg),
                        topEnd: const Radius.circular(AppRadius.lg),
                        bottomStart: Radius.circular(
                          mine ? AppRadius.xs : AppRadius.lg,
                        ),
                        bottomEnd: Radius.circular(
                          mine ? AppRadius.lg : AppRadius.xs,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (name != null && name.isNotEmpty)
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelMedium?.copyWith(
                                color: tokens.primaryText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          Text(
                            body,
                            style: text.bodyLarge?.copyWith(color: ink),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              Text(
                                when,
                                style: text.labelSmall?.copyWith(color: meta),
                              ),
                              if (delivery == H2hChatDelivery.failed)
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: AppSizes.iconInline,
                                  color: tokens.errorText,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (error != null)
                TextButton.icon(
                  key: const Key('h2hChat.resend'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('$error · إعادة الإرسال'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line across the top of the chat: no connection.
class H2hChatStrip extends StatelessWidget {
  const H2hChatStrip({super.key, required this.text, this.danger = false});

  /// What it says.
  final String text;

  /// Red when something is wrong, plain otherwise.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      width: double.infinity,
      color: danger ? tokens.errorContainer : tokens.surfaceElevated,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        text,
        style: context.text.bodySmall?.copyWith(
          color: danger ? tokens.errorText : tokens.textSecondary,
        ),
      ),
    );
  }
}

/// The rules a player accepts before he reads or writes in the chat, and the
/// button that accepts them.
class H2hChatRulesGate extends StatelessWidget {
  const H2hChatRulesGate({
    super.key,
    required this.onAccept,
    this.accepting = false,
  });

  /// Accepts the rules.
  final VoidCallback onAccept;

  /// Whether the answer is on its way.
  final bool accepting;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Center(
      child: SingleChildScrollView(
        key: const Key('h2hChat.rules'),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.forum_outlined,
                  color: tokens.primary,
                  size: AppSizes.iconMd,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    h2hChatRulesTitle,
                    style: text.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            for (final String rule in h2hChatRules)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '•',
                      style: text.bodyLarge?.copyWith(
                        color: tokens.primaryText,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        rule,
                        style: text.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('h2hChat.accept'),
                onPressed: accepting ? null : onAccept,
                child: const Text('أوافق وأبدأ الدردشة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The box to write in and its send button, asleep while nothing is typed.
class H2hChatComposer extends StatelessWidget {
  const H2hChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
  });

  /// The longest message, as the server allows it.
  static const int maxLength = 500;

  final TextEditingController controller;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.backgroundElevated,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('h2hChat.input'),
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: maxLength,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                buildCounter:
                    (
                      BuildContext context, {
                      required int currentLength,
                      required bool isFocused,
                      required int? maxLength,
                    }) => null,
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالة لمجموعتك…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              key: const Key('h2hChat.send'),
              tooltip: 'إرسال',
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
