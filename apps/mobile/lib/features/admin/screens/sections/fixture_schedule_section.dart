library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/leagues_providers.dart';
import '../../../competition/teams_providers.dart';
import '../../../fixture_prediction/fixture_prediction_providers.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';
import '../../widgets/team_picker_field.dart';

/// سطر تحذير تحت حقل فريق لم يُطابق الكتالوج: نبرة تحذير لا خطأ، فالإرسال
/// يبقى ممكنًا عمدًا.
class _UnresolvedTeamHint extends StatelessWidget {
  const _UnresolvedTeamHint({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: tokens.gold),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: tokens.gold),
            ),
          ),
        ],
      ),
    );
  }
}

/// إضافة مباراة — اختيار الشهر والدوري ثم الفريقين وموعد الانطلاق.
///
/// التعديل والحذف لهما شاشتاهما المستقلتان
/// (`fixture_edit_section.dart` و`fixture_delete_section.dart`).
class FixtureScheduleSection extends ConsumerStatefulWidget {
  const FixtureScheduleSection({super.key});

  @override
  ConsumerState<FixtureScheduleSection> createState() =>
      _FixtureScheduleSectionState();
}

class _FixtureScheduleSectionState
    extends ConsumerState<FixtureScheduleSection> {
  final TextEditingController _homeTeamController = TextEditingController();
  final TextEditingController _awayTeamController = TextEditingController();
  final FocusNode _homeTeamFocusNode = FocusNode();
  final FocusNode _awayTeamFocusNode = FocusNode();
  DateTime? _kickoffLocal;

  /// The month this fixture is filed into — a `MM/YYYY` contest season
  /// from `GET /months`, not a competition's edition.
  String? _seasonId;

  /// The league it belongs to. Required to submit: it is what names the
  /// fixture on the matches card, and what narrows both team dropdowns to
  /// one league's clubs.
  String? _leagueId;
  String? _homeTeamId;
  String? _awayTeamId;

  /// The clubs of [leagueId], filtered by [query] — the add-fixture form's
  /// team options.
  ///
  /// Deliberately narrow: no legacy name-only list and no cross-league
  /// names. Picking the German league must
  /// offer German clubs and nothing else, which is only possible now that
  /// `football_data.teams` carries a `league_id` (migration 0035). With no
  /// league chosen yet there is nothing legitimate to suggest, so the list
  /// is empty rather than the whole catalog.
  Iterable<String> _filterTeamsInLeague(
    String query, {
    required List<TeamDto> catalog,
    required String? leagueId,
    required bool continental,
  }) {
    if (leagueId == null) return const <String>[];
    // A continental competition has no clubs of its own -- its entrants
    // are other leagues' clubs -- so the whole catalog is on offer,
    // deduplicated by name because the seeds left a second row for some
    // of them.
    final Set<String> seen = <String>{};
    final List<String> options = <String>[
      for (final TeamDto team in catalog)
        if ((continental || team.leagueId == leagueId) &&
            seen.add(team.name.toLowerCase()))
          team.name,
    ]..sort();
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return options;
    final String needle = trimmed.toLowerCase();
    return options.where((String t) => t.toLowerCase().contains(needle));
  }

  /// Resolves [text] to a team id *within* [leagueId].
  ///
  /// The league scope is not decoration. A club that plays in two seeded
  /// competitions has two catalog rows under the same name — Barcelona is
  /// both a LaLiga row and a UCL row — so a name-only match would attach
  /// whichever row came first and silently file the fixture under the
  /// wrong league.
  String? _resolveTeamIdInLeague(
    List<TeamDto> catalog,
    String text,
    String? leagueId, {
    bool continental = false,
  }) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || leagueId == null) return null;
    for (final TeamDto team in catalog) {
      if ((continental || team.leagueId == leagueId) &&
          team.name.toLowerCase() == trimmed.toLowerCase()) {
        return team.id;
      }
    }
    return null;
  }

  /// Whether the chosen league draws its entrants from other leagues.
  ///
  /// Read off the catalog rather than kept in state: the flag belongs to
  /// the league, and a copy in the widget would go stale the moment a
  /// league is reclassified.
  bool _isContinental(List<LeagueDto> leagues) {
    for (final LeagueDto l in leagues) {
      if (l.id == _leagueId) return l.isContinental;
    }
    return false;
  }

  /// Whether [text] names something that is not a club of [leagueId] — the
  /// state that must be *visible*.
  ///
  /// A fixture stored with a null `home_team_id`/`away_team_id` still
  /// works: the free-text name is the identity of record (Axiom 3), so
  /// nothing fails, nothing is logged, and the admin gets no signal at
  /// all. What silently disappears is everything keyed off the resolved
  /// id — the crest and the team's brand colour — so the fixture card
  /// falls back to two grey letters. That is exactly how "اسبانيول"
  /// (catalog: "إسبانيول") and "مرسيليا" (catalog: "مارسيليا") shipped:
  /// one character off, no error, found only by eye on a screenshot days
  /// later.
  ///
  /// Deliberately a *warning*, not validation: the button stays enabled,
  /// because a real fixture whose club is genuinely absent from the
  /// catalog must remain submittable. It only refuses to let the mismatch
  /// pass unseen.
  bool _isUnresolvedTeamInLeague(
    List<TeamDto> catalog,
    String text,
    String? leagueId, {
    bool continental = false,
  }) =>
      text.trim().isNotEmpty &&
      _resolveTeamIdInLeague(
            catalog,
            text,
            leagueId,
            continental: continental,
          ) ==
          null;

  @override
  void dispose() {
    _homeTeamController.dispose();
    _awayTeamController.dispose();
    _homeTeamFocusNode.dispose();
    _awayTeamFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<TeamDto> catalog =
        ref.watch(teamCatalogProvider).value ?? const <TeamDto>[];
    final List<LeagueDto> leagues =
        ref.watch(leagueCatalogProvider).value ?? const <LeagueDto>[];
    final bool continental = _isContinental(leagues);
    final AsyncValue<AddMatchResult>? state = ref.watch(
      addMatchControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<AddMatchResult>;

    int nextDisplayOrder = 0;
    if (_seasonId != null) {
      final AsyncValue<List<SeasonFixtureCardDto>> fixturesState = ref.watch(
        seasonFixturesProvider(_seasonId!),
      );
      if (fixturesState is AsyncData<List<SeasonFixtureCardDto>>) {
        nextDisplayOrder = fixturesState.value.length;
      }
    }

    final bool canSubmit =
        !inFlight &&
        _seasonId != null &&
        _leagueId != null &&
        _homeTeamController.text.trim().isNotEmpty &&
        _awayTeamController.text.trim().isNotEmpty &&
        _kickoffLocal != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminAddMatchSectionTitle,
          subtitle: 'اختر الشهر والدوري والفريقين وموعد المباراة',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MonthPickerField(
                key: const Key('admin.fixtures.monthField'),
                enabled: !inFlight,
                selectedId: _seasonId,
                onSelected: (SeasonDto month) => setState(() {
                  _seasonId = month.id;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              LeaguePickerField(
                key: const Key('admin.fixtures.leagueField'),
                enabled: !inFlight,
                selectedId: _leagueId,
                onSelected: (LeagueDto league) => setState(() {
                  _leagueId = league.id;
                  // The clubs on offer change with the league, so whatever
                  // is already typed belongs to the previous one.
                  _homeTeamController.clear();
                  _awayTeamController.clear();
                  _homeTeamId = null;
                  _awayTeamId = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              TeamPickerField(
                fieldKey: const Key('admin.fixtures.homeTeamField'),
                controller: _homeTeamController,
                focusNode: _homeTeamFocusNode,
                label: l10n.adminHomeTeamLabel,
                enabled: !inFlight,
                catalog: catalog,
                optionsBuilder: (q) => _filterTeamsInLeague(
                  q,
                  catalog: catalog,
                  leagueId: _leagueId,
                  continental: continental,
                ),
                onChanged: () => setState(() {
                  _homeTeamId = _resolveTeamIdInLeague(
                    catalog,
                    _homeTeamController.text,
                    _leagueId,
                    continental: continental,
                  );
                }),
              ),
              if (_isUnresolvedTeamInLeague(
                catalog,
                _homeTeamController.text,
                _leagueId,
                continental: continental,
              ))
                _UnresolvedTeamHint(
                  key: const Key('admin.fixtures.homeTeamUnresolved'),
                  message: l10n.adminTeamNotInCatalogHint,
                ),
              const SizedBox(height: AppSpacing.md),
              TeamPickerField(
                fieldKey: const Key('admin.fixtures.awayTeamField'),
                controller: _awayTeamController,
                focusNode: _awayTeamFocusNode,
                label: l10n.adminAwayTeamLabel,
                enabled: !inFlight,
                catalog: catalog,
                optionsBuilder: (q) => _filterTeamsInLeague(
                  q,
                  catalog: catalog,
                  leagueId: _leagueId,
                  continental: continental,
                ),
                onChanged: () => setState(() {
                  _awayTeamId = _resolveTeamIdInLeague(
                    catalog,
                    _awayTeamController.text,
                    _leagueId,
                    continental: continental,
                  );
                }),
              ),
              if (_isUnresolvedTeamInLeague(
                catalog,
                _awayTeamController.text,
                _leagueId,
                continental: continental,
              ))
                _UnresolvedTeamHint(
                  key: const Key('admin.fixtures.awayTeamUnresolved'),
                  message: l10n.adminTeamNotInCatalogHint,
                ),
              const SizedBox(height: AppSpacing.md),
              AdminSecondaryButton(
                key: const Key('admin.fixtures.kickoffPicker'),
                label: _kickoffLocal == null
                    ? l10n.adminPickKickoffButton
                    : _formatKickoff(_kickoffLocal!),
                icon: Icons.event_outlined,
                onPressed: inFlight ? null : _pickKickoff,
              ),
              const SizedBox(height: AppSpacing.md),
              if (state is AsyncError<AddMatchResult>)
                AdminErrorBanner(
                  key: const Key('admin.fixtures.error'),
                  message: ErrorPresenter.message(state.error as AppError),
                ),
              if (state is AsyncData<AddMatchResult>)
                AdminSuccessBanner(
                  key: const Key('admin.fixtures.result'),
                  message: l10n.adminAddMatchSuccess(
                    state.value.fixture.homeTeam,
                    state.value.fixture.awayTeam,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.fixtures.addMatch'),
                label: l10n.adminAddMatchButton,
                icon: Icons.sports_soccer_rounded,
                loading: inFlight,
                onPressed: canSubmit ? () => _addMatch(nextDisplayOrder) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickKickoff() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _kickoffLocal ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _kickoffLocal == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(_kickoffLocal!),
    );
    if (time == null) return;
    setState(() {
      _kickoffLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _addMatch(int displayOrder) {
    final seasonId = _seasonId;
    final leagueId = _leagueId;
    final homeTeam = _homeTeamController.text.trim();
    final awayTeam = _awayTeamController.text.trim();
    final kickoff = _kickoffLocal;
    if (seasonId == null ||
        leagueId == null ||
        homeTeam.isEmpty ||
        awayTeam.isEmpty ||
        kickoff == null) {
      return;
    }
    ref
        .read(addMatchControllerProvider.notifier)
        .submit(
          seasonId: seasonId,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoffAt: kickoff.toUtc().toIso8601String(),
          displayOrder: displayOrder,
          homeTeamId: _homeTeamId,
          awayTeamId: _awayTeamId,
          leagueId: leagueId,
        );
  }

  String _formatKickoff(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
