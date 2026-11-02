/// قسم «الأجهزة» في لوحة المشرف (السكربت 200، قرار المالك 2026-11-02):
/// كل هاتف دخل منه أكثر من حساب، مع عدد حساباته وآخر ظهور له، وإيقاف أي
/// حساب منها أو إعادته.
///
/// الهاتف هو تثبيت التطبيق (رقم التثبيت يرسله التطبيق مع كل طلب منذ هذا
/// الإصدار)، أو رمز إشعاراته لما قبل ذلك. يُسمح بأكثر من حساب على الهاتف
/// الواحد، لكن الخادم يرفض أن يتوقع حساب ثانٍ مباراة توقعها حساب آخر من
/// الهاتف نفسه.
///
/// الإيقاف هو تعليق الحساب نفسه في قسم «الحسابات»: يختفي هو ونقاطه من كل
/// اللوحات ولا يكسب شيئاً، ولا يُحذف شيء؛ الإعادة ترجعه كما كان.
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
import '../../widgets/admin_ui_kit.dart';

/// `GET /admin/shared-devices`.
final adminSharedDevicesProvider = FutureProvider.autoDispose<SharedDevicesDto>(
  (ref) async {
    return switch (await ref.watch(adminApiProvider).sharedDevices()) {
      Ok<SharedDevicesDto>(:final value) => value,
      Err<SharedDevicesDto>(:final error) => throw error,
    };
  },
);

/// «حسابان» / «3 حسابات» / «11 حساباً».
String sharedDeviceAccounts(int count) {
  if (count == 2) return 'حسابان';
  if (count >= 3 && count <= 10) return '$count حسابات';
  return '$count حساباً';
}

String _day(DateTime when) {
  final DateTime local = when.toLocal();
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}

/// The "shared phones" section of the admin hub.
class SharedDevicesSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const SharedDevicesSection({super.key});

  @override
  ConsumerState<SharedDevicesSection> createState() =>
      _SharedDevicesSectionState();
}

class _SharedDevicesSectionState extends ConsumerState<SharedDevicesSection> {
  final TextEditingController _reason = TextEditingController();
  UserSummaryDto? _selected;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _select(UserSummaryDto user) {
    setState(() {
      _selected = _selected?.id == user.id ? null : user;
      _error = null;
    });
  }

  Future<void> _setSuspended({required bool suspended}) async {
    final UserSummaryDto? user = _selected;
    if (user == null) return;
    final String reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'اكتب السبب أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(adminApiProvider);
    final Result<UserSanctionResultDto> result = suspended
        ? await api.suspendUser(user.id, reason)
        : await api.reinstateUser(user.id, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<UserSanctionResultDto>(:final value):
        setState(() {
          _selected = UserSummaryDto(
            id: user.id,
            email: user.email,
            displayName: user.displayName,
            status: value.status,
          );
          _reason.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value.status == 'suspended'
                  ? 'أُوقف الحساب: لا يظهر في اللوحات ولا يكسب نقاطاً'
                  : 'أُعيد الحساب ونقاطه إلى اللوحات',
            ),
          ),
        );
        ref.invalidate(adminSharedDevicesProvider);
      case Err<UserSanctionResultDto>(:final error):
        setState(() => _error = ErrorPresenter.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<SharedDevicesDto> devices = ref.watch(
      adminSharedDevicesProvider,
    );
    return ListView(
      key: const Key('admin.devices.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'حسابات على هاتف واحد',
          subtitle:
              'كل هاتف دخل منه أكثر من حساب. لا يتوقع حسابان من هاتف واحد '
              'المباراة نفسها. اضغط على حساب لإيقافه أو إعادته.',
        ),
        ...devices.when(
          loading: () => <Widget>[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
          error: (Object error, _) => <Widget>[
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    ErrorPresenter.messageOf(error),
                    key: const Key('admin.devices.loadError'),
                    style: TextStyle(color: tokens.errorText),
                  ),
                  TextButton(
                    key: const Key('admin.devices.retry'),
                    onPressed: () => ref.invalidate(adminSharedDevicesProvider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ],
          data: (SharedDevicesDto data) => <Widget>[
            Text(
              data.devices.isEmpty
                  ? 'لا يوجد هاتف عليه أكثر من حساب'
                  : 'هواتف بأكثر من حساب: ${data.devices.length} · '
                        'حسابات فيها: '
                        '${data.devices.fold<int>(0, (n, d) => n + d.users.length)}',
              key: const Key('admin.devices.summary'),
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (int i = 0; i < data.devices.length; i++) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _phoneCard(context, i, data.devices[i]),
            ],
          ],
        ),
      ],
    );
  }

  Widget _phoneCard(BuildContext context, int index, SharedDeviceDto device) {
    final AppTokens tokens = context.tokens;
    final UserSummaryDto? selected = _selected;
    final bool holdsSelected =
        selected != null && device.users.any((u) => u.id == selected.id);
    return AdminCard(
      key: Key('admin.devices.phone.$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'هاتف ${index + 1} · ${sharedDeviceAccounts(device.users.length)}',
            key: Key('admin.devices.phone.$index.title'),
            style: context.text.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'آخر ظهور: ${_day(device.lastSeen)}',
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final UserSummaryDto user in device.users)
            _AccountTile(
              key: Key('admin.devices.account.$index.${user.id}'),
              user: user,
              selected: user.id == selected?.id,
              onTap: () => _select(user),
            ),
          if (holdsSelected) _editor(context, selected),
        ],
      ),
    );
  }

  Widget _editor(BuildContext context, UserSummaryDto user) {
    final AppTokens tokens = context.tokens;
    final bool suspended = user.status == 'suspended';
    final String? error = _error;
    return Column(
      key: const Key('admin.devices.editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.sm),
        AdminTextField(
          key: const Key('admin.devices.reasonField'),
          controller: _reason,
          hint: 'السبب (إلزامي)',
          prefixIcon: Icons.notes_rounded,
          enabled: !_busy,
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error,
            key: const Key('admin.devices.error'),
            style: TextStyle(color: tokens.errorText),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (suspended)
          AdminSecondaryButton(
            key: const Key('admin.devices.reinstate'),
            label: 'إعادة الحساب',
            icon: Icons.visibility_rounded,
            loading: _busy,
            onPressed: _busy
                ? null
                : () => unawaited(_setSuspended(suspended: false)),
          )
        else
          AdminPrimaryButton(
            key: const Key('admin.devices.suspend'),
            label: 'إيقاف الحساب',
            icon: Icons.block_rounded,
            loading: _busy,
            onPressed: _busy
                ? null
                : () => unawaited(_setSuspended(suspended: true)),
          ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    super.key,
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final UserSummaryDto user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final bool suspended = user.status == 'suspended';
    final String name = user.displayName.isEmpty ? user.id : user.displayName;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      // A ListTile paints its ink on the nearest Material; the card's own
      // background would hide it, so the tile gets a Material of its own.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: onTap,
          selected: selected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: tokens.border),
          ),
          title: Text(name),
          subtitle: Text(
            suspended
                ? '${user.email ?? user.id} · موقوف'
                : user.email ?? user.id,
            style: suspended ? TextStyle(color: tokens.errorText) : null,
          ),
          trailing: Icon(
            suspended ? Icons.block_rounded : Icons.chevron_left_rounded,
          ),
        ),
      ),
    );
  }
}
