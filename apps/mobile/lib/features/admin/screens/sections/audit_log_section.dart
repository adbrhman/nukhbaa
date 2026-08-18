library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/ui/ui.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/widgets/async_list_view.dart';
import '../../admin_providers.dart';

class AuditLogSection extends ConsumerWidget {
  const AuditLogSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AuditLogDto> log = ref.watch(auditLogProvider);
    return AsyncListView<AuditEntryDto>(
      value: log.whenData((dto) => dto.entries),
      emptyMessage: l10n.adminAuditLogEmpty,
      onRetry: () => ref.invalidate(auditLogProvider),
      itemBuilder: (context, entry) {
        final AppTokens tokens = context.tokens;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: AppCard(
            key: Key('admin.audit.item.${entry.id}'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.action,
                        key: Key('admin.audit.action.${entry.id}'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${entry.targetRef}${entry.reason != null ? ' — ${entry.reason}' : ''}',
                        key: Key('admin.audit.detail.${entry.id}'),
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  entry.occurredAt,
                  key: Key('admin.audit.occurredAt.${entry.id}'),
                  style: TextStyle(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
