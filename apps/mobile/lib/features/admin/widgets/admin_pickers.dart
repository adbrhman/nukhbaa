library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/error/error_presenter.dart';
import '../../../l10n/app_localizations.dart';
import '../../competition/competition_providers.dart';
import '../../competition/leagues_providers.dart';
import '../../fixture_prediction/fixture_prediction_providers.dart';

/// The competition dropdown: reads the public catalogue
/// (`GET /competitions`, via `competitionListProvider`) and lets the admin
/// pick one. Purely a client-side convenience — a fixture aggregate carries
/// no competition reference (Axiom 3), so the selection only scopes which
/// team names suggestions show and which seasons/rounds load. Shared by the
/// fixtures and rounds sections.
class CompetitionPickerField extends ConsumerWidget {
  const CompetitionPickerField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.enabled,
    required this.selectedId,
    required this.onSelected,
  });

  final Key fieldKey;
  final String label;
  final bool enabled;
  final String? selectedId;
  final ValueChanged<CompetitionDto> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CompetitionDto>> competitions = ref.watch(
      competitionListProvider,
    );
    return competitions.when(
      loading: () => DropdownButtonFormField<String>(
        key: fieldKey,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: const <DropdownMenuItem<String>>[],
        onChanged: null,
      ),
      error: (Object error, StackTrace stackTrace) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(ErrorPresenter.message(error as AppError)),
      ),
      data: (List<CompetitionDto> list) {
        final String? value = list.any((c) => c.id == selectedId)
            ? selectedId
            : null;
        return DropdownButtonFormField<String>(
          key: fieldKey,
          initialValue: value,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            for (final CompetitionDto competition in list)
              DropdownMenuItem<String>(
                key: Key('admin.fixtures.competitionField.${competition.id}'),
                value: competition.id,
                child: Text(competition.name),
              ),
          ],
          onChanged: !enabled
              ? null
              : (String? id) {
                  final CompetitionDto? competition = list
                      .cast<CompetitionDto?>()
                      .firstWhere((c) => c?.id == id, orElse: () => null);
                  if (competition != null) onSelected(competition);
                },
        );
      },
    );
  }
}

/// قائمة الموسم المنسدلة (المسابقة ← الموسم). تعرض label الموسم وتُخرج id
/// فقط. مشتركة بين قسمي المباريات والجولات.
class SeasonPickerField extends ConsumerWidget {
  const SeasonPickerField({
    super.key,
    required this.competitionId,
    required this.enabled,
    required this.selectedId,
    required this.onSelected,
  });

  final String competitionId;
  final bool enabled;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<SeasonDto>> seasons = ref.watch(
      competitionSeasonsProvider(competitionId),
    );
    return seasons.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object error, StackTrace _) => InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.adminSelectSeasonLabel,
          border: const OutlineInputBorder(),
        ),
        child: Text(ErrorPresenter.message(error as AppError)),
      ),
      data: (List<SeasonDto> list) {
        if (list.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.adminSelectSeasonLabel,
              border: const OutlineInputBorder(),
            ),
            child: Text(l10n.adminNoSeasonsHint),
          );
        }
        final String? value = list.any((s) => s.id == selectedId)
            ? selectedId
            : null;
        return DropdownButtonFormField<String>(
          key: Key('admin.fixtures.seasonField.$competitionId'),
          initialValue: value,
          decoration: InputDecoration(
            labelText: l10n.adminSelectSeasonLabel,
            border: const OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            for (final SeasonDto season in list)
              DropdownMenuItem<String>(
                key: Key('admin.fixtures.seasonField.${season.id}'),
                value: season.id,
                child: Text(season.label),
              ),
          ],
          onChanged: !enabled
              ? null
              : (String? id) {
                  if (id != null) onSelected(id);
                },
        );
      },
    );
  }
}

/// منتقي الشهر: يقرأ `GET /months` (`monthlySeasonsProvider`) ويعرض الأشهر
/// من الأحدث. المسابقة شهر تقويمي، فهذا هو الاختيار الوحيد الذي يحدّد أين
/// تُودَع المباراة — لا مسابقة ولا موسم دوري.
class MonthPickerField extends ConsumerWidget {
  const MonthPickerField({
    super.key,
    required this.enabled,
    required this.selectedId,
    required this.onSelected,
  });

  final bool enabled;
  final String? selectedId;
  final ValueChanged<SeasonDto> onSelected;

  /// Renders a stored `MM/YYYY` label the way the app names a month
  /// everywhere else: `09/2026` → `شهر 9`. Anything not in that shape is
  /// shown verbatim rather than mangled — the read only ever returns
  /// `MM/YYYY`, so an unexpected label is worth seeing as it is.
  static String monthLabel(String stored) {
    final List<String> parts = stored.split('/');
    if (parts.length != 2) return stored;
    final int? month = int.tryParse(parts.first);
    if (month == null) return stored;
    return 'شهر $month';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<SeasonDto>> months = ref.watch(
      monthlySeasonsProvider,
    );
    return months.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object error, StackTrace _) => InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.adminSelectMonthLabel,
          border: const OutlineInputBorder(),
        ),
        child: Text(ErrorPresenter.message(error as AppError)),
      ),
      data: (List<SeasonDto> list) {
        if (list.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.adminSelectMonthLabel,
              border: const OutlineInputBorder(),
            ),
            child: Text(l10n.adminNoMonthsHint),
          );
        }
        final String? value = list.any((SeasonDto s) => s.id == selectedId)
            ? selectedId
            : null;
        return DropdownButtonFormField<String>(
          key: const Key('admin.fixtures.monthField.field'),
          initialValue: value,
          decoration: InputDecoration(
            labelText: l10n.adminSelectMonthLabel,
            border: const OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            for (final SeasonDto month in list)
              DropdownMenuItem<String>(
                key: Key('admin.fixtures.monthField.${month.id}'),
                value: month.id,
                child: Text(monthLabel(month.label)),
              ),
          ],
          onChanged: !enabled
              ? null
              : (String? id) {
                  if (id == null) return;
                  onSelected(list.firstWhere((SeasonDto s) => s.id == id));
                },
        );
      },
    );
  }
}

/// منتقي الدوري: يقرأ `GET /leagues` (`leagueCatalogProvider`). اختياره
/// إلزامي في نموذج الإضافة — هو ما يُسمّي المباراة في شاشة المباريات وما
/// يحصر قائمتَي الفريقين في أندية ذلك الدوري وحدها.
class LeaguePickerField extends ConsumerWidget {
  const LeaguePickerField({
    super.key,
    required this.enabled,
    required this.selectedId,
    required this.onSelected,
  });

  final bool enabled;
  final String? selectedId;
  final ValueChanged<LeagueDto> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<LeagueDto>> leagues = ref.watch(
      leagueCatalogProvider,
    );
    return leagues.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object error, StackTrace _) => InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.adminSelectLeagueLabel,
          border: const OutlineInputBorder(),
        ),
        child: Text(ErrorPresenter.message(error as AppError)),
      ),
      data: (List<LeagueDto> list) {
        if (list.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.adminSelectLeagueLabel,
              border: const OutlineInputBorder(),
            ),
            child: Text(l10n.adminNoLeaguesHint),
          );
        }
        final String? value = list.any((LeagueDto l) => l.id == selectedId)
            ? selectedId
            : null;
        return DropdownButtonFormField<String>(
          key: const Key('admin.fixtures.leagueField.field'),
          initialValue: value,
          decoration: InputDecoration(
            labelText: l10n.adminSelectLeagueLabel,
            border: const OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            for (final LeagueDto league in list)
              DropdownMenuItem<String>(
                key: Key('admin.fixtures.leagueField.${league.id}'),
                value: league.id,
                child: Text(league.name),
              ),
          ],
          onChanged: !enabled
              ? null
              : (String? id) {
                  if (id == null) return;
                  onSelected(list.firstWhere((LeagueDto l) => l.id == id));
                },
        );
      },
    );
  }
}

/// قائمة المباراة المنسدلة (الموسم ← المباراة مباشرة، بلا Round — Axiom 4
/// Amendment). تعرض الفريقين — أو تنويهاً عند نقص بيانات الهوية — وتُخرج
/// fixtureId فقط، بلا إدخال UUID يدوي. [keyPrefix] يُميّز مفاتيح الودجت بين
/// الأقسام المختلفة التي تستخدم هذا المنتقي.
class SeasonFixturePickerField extends ConsumerWidget {
  const SeasonFixturePickerField({
    super.key,
    required this.keyPrefix,
    required this.seasonId,
    required this.enabled,
    required this.selectedId,
    required this.onSelected,
  });

  final String keyPrefix;
  final String seasonId;
  final bool enabled;
  final String? selectedId;
  final ValueChanged<SeasonFixtureCardDto> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<SeasonFixtureCardDto>> fixtures = ref.watch(
      seasonFixturesProvider(seasonId),
    );
    return fixtures.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object error, StackTrace _) => InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.adminSelectFixtureLabel,
          border: const OutlineInputBorder(),
        ),
        child: Text(ErrorPresenter.message(error as AppError)),
      ),
      data: (List<SeasonFixtureCardDto> list) {
        if (list.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.adminSelectFixtureLabel,
              border: const OutlineInputBorder(),
            ),
            child: Text(l10n.adminNoSeasonFixturesHint),
          );
        }
        final String? value = list.any((f) => f.fixtureId == selectedId)
            ? selectedId
            : null;
        return DropdownButtonFormField<String>(
          key: Key('$keyPrefix.fixtureField'),
          initialValue: value,
          decoration: InputDecoration(
            labelText: l10n.adminSelectFixtureLabel,
            border: const OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            for (final SeasonFixtureCardDto fixture in list)
              DropdownMenuItem<String>(
                key: Key('$keyPrefix.fixtureField.${fixture.fixtureId}'),
                value: fixture.fixtureId,
                child: Text(_fixtureLabel(fixture, l10n)),
              ),
          ],
          onChanged: !enabled
              ? null
              : (String? id) {
                  if (id == null) return;
                  final SeasonFixtureCardDto fixture = list.firstWhere(
                    (f) => f.fixtureId == id,
                  );
                  onSelected(fixture);
                },
        );
      },
    );
  }

  String _fixtureLabel(SeasonFixtureCardDto fixture, AppLocalizations l10n) {
    final String? home = fixture.homeTeam;
    final String? away = fixture.awayTeam;
    if (home == null || away == null) {
      return l10n.adminFixtureIncompleteDataLabel;
    }
    return '$home × $away';
  }
}
