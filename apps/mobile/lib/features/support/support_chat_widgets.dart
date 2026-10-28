/// The pieces both sides of the support chat draw (migration 0187): a
/// message bubble, the strip above the list, and the box to write in. The
/// player's chat (script 166) and the admins' conversation (script 167)
/// differ only in whose messages are "mine".
library;

import 'package:flutter/material.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/format/timestamps.dart';

/// Where a message of the reader's own stands.
enum SupportDelivery {
  /// On its way to the server.
  sending,

  /// The server refused it, or could not be reached.
  failed,

  /// Stored; the other side has not read it.
  sent,

  /// The other side read it.
  read,
}

/// One message: the reader's own on the start side (the right, in Arabic),
/// the other side's on the end side, each with its day and time; the
/// reader's own also with where it stands.
class SupportBubble extends StatelessWidget {
  const SupportBubble({
    super.key,
    required this.mine,
    required this.body,
    required this.senderLabel,
    this.createdAt,
    this.delivery,
    this.error,
    this.onRetry,
    this.image,
  });

  /// Whether the reader sent it.
  final bool mine;

  /// The text.
  final String body;

  /// Who sent it, for a screen reader.
  final String senderLabel;

  /// When it was sent (ISO-8601); null while it is not stored.
  final String? createdAt;

  /// Where the reader's own message stands; null for the other side's.
  final SupportDelivery? delivery;

  /// Why it failed, shown with a resend.
  final String? error;

  /// Sends a failed message again.
  final VoidCallback? onRetry;

  /// The picture that came with it (migration 0188), drawn above the text.
  final Widget? image;

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
      SupportDelivery.sending => 'جارٍ الإرسال',
      SupportDelivery.failed => 'لم تُرسل',
      _ => at == null ? '' : formatDayAndTime(context, at),
    };
    final Widget? status = switch (delivery) {
      SupportDelivery.sending => Icon(
        Icons.schedule_rounded,
        key: const Key('support.status.sending'),
        size: AppSizes.iconInline,
        color: meta,
      ),
      SupportDelivery.failed => Icon(
        Icons.error_outline_rounded,
        key: const Key('support.status.failed'),
        size: AppSizes.iconInline,
        color: tokens.errorText,
      ),
      SupportDelivery.sent => Icon(
        Icons.done_rounded,
        key: const Key('support.status.sent'),
        size: AppSizes.iconInline,
        color: meta,
      ),
      SupportDelivery.read => Icon(
        Icons.done_all_rounded,
        key: const Key('support.status.read'),
        size: AppSizes.iconInline,
        color: meta,
      ),
      null => null,
    };

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
              Semantics(
                label: senderLabel,
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
                        ?image,
                        if (body.isNotEmpty)
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
                            ?status,
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (error != null)
                TextButton.icon(
                  key: const Key('support.resend'),
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

/// A line across the top of the chat: no connection, or the conversation
/// is closed.
class SupportStrip extends StatelessWidget {
  const SupportStrip({super.key, required this.text, this.danger = false});

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

/// The box to write in and its send button, asleep while nothing is typed.
class SupportComposer extends StatelessWidget {
  const SupportComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttach,
  });

  /// The longest message, as the server allows it.
  static const int maxLength = 2000;

  final TextEditingController controller;
  final VoidCallback? onSend;

  /// Picks a picture to send (migration 0188); no button when null.
  final VoidCallback? onAttach;

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
            if (onAttach != null) ...<Widget>[
              IconButton(
                key: const Key('support.attach'),
                tooltip: 'إرفاق صورة',
                onPressed: onAttach,
                icon: const Icon(Icons.image_outlined),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: TextField(
                key: const Key('support.input'),
                controller: controller,
                minLines: 1,
                maxLines: 5,
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
                  hintText: 'اكتب رسالتك…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              key: const Key('support.send'),
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
