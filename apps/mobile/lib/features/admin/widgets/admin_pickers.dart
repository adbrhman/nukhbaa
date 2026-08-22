library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/error/error_presenter.dart';
import '../../../l10n/app_localizations.dart';
import '../../competition/competition_providers.dart';

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
          key: const Key('admin.fixtures.seasonField'),
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
