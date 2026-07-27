library;
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/error/error_presenter.dart';
import '../../core/theme/app_colors.dart';
import 'groups_providers.dart';

/// An invite-code-only form that joins the caller into a private group.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<GroupMembershipDto>? state = ref.watch(joinGroupControllerProvider);
    ref.listen<AsyncValue<GroupMembershipDto>?>(joinGroupControllerProvider, (previous, next) {
      if (next is AsyncData<GroupMembershipDto>) {
        Navigator.of(context).pop(next.value);
      }
    });
    final bool inFlight = state is AsyncLoading<GroupMembershipDto>;
    return Scaffold(
      appBar: AppBar(title: const Text('Join Group', key: Key('joinGroup.title'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const Key('joinGroup.codeField'),
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Invite code', border: OutlineInputBorder()),
              enabled: !inFlight,
            ),
            const SizedBox(height: 16),
            if (state is AsyncError<GroupMembershipDto>)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(ErrorPresenter.message(state.error as AppError), key: const Key('joinGroup.error'), style: const TextStyle(color: Colors.redAccent)),
              ),
            FilledButton(
              key: const Key('joinGroup.submit'),
              onPressed: inFlight
                  ? null
                  : () {
                      final code = _codeController.text.trim();
                      if (code.isEmpty) return;
                      ref.read(joinGroupControllerProvider.notifier).join(code);
                    },
              child: inFlight
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                  : const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}
