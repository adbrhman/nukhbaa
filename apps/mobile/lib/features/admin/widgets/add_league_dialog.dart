/// إضافة دوري إلى قائمة الدوريات من نموذج المباراة (script 139، الترحيل
/// 0183).
///
/// بعض المسابقات تُلعب نادرًا وفيها مباريات قوية، ولم تكن القائمة تحمل إلا
/// ما أضافته ترحيلات البذر. آخر خانة في قائمة الدوريات «دوري جديد»: يُكتب
/// اسمه هنا فيُضاف (`POST /admin/leagues`) ويُختار للمباراة. يُضاف قاريًا
/// كـ«ديربيات كبرى» (0104): أنديته من القائمة كلها ولا يُنسب إليه نادٍ.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/providers.dart';
import '../../competition/leagues_providers.dart';
import 'add_club_dialog.dart' show clubNameKey;
import 'admin_ui_kit.dart';

/// The value of the «دوري جديد» entry at the foot of the league list: it
/// opens [showAddLeagueDialog] instead of picking a league.
const String newLeagueEntryValue = 'admin.newLeague';

/// The league of [catalog] whose name has the spelling key of [name], or
/// null: the server refuses such a name, so the dialog offers that league
/// before anything is sent.
LeagueDto? sameNameLeague(String name, List<LeagueDto> catalog) {
  final String key = clubNameKey(name);
  if (key.isEmpty) return null;
  for (final LeagueDto league in catalog) {
    if (clubNameKey(league.name) == key) return league;
  }
  return null;
}

/// Opens the dialog over [context]; answers the league added, or the one
/// on file under the same name, or null when the admin cancels.
Future<LeagueDto?> showAddLeagueDialog(
  BuildContext context, {
  required List<LeagueDto> catalog,
}) => showDialog<LeagueDto>(
  context: context,
  builder: (BuildContext _) => AddLeagueDialog(catalog: catalog),
);

/// يضيف دوريًا إلى القائمة، أو يختار الدوري المسجّل بالاسم نفسه.
class AddLeagueDialog extends ConsumerStatefulWidget {
  /// Creates the dialog over the leagues on file.
  const AddLeagueDialog({super.key, required this.catalog});

  /// The leagues on file, read for the same name.
  final List<LeagueDto> catalog;

  @override
  ConsumerState<AddLeagueDialog> createState() => _AddLeagueDialogState();
}

class _AddLeagueDialogState extends ConsumerState<AddLeagueDialog> {
  final TextEditingController _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<LeagueDto> result = await ref
        .read(adminApiProvider)
        .addLeague(name: name);
    if (!mounted) return;
    switch (result) {
      case Ok<LeagueDto>(:final value):
        ref.invalidate(leagueCatalogProvider);
        Navigator.of(context).pop(value);
      case Err<LeagueDto>(:final error):
        setState(() {
          _busy = false;
          _error = ErrorPresenter.message(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String typed = _name.text.trim();
    final LeagueDto? same = sameNameLeague(typed, widget.catalog);
    final String? error = _error;
    return AlertDialog(
      key: const Key('admin.addLeague.dialog'),
      title: const Text('دوري جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const Key('admin.addLeague.name'),
              controller: _name,
              enabled: !_busy,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم الدوري',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'يُضاف إلى قائمة الدوريات وتُختار أنديته من القائمة كلها.',
            ),
            if (same != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              const Text(
                'هذا الدوري في القائمة من قبل، فاختره ولا تضفه مرة ثانية:',
                key: Key('admin.addLeague.sameTitle'),
              ),
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: Key('admin.addLeague.same.${same.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(same.name),
                  trailing: const Text('اختره'),
                  onTap: _busy ? null : () => Navigator.of(context).pop(same),
                ),
              ),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              AdminErrorBanner(
                key: const Key('admin.addLeague.error'),
                message: error,
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('admin.addLeague.cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('admin.addLeague.confirm'),
          onPressed: _busy || typed.isEmpty || same != null ? null : _add,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('أضف الدوري'),
        ),
      ],
    );
  }
}
