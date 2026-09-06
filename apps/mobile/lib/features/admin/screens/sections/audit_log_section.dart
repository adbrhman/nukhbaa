library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/format/timestamps.dart';
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
                        _actionLabel(entry.action),
                        key: Key('admin.audit.action.${entry.id}'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _detailLine(entry),
                        key: Key('admin.audit.detail.${entry.id}'),
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  formatTimestamp(context, entry.occurredAt),
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

/// The Arabic reading of an `admin.audit_action` enum value.
///
/// The log used to render the raw enum name (`fixture_predictions_viewed`)
/// straight from the DTO. The map below covers every value the enum has had
/// since migration 0010, including the two added later by 0015 and 0023. An
/// unknown value -- a future migration this build predates -- falls through
/// to the raw name rather than disappearing from the log, which for an audit
/// trail matters more than looking tidy.
String _actionLabel(String action) => switch (action) {
  'user_suspended' => 'تعليق مستخدم',
  'user_reinstated' => 'إعادة تفعيل مستخدم',
  'participant_ledger_viewed' => 'عرض سجل نقاط مشارك',
  'fixture_result_recorded' => 'تسجيل نتيجة مباراة',
  'round_scored' => 'احتساب نقاط جولة',
  'round_posted_to_ledger' => 'ترحيل نقاط جولة إلى السجل',
  'competition_created' => 'إنشاء مسابقة',
  'season_started' => 'بدء موسم',
  'round_opened' => 'فتح جولة',
  'round_locked' => 'إغلاق جولة',
  'fixture_linked_to_round' => 'ربط مباراة بجولة',
  'round_predictions_viewed' => 'عرض توقعات جولة',
  'fixture_predictions_viewed' => 'عرض توقعات مباراة',
  _ => action,
};

/// The admin's reason first, then a short handle for the target.
///
/// `targetRef` is a bare UUID in almost every entry; 36 characters of hex
/// crowd out the reason text and tell a reader nothing. The first segment is
/// enough to match an entry against a row when someone is actually
/// investigating, so only that is shown.
String _detailLine(AuditEntryDto entry) {
  final String ref = _shortRef(entry.targetRef);
  final String? reason = entry.reason;
  return reason == null ? ref : '$reason — $ref';
}

String _shortRef(String targetRef) {
  final bool looksLikeUuid =
      targetRef.length == 36 && targetRef.split('-').length == 5;
  return looksLikeUuid ? '#${targetRef.substring(0, 8)}' : targetRef;
}
