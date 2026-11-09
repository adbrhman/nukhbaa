/// لوحة المشرف لأبطال كأس النخبة (migration 0204): بجانب لوحة بطل الشهر.
///
/// يُتوَّج بطل كل مسار من مساراته الثلاثة تلقائيًا بعد النهائي (يقرّره
/// الخادم وحده). هنا يرى المشرف الأبطال، ويضيف صورة البطل إن وفّرها،
/// ويغيّرها أو يحذفها. بلا صورة يظهر البطل بصورته الشخصية ثم بحرفه الأول.
/// لا جائزة نقدية: التتويج لقب وبطاقة.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/providers.dart';
import '../../../../core/ui/app_dialog.dart';
import '../../../../core/ui/user_avatar.dart';
import '../../../leaderboards/cup_champions_providers.dart';
import '../../../leaderboards/widgets/champion_spotlight.dart';
import '../../widgets/admin_ui_kit.dart';
import 'champion_admin_section.dart';

/// The Elite Cup crowning panel of the admin hub.
class CupChampionsAdminSection extends ConsumerStatefulWidget {
  /// Creates the panel; [pickPhoto] replaces the gallery (tests).
  const CupChampionsAdminSection({this.pickPhoto, super.key});

  /// Opens the gallery; null uses the device's picker.
  final ChampionPhotoPicker? pickPhoto;

  @override
  ConsumerState<CupChampionsAdminSection> createState() =>
      _CupChampionsAdminSectionState();
}

class _CupChampionsAdminSectionState
    extends ConsumerState<CupChampionsAdminSection> {
  bool _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Picks a picture, checks it, and answers it; null (with a message) when
  /// it cannot be used.
  Future<ChampionPhoto?> _pick() async {
    final ChampionPhoto? photo;
    try {
      photo = await (widget.pickPhoto ?? pickChampionPhotoFromGallery)();
    } on Object {
      if (mounted) _snack('تعذّر فتح الصورة');
      return null;
    }
    if (photo == null || !mounted) return null;
    if (photo.bytes.length > championPhotoMaxBytes) {
      _snack('الصورة أكبر من 512 ك.ب، اختر صورة أصغر');
      return null;
    }
    return photo;
  }

  Future<void> _setPhoto(CupChampionDto champion) async {
    final ChampionPhoto? photo = await _pick();
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    final Result<CupChampionsDto> result = await ref
        .read(adminApiProvider)
        .setCupChampionPhoto(
          monthStart: champion.monthStart,
          place: champion.place,
          bytes: photo.bytes,
          contentType: photo.mime,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(cupChampionsProvider);
    _snack(switch (result) {
      Ok<CupChampionsDto>() => 'تم حفظ صورة البطل',
      Err<CupChampionsDto>(:final error) => ErrorPresenter.message(error),
    });
  }

  Future<void> _removePhoto(CupChampionDto champion) async {
    final bool? confirmed = await AppDialog.confirm(
      context,
      title: 'حذف الصورة',
      message:
          'تُحذف صورة ${champion.displayName} من ${cupPathName(champion.place)}، '
          'ويظهر بصورته الشخصية أو بحرفه الأول.',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final Result<CupChampionsDto> result = await ref
        .read(adminApiProvider)
        .removeCupChampionPhoto(
          monthStart: champion.monthStart,
          place: champion.place,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(cupChampionsProvider);
    _snack(switch (result) {
      Ok<CupChampionsDto>() => 'تم حذف الصورة',
      Err<CupChampionsDto>(:final error) => ErrorPresenter.message(error),
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CupChampionsDto> cup = ref.watch(cupChampionsProvider);
    return ListView(
      key: const Key('admin.cup.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'تتويج كأس النخبة',
          subtitle:
              'يُتوَّج بطل كل مسار وحده بعد النهائي. أضف هنا صورة البطل إن '
              'وفّرها، وبلا صورة يظهر بصورته الشخصية.',
        ),
        ...cup.when(
          loading: () => const <Widget>[
            Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (Object error, _) => <Widget>[
            AdminErrorBanner(
              key: const Key('admin.cup.error'),
              message: error is AppError
                  ? ErrorPresenter.message(error)
                  : 'تعذّر تحميل أبطال الكأس',
            ),
            TextButton(
              onPressed: () => ref.invalidate(cupChampionsProvider),
              child: const Text('إعادة المحاولة'),
            ),
          ],
          data: (CupChampionsDto data) => _champions(context, data),
        ),
      ],
    );
  }

  List<Widget> _champions(BuildContext context, CupChampionsDto data) {
    if (data.champions.isEmpty) {
      return const <Widget>[
        AdminEmptyState(
          key: Key('admin.cup.empty'),
          icon: Icons.emoji_events_outlined,
          title: 'لم يُتوَّج أحد في الكأس بعد',
        ),
      ];
    }
    final AppTokens t = context.tokens;
    final List<Widget> out = <Widget>[];
    String? month;
    for (final CupChampionDto c in data.champions) {
      if (c.monthStart != month) {
        month = c.monthStart;
        out.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              championMonthName(
                cupMonthLabel(c.monthStart),
                const Locale('ar'),
              ),
              style: context.text.titleSmall?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      out
        ..add(_row(context, c))
        ..add(const SizedBox(height: AppSpacing.sm));
    }
    return out;
  }

  Widget _row(BuildContext context, CupChampionDto c) {
    final AppTokens t = context.tokens;
    final String id = '${c.monthStart}.${c.place}';
    return AdminCard(
      key: Key('admin.cup.champion.$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              UserAvatar(
                displayName: c.displayName,
                avatarUrl: c.photoUrl ?? c.avatarUrl,
                size: 44,
                gradient: false,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      c.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${cupPathName(c.place)} · ${cupHowName(c.how)}',
                      style: context.text.labelSmall?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // The buttons sit under the name, full width: the app's theme
          // gives every outlined button an unbounded minimum width, which
          // a row cannot lay out.
          AdminSecondaryButton(
            key: Key('admin.cup.setPhoto.$id'),
            label: c.photoUrl == null ? 'إضافة صورة البطل' : 'تغيير الصورة',
            icon: Icons.add_photo_alternate_outlined,
            onPressed: _busy ? null : () => unawaited(_setPhoto(c)),
          ),
          if (c.photoUrl != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            AdminSecondaryButton(
              key: Key('admin.cup.removePhoto.$id'),
              label: 'حذف الصورة',
              icon: Icons.delete_outline_rounded,
              onPressed: _busy ? null : () => unawaited(_removePhoto(c)),
            ),
          ],
        ],
      ),
    );
  }
}
