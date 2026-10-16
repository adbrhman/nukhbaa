/// إضافة نادٍ إلى قائمة الأندية من لوحة الإدارة (script 91، الترحيل 0173).
///
/// تُضاف المباراة بناديين من القائمة، فالاسم المكتوب باليد بلا معرّف فريق
/// لم يكشف أن «هوفنهايم - بيشتكاش» هي «هوفنهايم - بشكتاش» التي أضافتها
/// المزامنة (2026-10-15). النادي الذي ليس في القائمة يُضاف إليها من هنا
/// (`POST /admin/teams`)، وقبل الإضافة تُعرض الأندية ذات الأسماء القريبة
/// ليُختار منها إن كان المقصود أحدها، فلا يدخل النادي نفسه القائمة مرتين.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/providers.dart';
import '../../competition/teams_providers.dart';
import 'admin_ui_kit.dart';

/// The key two club names are compared by on the phone: case, spaces,
/// dashes and dots dropped, hamza forms, alif maqsura and taa marbuta
/// folded -- the server's `competition.team_name_key` (migration 0110) and
/// a little more.
String clubNameKey(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'[\s\-_.]+'), '');

/// [key] without a leading «ال» when what is left is still a name.
String _core(String key) =>
    key.length > 4 && key.startsWith('ال') ? key.substring(2) : key;

/// Edits between [a] and [b]: a letter added, dropped or changed, or two
/// neighbours swapped («بشتكاش» is one edit from «بشكتاش»).
int _editDistance(String a, String b) {
  final int n = a.length;
  final int m = b.length;
  final List<List<int>> d = List<List<int>>.generate(
    n + 1,
    (int i) => List<int>.filled(m + 1, 0),
  );
  for (int i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (int j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
      int best = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < best) best = d[i][j - 1] + 1;
      if (d[i - 1][j - 1] + cost < best) best = d[i - 1][j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          d[i - 2][j - 2] + 1 < best) {
        best = d[i - 2][j - 2] + 1;
      }
      d[i][j] = best;
    }
  }
  return d[n][m];
}

/// How far [name] is from [query], or null when they are not close: 0 for
/// one key, 1 for one inside the other (four letters at least, three fifths
/// of the longer), else the edits -- one allowed from four letters, two
/// from six.
int? _closeness(String query, String name) {
  final String a = _core(clubNameKey(query));
  final String b = _core(clubNameKey(name));
  if (a.isEmpty || b.isEmpty) return null;
  if (a == b) return 0;
  final String shorter = a.length <= b.length ? a : b;
  final String longer = a.length <= b.length ? b : a;
  if (shorter.length >= 4 &&
      longer.contains(shorter) &&
      shorter.length * 10 >= longer.length * 6) {
    return 1;
  }
  final int allowed = shorter.length >= 6 ? 2 : (shorter.length >= 4 ? 1 : 0);
  if (allowed == 0) return null;
  final int edits = _editDistance(a, b);
  return edits <= allowed ? edits : null;
}

/// The clubs of [catalog] whose name is close to [name], the closest first
/// and at most [max], one per name: what the admin may have meant before a
/// new club is added.
List<TeamDto> similarClubs(String name, List<TeamDto> catalog, {int max = 5}) {
  final List<(int, TeamDto)> found = <(int, TeamDto)>[];
  final Set<String> seen = <String>{};
  for (final TeamDto team in catalog) {
    final int? closeness = _closeness(name, team.name);
    if (closeness != null && seen.add(clubNameKey(team.name))) {
      found.add((closeness, team));
    }
  }
  found.sort(((int, TeamDto) x, (int, TeamDto) y) {
    final int byCloseness = x.$1.compareTo(y.$1);
    return byCloseness != 0 ? byCloseness : x.$2.name.compareTo(y.$2.name);
  });
  return <TeamDto>[for (final f in found.take(max)) f.$2];
}

/// The league a club added under [league] is filed in: none for a
/// continental competition, whose clubs come from other leagues (as the
/// seed migrations file them, 0103 and 0104).
String? clubLeagueIdFor(LeagueDto? league) =>
    league == null || league.isContinental ? null : league.id;

/// Opens the dialog over [context]; answers the club added, or the one
/// picked from the near names, or null when the admin cancels.
Future<TeamDto?> showAddClubDialog(
  BuildContext context, {
  required String name,
  required List<TeamDto> catalog,
  required LeagueDto? league,
}) => showDialog<TeamDto>(
  context: context,
  builder: (BuildContext _) =>
      AddClubDialog(initialName: name, catalog: catalog, league: league),
);

/// يضيف نادياً إلى القائمة، أو يختار نادياً قريب الاسم منها.
class AddClubDialog extends ConsumerStatefulWidget {
  /// Creates the dialog, its name field holding [initialName].
  const AddClubDialog({
    super.key,
    required this.initialName,
    required this.catalog,
    required this.league,
  });

  /// What the admin typed in the match's field.
  final String initialName;

  /// The clubs on file, read for the near names.
  final List<TeamDto> catalog;

  /// The league picked in the form, or null.
  final LeagueDto? league;

  @override
  ConsumerState<AddClubDialog> createState() => _AddClubDialogState();
}

class _AddClubDialogState extends ConsumerState<AddClubDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _leagueLine {
    final LeagueDto? league = widget.league;
    if (league == null) return 'يُضاف بلا دوري.';
    if (league.isContinental) {
      return 'يُضاف بلا دوري، فـ«${league.name}» تجمع أندية من دوريات أخرى.';
    }
    return 'يُضاف إلى «${league.name}».';
  }

  Future<void> _add() async {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<TeamDto> result = await ref
        .read(adminApiProvider)
        .addTeam(name: name, leagueId: clubLeagueIdFor(widget.league));
    if (!mounted) return;
    switch (result) {
      case Ok<TeamDto>(:final value):
        ref.invalidate(teamCatalogProvider);
        Navigator.of(context).pop(value);
      case Err<TeamDto>(:final error):
        setState(() {
          _busy = false;
          _error = ErrorPresenter.message(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String typed = _name.text.trim();
    final List<TeamDto> near = typed.isEmpty
        ? const <TeamDto>[]
        : similarClubs(typed, widget.catalog);
    final String? error = _error;
    return AlertDialog(
      key: const Key('admin.addClub.dialog'),
      title: const Text('إضافة نادٍ إلى القائمة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const Key('admin.addClub.name'),
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'اسم النادي',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(_leagueLine),
            if (near.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              const Text(
                'في القائمة أندية بأسماء قريبة. إن كان النادي أحدها فاختره '
                'ولا تضفه مرة ثانية:',
                key: Key('admin.addClub.nearTitle'),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final TeamDto team in near)
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    key: Key('admin.addClub.near.${team.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(team.name),
                    trailing: const Text('اختره'),
                    onTap: _busy ? null : () => Navigator.of(context).pop(team),
                  ),
                ),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              AdminErrorBanner(
                key: const Key('admin.addClub.error'),
                message: error,
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('admin.addClub.cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('admin.addClub.confirm'),
          onPressed: _busy || typed.isEmpty ? null : _add,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('أضف النادي'),
        ),
      ],
    );
  }
}

/// سطر تحذير تحت حقل فريق ليس في القائمة، ومعه زر إضافته إليها: لا تُحفظ
/// المباراة حتى يُختار الفريقان من القائمة (script 91).
class UnresolvedTeamHint extends StatelessWidget {
  /// Creates the hint; [onAddClub] opens [showAddClubDialog].
  const UnresolvedTeamHint({
    super.key,
    required this.message,
    required this.buttonKey,
    required this.onAddClub,
  });

  /// Why the match cannot be saved yet.
  final String message;

  /// The key of the add button itself (tests tap the button, not the row).
  final Key buttonKey;

  /// Opens the add-club dialog; null while the form is busy.
  final VoidCallback? onAddClub;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline, size: 16, color: tokens.gold),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: AppFontSize.s12,
                    color: tokens.gold,
                  ),
                ),
              ),
            ],
          ),
          TextButton.icon(
            key: buttonKey,
            onPressed: onAddClub,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('أضف النادي إلى القائمة'),
          ),
        ],
      ),
    );
  }
}
