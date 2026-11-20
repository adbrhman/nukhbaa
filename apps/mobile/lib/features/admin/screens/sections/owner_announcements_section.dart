/// تبويب «الإعلانات» في «الإدارة العامة للمالك» (السكربت 290، قرار المالك
/// 2026-11-20، تعديل على ق٠٧، فوق الهجرة 0220): إعلان أي مشرف غير المالك
/// ينتظر هنا، فينشره المالك لكل اللاعبين النشطين كما كتبه المشرف، أو
/// يرفضه فلا يصل أحداً، ويرى المشرف «لم يُعتمد للنشر» بلا سبب.
///
/// إعلانات المالك نفسه تُنشر فوراً ولا تمر من هنا. والخادم يجيب غير
/// المالكَين بمسار غير موجود.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../widgets/admin_ui_kit.dart';

// NK290_14
/// `GET /owner/announcements`.
final ownerAnnouncementsProvider =
    FutureProvider.autoDispose<AnnouncementRequestsDto>((ref) async {
      return switch (await ref.watch(adminApiProvider).ownerAnnouncements()) {
        Ok<AnnouncementRequestsDto>(:final value) => value,
        Err<AnnouncementRequestsDto>(:final error) => throw error,
      };
    });

String _statusLabel(AnnouncementRequestDto line) => switch (line.status) {
  'pending' => 'ينتظر قرارك',
  'published' => 'نُشر لـ${line.recipients ?? 0} لاعب',
  'rejected' => 'رُفض',
  _ => line.status,
};

/// The owners' review of the admins' announcements.
class OwnerAnnouncementsSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const OwnerAnnouncementsSection({super.key});

  @override
  ConsumerState<OwnerAnnouncementsSection> createState() =>
      _OwnerAnnouncementsSectionState();
}

class _OwnerAnnouncementsSectionState
    extends ConsumerState<OwnerAnnouncementsSection> {
  bool _busy = false;

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _decide(AnnouncementRequestDto line, bool publish) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(publish ? 'نشر الإعلان للجميع؟' : 'رفض الإعلان؟'),
        content: Text(
          publish
              ? 'يصل «${line.title}» إلى صندوق كل لاعب نشط وإلى هاتفه، كما '
                    'كتبه ${line.authorName}، ولا يمكن سحبه بعد النشر.'
              : 'لا يصل «${line.title}» إلى أحد، ويرى ${line.authorName} '
                    'أنه لم يُعتمد للنشر، بلا سبب.',
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('admin.ownerAnnouncements.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('admin.ownerAnnouncements.confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(publish ? 'انشر' : 'ارفض'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    final Result<String> result = await ref
        .read(adminApiProvider)
        .decideAnnouncement(line.id, publish: publish);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<String>():
        _say(publish ? 'نُشر «${line.title}»' : 'رُفض «${line.title}»');
        ref.invalidate(ownerAnnouncementsProvider);
      case Err<String>(:final error):
        _say(ErrorPresenter.message(error));
        ref.invalidate(ownerAnnouncementsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<AnnouncementRequestsDto> state = ref.watch(
      ownerAnnouncementsProvider,
    );
    return state.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (Object e, _) => ListView(
        children: <Widget>[
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  ErrorPresenter.messageOf(e),
                  key: const Key('admin.ownerAnnouncements.loadError'),
                  style: TextStyle(color: tokens.errorText),
                ),
                TextButton(
                  key: const Key('admin.ownerAnnouncements.retry'),
                  onPressed: () => ref.invalidate(ownerAnnouncementsProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ],
      ),
      data: (AnnouncementRequestsDto data) => ListView(
        key: const Key('admin.ownerAnnouncements.list'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: <Widget>[
          const AdminSectionHeader(
            title: 'إعلانات المشرفين',
            subtitle:
                'إعلان أي مشرف ينتظر هنا قبل أن يصل إلى اللاعبين. انشره كما '
                'كتبه، أو ارفضه فيرى المشرف أنه لم يُعتمد للنشر، بلا سبب. '
                'إعلاناتك تُنشر فوراً.',
          ),
          if (data.requests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'لا إعلان ينتظر',
                key: Key('admin.ownerAnnouncements.none'),
              ),
            ),
          for (final AnnouncementRequestDto line in data.requests)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AdminCard(
                key: Key('admin.ownerAnnouncements.row.${line.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      line.title,
                      style: context.text.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      line.body,
                      style: context.text.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${line.authorName} · '
                      '${formatTimestamp(context, line.createdAt.toIso8601String())}'
                      ' · ${_statusLabel(line)}',
                      key: Key('admin.ownerAnnouncements.status.${line.id}'),
                      style: context.text.bodySmall?.copyWith(
                        color: line.status == 'pending'
                            ? tokens.primaryText
                            : tokens.textSecondary,
                        fontWeight: line.status == 'pending'
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    if (line.status == 'pending') ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: <Widget>[
                          AdminSecondaryButton(
                            key: Key(
                              'admin.ownerAnnouncements.publish.${line.id}',
                            ),
                            label: 'انشر للجميع',
                            semanticsLabel: 'انشر: ${line.title}',
                            icon: Icons.campaign_rounded,
                            onPressed: _busy
                                ? null
                                : () => unawaited(_decide(line, true)),
                          ),
                          AdminSecondaryButton(
                            key: Key(
                              'admin.ownerAnnouncements.reject.${line.id}',
                            ),
                            label: 'ارفض',
                            semanticsLabel: 'ارفض: ${line.title}',
                            icon: Icons.block_rounded,
                            onPressed: _busy
                                ? null
                                : () => unawaited(_decide(line, false)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
