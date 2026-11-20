/// إرسال إشعار إداري — شاشة مستقلة: عنوان ← نص التعليمات ← إرسال للجميع.
library;

import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/arabic_count.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../widgets/admin_ui_kit.dart';
import '../../widgets/app_release_card.dart';

// NK290_13
/// `GET /admin/announcements/mine` (script 290): what this admin sent for
/// review, and where each stands.
final myAnnouncementsProvider =
    FutureProvider.autoDispose<AnnouncementRequestsDto>((ref) async {
      return switch (await ref.watch(adminApiProvider).myAnnouncements()) {
        Ok<AnnouncementRequestsDto>(:final value) => value,
        Err<AnnouncementRequestsDto>(:final error) => throw error,
      };
    });

/// What an admin reads about one announcement he sent (script 290): never
/// who reviews it.
String announcementStatusLabel(String status) => switch (status) {
  AnnouncementPublishedDto.pending => 'بانتظار المراجعة',
  AnnouncementPublishedDto.rejected => 'لم يُعتمد للنشر',
  _ => 'نُشر',
};

/// شاشة إرسال تعليمات المشرف إلى كل المستخدمين النشطين.
///
/// إعلان المالك يُنشر فوراً، وإعلان أي مشرف آخر ينتظر المراجعة قبل نشره
/// (السكربت 290)، ويرى المشرف حالته في «ما أرسلته».
///
/// النصّ يُحفظ مرّة واحدة في `notification.announcements`، ثم يُنشأ لكل
/// مستخدم إشعار يشير إليه؛ فلا يُكرَّر النصّ في قاعدة البيانات. الخادم وحده
/// يحدّد المستلمين — لا يرسل التطبيق أي قائمة مستخدمين.
///
/// قبل الإرسال حوار تأكيد يعرض الرسالة كما ستصل، ولكل رسالة معرّف طلب
/// (`request_id`) يُصنع معها ويُعاد مع كل إعادة محاولة لها (تدقيق M-14):
/// إن انتهت المهلة وأعاد المشرف الضغط، فهو الإعلان نفسه ولا يصل أحداً
/// مرتين. رسالة جديدة تأخذ معرّفاً جديداً.
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
  String _sentStatus = AnnouncementPublishedDto.published;

  /// معرّف الرسالة المكتوبة الآن، والنص الذي صُنع له.
  String? _requestId;
  String? _requestFor;

  @override
  void initState() {
    super.initState();
    // العنوان يُكتب غالبًا بعد نص التعليمات، و AdminTextField لا يستدعي أي
    // onChanged يُعيد بناء هذا الأب عند تعديله -- فيبقى الزر عالقًا على حالة
    // _canSend القديمة (معطّلاً) حتى لو صار كِلا الحقلين ممتلئين فعليًا.
    // الاستماع مباشرةً لكِلا المتحكِّمين يضمن إعادة البناء عند أي تغيير في
    // أيّهما، بصرف النظر عمّا إذا كان الحقل نفسه يملك onChanged أم لا.
    _title.addListener(_onFieldsChanged);
    _body.addListener(_onFieldsChanged);
  }

  void _onFieldsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _title.removeListener(_onFieldsChanged);
    _body.removeListener(_onFieldsChanged);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_inFlight &&
      _title.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty;

  Future<void> _confirmAndSend() async {
    final String title = _title.text.trim();
    final String body = _body.text.trim();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('admin.announcement.confirm'),
        title: const Text('إرسال إلى كل اللاعبين؟'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.xs),
              Text(body),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'يصل إلى صندوق كل لاعب نشط وإلى هاتفه، ولا يمكن سحبه بعد '
                'الإرسال.',
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('admin.announcement.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('admin.announcement.confirmSend'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('أرسل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _send(title: title, body: body);
  }

  Future<void> _send({required String title, required String body}) async {
    final String message = '$title\n$body';
    if (_requestFor != message) {
      _requestFor = message;
      _requestId = newAnnouncementRequestId(Random.secure());
    }
    setState(() {
      _inFlight = true;
      _error = null;
      _sentTo = null;
    });
    final AdminApi api = ref.read(adminApiProvider);
    final Result<AnnouncementPublishedDto> result = await api
        .publishAnnouncement(title: title, body: body, requestId: _requestId);
    if (!mounted) {
      return;
    }
    setState(() {
      _inFlight = false;
      switch (result) {
        case Ok<AnnouncementPublishedDto>(:final value):
          _sentTo = value.recipients;
          _sentStatus = value.status;
          _requestId = null;
          _requestFor = null;
          _title.clear();
          _body.clear();
        case Err<AnnouncementPublishedDto>(:final error):
          _error = error;
      }
    });
    if (result is Ok<AnnouncementPublishedDto>) {
      ref.invalidate(myAnnouncementsProvider);
    }
  }

  String _sentMessage(int sentTo) {
    if (_sentStatus == AnnouncementPublishedDto.pending) {
      return 'تم إرسال الإشعار، وسيُنشر في كل التطبيق بعد مراجعة محتواه.';
    }
    if (_sentStatus == AnnouncementPublishedDto.rejected) {
      return 'لم يُعتمد للنشر.';
    }
    return sentTo == 0
        ? 'وصل هذا الإشعار من قبل، فلم يُرسل مرة أخرى.'
        : 'أُرسل الإشعار إلى '
              '${arabicCount(sentTo, ArabicNoun.usersAfterPreposition)}';
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
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AdminErrorBanner(
                  message: ErrorPresenter.message(_error!),
                  detail: 'تعذر إرسال الإشعار',
                ),
              ],
              if (_sentTo case final int sentTo) ...[
                const SizedBox(height: AppSpacing.sm),
                AdminSuccessBanner(
                  key: const Key('admin.announcement.sent'),
                  message: _sentMessage(sentTo),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.announcement.sendButton'),
                label: 'إرسال للجميع',
                icon: Icons.campaign_rounded,
                loading: _inFlight,
                onPressed: _canSend ? _confirmAndSend : null,
              ),
            ],
          ),
        ),
        const _MyAnnouncements(),
        // Below the message: after raising the minimum, the announcement
        // reaches the builds that do not know it (batch 147).
        const SizedBox(height: AppSpacing.lg),
        const AppReleaseCard(),
      ],
    );
  }
}

/// A random UUID (version 4) for one announcement's `request_id`.
String newAnnouncementRequestId(Random random) {
  const String hex = '0123456789abcdef';
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < 32; i++) {
    if (i == 8 || i == 12 || i == 16 || i == 20) {
      out.write('-');
    }
    if (i == 12) {
      out.write('4');
    } else if (i == 16) {
      out.write(hex[8 + random.nextInt(4)]);
    } else {
      out.write(hex[random.nextInt(16)]);
    }
  }
  return out.toString();
}

/// «ما أرسلته»: the admin's latest announcements held for review and where
/// each stands (script 290). Nothing while there is none.
class _MyAnnouncements extends ConsumerWidget {
  const _MyAnnouncements();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AnnouncementRequestsDto> mine = ref.watch(
      myAnnouncementsProvider,
    );
    return mine.when(
      loading: () => const SizedBox.shrink(),
      error: (Object e, _) => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          'تعذر تحميل ما أرسلته',
          key: Key('admin.announcement.mine.error'),
        ),
      ),
      data: (AnnouncementRequestsDto data) {
        if (data.requests.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: AdminCard(
            key: const Key('admin.announcement.mine'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'ما أرسلته',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                for (final AnnouncementRequestDto line in data.requests)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      '${line.title} · ${announcementStatusLabel(line.status)}'
                      ' · ${formatTimestamp(context, line.createdAt.toIso8601String())}',
                      key: Key('admin.announcement.mine.${line.id}'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
