/// تبويب «سجل المشرفين» (script 300, owner decision 2026-11-21): every change
/// an admin made, the newest first, with his name, the player or match it
/// touched and that match's result as it stands now, so the owner can check
/// it. Nothing an admin does is refused for it; the server answers anyone
/// but the owners as a path with no route.
library;

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

// NK300_13
/// `GET /owner/admin-activity`.
final ownerAdminActivityProvider =
    FutureProvider.autoDispose<AdminActivityLogDto>((ref) async {
      return switch (await ref.watch(adminApiProvider).ownerAdminActivity()) {
        Ok<AdminActivityLogDto>(:final value) => value,
        Err<AdminActivityLogDto>(:final error) => throw error,
      };
    });

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

const Map<String, String> _labels = <String, String>{
  'POST /admin/users/:id/display-name': 'تغيير اسم لاعب',
  'POST /admin/users/:id/suspend': 'تعليق لاعب',
  'POST /admin/users/:id/reinstate': 'إعادة تفعيل لاعب',
  'POST /admin/announcements': 'طلب إعلان للاعبين',
  'PUT /admin/app/min-build': 'تغيير أدنى نسخة APK',
  'PUT /admin/app/min-play-build': 'تغيير أدنى نسخة Google Play',
  'POST /admin/errors/:id': 'تحديث حالة خطأ',
  'POST /admin/fixture-visibility': 'إخفاء مباراة أو إظهارها',
  'POST /admin/fixtures/:id/merge': 'دمج نسختين من مباراة',
  'POST /admin/leagues': 'إضافة دوري',
  'POST /admin/teams': 'إضافة نادٍ',
  'POST /competitions': 'إنشاء مسابقة',
  'POST /competitions/:id/seasons': 'بدء موسم',
  'POST /fixtures': 'إضافة مباراة',
  'PUT /fixtures/:id': 'تعديل مباراة',
  'PUT /fixtures/:id/result': 'تسجيل نتيجة مباراة',
  'POST /fixtures/:id/score': 'احتساب نقاط مباراة',
  'POST /fixtures/:id/ledger': 'ترحيل نقاط مباراة',
  'PUT /fixtures/:id/live-score': 'تصحيح نتيجة مباشرة',
  'DELETE /fixtures/:id/live-score': 'إلغاء تصحيح نتيجة مباشرة',
  'POST /seasons/:id/fixtures': 'ربط مباراة بالموسم',
  'DELETE /seasons/:id/fixtures/:id': 'حذف مباراة من الموسم',
};

const Map<String, String> _h2h = <String, String>{
  'exclusions': 'استبعاد لاعب',
  'excusals': 'إعذار لاعب',
  'extra-groups': 'مجموعات إضافية',
  'jobs': 'تشغيل مهمة',
  'pilot': 'التجربة',
  'relegations': 'الهبوط',
  'rounds': 'الجولات',
  'seats': 'المقاعد',
  'settings': 'الإعدادات',
};

/// What the request [method] [path] did, in words. One this build does not
/// know keeps its method and path: a log must not hide what it does not
/// understand.
String adminActivityLabel(String method, String path) {
  final List<String> parts = <String>[
    for (final String part in path.split('/'))
      if (part.isNotEmpty) _uuid.hasMatch(part) ? ':id' : part,
  ];
  final String? known = _labels['$method /${parts.join('/')}'];
  if (known != null) return known;
  if (parts.length >= 2 && parts[0] == 'admin') {
    switch (parts[1]) {
      case 'h2h':
        final String what = parts.length > 2 ? parts[2] : '';
        return 'دوري المواجهات: ${_h2h[what] ?? what}';
      case 'support':
        return 'الدعم: رسالة أو تعديل في محادثة';
      case 'champions':
        return 'بطل الشهر';
      case 'cup-champions':
        return 'أبطال كأس النخبة';
    }
  }
  return 'تعديل ($method $path)';
}

/// The owners' tab of what the admins changed.
class OwnerAdminActivitySection extends ConsumerWidget {
  /// Creates the section.
  const OwnerAdminActivitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AsyncValue<AdminActivityLogDto> state = ref.watch(
      ownerAdminActivityProvider,
    );
    return RefreshIndicator(
      onRefresh: () => ref.refresh(ownerAdminActivityProvider.future),
      child: ListView(
        key: const Key('admin.activity.list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: <Widget>[
          const AdminSectionHeader(
            title: 'سجل المشرفين',
            subtitle:
                'كل تعديل قام به مشرف: ماذا، ومن، ومتى، وعلى من. '
                'الاسم والنتيجة كما هما الآن.',
          ),
          ...switch (state) {
            AsyncData<AdminActivityLogDto>(:final value)
                when value.entries.isEmpty =>
              <Widget>[
                Text(
                  'لا تعديلات بعد.',
                  key: const Key('admin.activity.empty'),
                  style: TextStyle(color: t.textSecondary),
                ),
              ],
            AsyncData<AdminActivityLogDto>(:final value) => <Widget>[
              for (final AdminActivityDto line in value.entries)
                _ActivityCard(line: line),
            ],
            AsyncError<AdminActivityLogDto>(:final error) => <Widget>[
              Text(
                ErrorPresenter.messageOf(error),
                key: const Key('admin.activity.error'),
                style: TextStyle(color: t.errorText),
              ),
              TextButton(
                onPressed: () => ref.invalidate(ownerAdminActivityProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ],
            _ => <Widget>[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(),
                ),
              ),
            ],
          },
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.line});

  final AdminActivityDto line;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String? target = line.target;
    final String? result = line.result;
    final TextStyle? small = context.text.bodySmall?.copyWith(
      color: t.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AdminCard(
        key: Key('admin.activity.${line.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              adminActivityLabel(line.method, line.path),
              style: context.text.titleSmall?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('المشرف: ${line.actorName}', style: small),
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
