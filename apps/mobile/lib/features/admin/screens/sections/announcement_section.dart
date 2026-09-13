/// إرسال إشعار إداري — شاشة مستقلة: عنوان ← نص التعليمات ← إرسال للجميع.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/providers.dart';
import '../../widgets/admin_ui_kit.dart';

/// شاشة إرسال تعليمات المشرف إلى كل المستخدمين النشطين.
///
/// النصّ يُحفظ مرّة واحدة في `notification.announcements`، ثم يُنشأ لكل
/// مستخدم إشعار يشير إليه؛ فلا يُكرَّر النصّ في قاعدة البيانات. الخادم وحده
/// يحدّد المستلمين — لا يرسل التطبيق أي قائمة مستخدمين.
///
/// لا يوجد Riverpod codegen هنا عن قصد: الحالة (جارٍ الإرسال / خطأ / نجاح)
/// محلّية بالكامل لهذه الشاشة ولا يشاركها أي سطح آخر، فإضافة provider مولَّد
/// كانت ستُلزم إعادة توليد `admin_providers.g.dart` دون فائدة.
class AnnouncementSection extends ConsumerStatefulWidget {
  /// ينشئ القسم.
  const AnnouncementSection({super.key});

  @override
  ConsumerState<AnnouncementSection> createState() =>
      _AnnouncementSectionState();
}

class _AnnouncementSectionState extends ConsumerState<AnnouncementSection> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  bool _inFlight = false;
  AppError? _error;
  int? _sentTo;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_inFlight &&
      _title.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty;

  Future<void> _send() async {
    setState(() {
      _inFlight = true;
      _error = null;
      _sentTo = null;
    });
    final AdminApi api = ref.read(adminApiProvider);
    final Result<AnnouncementPublishedDto> result = await api
        .publishAnnouncement(
          title: _title.text.trim(),
          body: _body.text.trim(),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _inFlight = false;
      switch (result) {
        case Ok<AnnouncementPublishedDto>(:final value):
          _sentTo = value.recipients;
          _title.clear();
          _body.clear();
        case Err<AnnouncementPublishedDto>(:final error):
          _error = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const AdminSectionHeader(
          title: 'إرسال إشعار',
          subtitle:
              'تصل التعليمات إلى كل المستخدمين النشطين داخل التطبيق '
              'وعلى أجهزتهم',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminTextField(
                key: const Key('admin.announcement.titleField'),
                controller: _title,
                hint: 'العنوان (مثال: تنبيه بخصوص مباريات الجمعة)',
                prefixIcon: Icons.title_rounded,
                enabled: !_inFlight,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('admin.announcement.bodyField'),
                controller: _body,
                enabled: !_inFlight,
                maxLines: 6,
                maxLength: 1000,
                decoration: const InputDecoration(
                  hintText: 'نص التعليمات كما سيقرؤه المستخدم',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AdminErrorBanner(
                  message: ErrorPresenter.message(_error!),
                  debugDetail: 'تعذر إرسال الإشعار',
                ),
              ],
              if (_sentTo != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AdminSuccessBanner(
                  message: 'أُرسل الإشعار إلى $_sentTo مستخدمًا',
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.announcement.sendButton'),
                label: 'إرسال للجميع',
                icon: Icons.campaign_rounded,
                loading: _inFlight,
                onPressed: _canSend ? _send : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
