/// تبويب «سجلي» (script 347, owner decision 2026-11-26): the owners' own log,
/// the newest first -- what an owner seat did on `/owner` and inside the
/// admins' tools: what, where, when and the result. It reads `GET /owner/audit`
/// (an owner seat alone: the server answers anyone else as a path with no
/// route).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_radius.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../widgets/admin_ui_kit.dart';
import 'owner_admin_activity_section.dart';

// NK347_01
/// `GET /owner/audit`.
final ownerAuditProvider = FutureProvider.autoDispose<OwnerAuditLogDto>((
  ref,
) async {
  return switch (await ref.watch(adminApiProvider).ownerAudit()) {
    Ok<OwnerAuditLogDto>(:final value) => value,
    Err<OwnerAuditLogDto>(:final error) => throw error,
  };
}, retry: (_, _) => null);

/// The line's `source` for a request to `/owner`.
const String ownerAuditSourceOwner = 'owner';

/// The line's `source` for a change made inside the admins' tools.
const String ownerAuditSourceAdmin = 'admin';

const Map<String, String> _ownerPages = <String, String>{
  'admins': 'المشرفون',
  'announcements': 'الإعلانات',
  'crests': 'الشعارات',
  'hidden-accounts': 'المخفيون',
  'mode': 'وضع التطبيق',
  'person-links': 'الأشخاص',
  'switches': 'المفاتيح',
};

/// What the line did, in words. A request to `/owner` reads as the owners'
/// page it came from; an admin-tool change reads as in «سجل المشرفين». One
/// this build does not know keeps its method and path: a log must not hide
/// what it does not understand.
String ownerAuditLabel(OwnerAuditEntryDto line) {
  if (line.source == ownerAuditSourceOwner) {
    final List<String> parts = <String>[
      for (final String part in line.path.split('/'))
        if (part.isNotEmpty) part,
    ];
    final String? page = parts.length >= 2 && parts[0] == 'owner'
        ? _ownerPages[parts[1]]
        : null;
    if (page != null) return 'صفحة المالك: $page';
  }
  return adminActivityLabel(line.method, line.path);
}

/// Where the line came from, in words.
String ownerAuditSourceLabel(String source) => switch (source) {
  ownerAuditSourceOwner => 'صفحة المالك',
  ownerAuditSourceAdmin => 'أدوات المشرفين',
  _ => source,
};

/// The owners' tab of what an owner seat did.
class OwnerAuditSection extends ConsumerWidget {
  /// Creates the section.
  const OwnerAuditSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AsyncValue<OwnerAuditLogDto> state = ref.watch(ownerAuditProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(ownerAuditProvider.future),
      child: ListView(
        key: const Key('owner.audit.list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: <Widget>[
          const AdminSectionHeader(
            title: 'سجلي',
            subtitle:
                'كل ما فعلته أنت: ماذا، وأين، ومتى. لا يراه مشرف ولا لاعب.',
          ),
          ...switch (state) {
            AsyncData<OwnerAuditLogDto>(:final value)
                when value.entries.isEmpty =>
              <Widget>[
                Text(
                  'لا إجراءات بعد.',
                  key: const Key('owner.audit.empty'),
                  style: TextStyle(color: t.textSecondary),
                ),
              ],
            AsyncData<OwnerAuditLogDto>(:final value) => <Widget>[
              for (final OwnerAuditEntryDto line in value.entries)
                _AuditCard(line: line),
            ],
            AsyncError<OwnerAuditLogDto>(:final error) => <Widget>[
              Text(
                ErrorPresenter.messageOf(error),
                key: const Key('owner.audit.error'),
                style: TextStyle(color: t.errorText),
              ),
              TextButton(
                key: const Key('owner.audit.retry'),
                onPressed: () => ref.invalidate(ownerAuditProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ],
            _ => <Widget>[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(
                    key: Key('owner.audit.loading'),
                  ),
                ),
              ),
            ],
          },
        ],
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.line});

  final OwnerAuditEntryDto line;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String? target = line.target;
    final String? result = line.result;
    final String prefix = 'owner.audit.item.${line.source}.${line.id}';
    final TextStyle? small = context.text.bodySmall?.copyWith(
      color: t.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AdminCard(
        key: Key(prefix),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              ownerAuditLabel(line),
              style: context.text.titleSmall?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              key: Key('$prefix.source'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                borderRadius: AppRadius.brSm,
                border: Border.all(color: t.border),
              ),
              child: Text(ownerAuditSourceLabel(line.source), style: small),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (line.source == ownerAuditSourceOwner)
              Text(
                '${line.method} ${line.path}',
                key: Key('$prefix.request'),
                textDirection: TextDirection.ltr,
                style: small,
              ),
            if (target != null)
              Text(
                result == null
                    ? 'على: $target'
                    : 'على: $target · النتيجة الآن $result',
                style: small,
              ),
            Text(
              formatTimestamp(context, line.at.toIso8601String()),
              style: context.text.bodySmall?.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
