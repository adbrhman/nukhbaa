library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/leagues_providers.dart';
import '../../../competition/teams_providers.dart';
import '../../admin_providers.dart';
import '../../widgets/add_club_dialog.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';
import '../../widgets/riyadh_kickoff_field.dart';
import '../../widgets/team_catalog_status.dart';
import '../../widgets/team_picker_field.dart';
import '../../widgets/team_picker_aliases.dart';
import '../../widgets/team_picker_league_scope.dart';

/// إضافة مباراة — اختيار الشهر والدوري ثم الفريقين وموعد الانطلاق، مع
/// خيار «مباراة تجريبية» (الترحيل 0098): يراها المشرفون وحدهم ولا تُحتسب
/// لها نقاط، ولا يتغيّر هذا الخيار بعد الإضافة.
///
/// تُفتح من قسم «المباريات» (`fixtures_admin_section.dart`)، ومنه أيضًا
/// التعديل والحذف والإخفاء.
class FixtureScheduleSection extends ConsumerStatefulWidget {
  const FixtureScheduleSection({super.key, this.initialSeasonId});

  /// The month the form opens on: the one the matches list was showing.
  final String? initialSeasonId;

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

  /// The kickoff instant (UTC), picked on Riyadh's clock (audit L-12).
  DateTime? _kickoffAt;

  /// The month this fixture is filed into — a `MM/YYYY` contest season
  /// from `GET /months`, not a competition's edition.
  String? _seasonId;

  /// The league it belongs to. Required to submit: it is what names the
  /// fixture on the matches card, and what narrows both team dropdowns to
  /// one league's clubs.
  String? _leagueId;

  /// The club picked in the add-club dialog for each side (script 91): the
  /// side's id while its field still names that club, whatever league the
  /// club is filed under.
  TeamDto? _homePicked;
  TeamDto? _awayPicked;

  /// Whether to file it as a test fixture (migration 0098).
  bool _isTest = false;

  @override
  void initState() {
    super.initState();
    _seasonId = widget.initialSeasonId;
  }

  /// The clubs of [leagueId], filtered by [query] — the add-fixture form's
  /// team options.
  ///
  /// Deliberately narrow: no legacy name-only list and no cross-league
  /// names. Picking the German league must
  /// offer German clubs and nothing else, which is only possible now that
  /// `football_data.teams` carries a `league_id` (migration 0035). With no
  /// league chosen yet there is nothing legitimate to suggest, so the list
  /// is empty rather than the whole catalog.
  ///
  /// A continental league offers its own clubs too, not the whole catalog
  /// (`team_picker_league_scope.dart`): the ones filed under it and the
  /// ones already playing its matches this month, and the whole catalog
  /// only when none of those matches what is typed.
  Iterable<String> _filterTeamsInLeague(
    String query, {
    required List<TeamDto> catalog,
    required List<LeagueDto> leagues,
    required List<SeasonFixtureCardDto> monthFixtures,
  }) {
    final LeagueDto? league = _selectedLeague(leagues);
    if (league == null) return const <String>[];
    return teamPickerLeagueOptions(
      query,
      catalog: catalog,
      league: league,
      monthFixtures: monthFixtures,
      fallbackToCatalog: league.isContinental,
    );
  }

  /// The league picked in the form, read off the catalog.
  LeagueDto? _selectedLeague(List<LeagueDto> leagues) {
    for (final LeagueDto l in leagues) {
      if (l.id == _leagueId) return l;
    }
    return null;
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
    if (text.trim().isEmpty || leagueId == null) return null;
    for (final TeamDto team in catalog) {
      if ((continental || team.leagueId == leagueId) &&
          teamPickerExactMatch(text, team.name)) {
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

  /// The team id of a side: the club of the league that [text] names, or
  /// the club [picked] in the add-club dialog while [text] still names it.
  ///
  /// Null blocks the add (script 91). A name the list does not know carries
  /// no team id, so neither the server's check (batch 138) nor the
  /// schedule's trigger (0110) could see the same match already added under
  /// another spelling: «هوفنهايم - بيشتكاش» beside the sync's «هوفنهايم -
  /// بشكتاش» on 2026-10-15. Before that a missing id only cost the crest and
  /// colours («اسبانيول» and «مرسيليا» shipped one letter off, found days
  /// later on a screenshot). A test fixture is never checked.
  String? _sideId(
    List<TeamDto> catalog,
    String text,
    TeamDto? picked, {
    bool continental = false,
  }) =>
      _resolveTeamIdInLeague(
        catalog,
        text,
        _leagueId,
        continental: continental,
      ) ??
      (picked != null && teamPickerExactMatch(text, picked.name)
          ? picked.id
          : null);

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
    // A club is added only against the list as it stands: its near names
    // are what keeps one club from going in twice.
    final bool catalogReady = ref.watch(teamCatalogProvider).hasValue;
    final List<LeagueDto> leagues =
        ref.watch(leagueCatalogProvider).value ?? const <LeagueDto>[];
    final bool continental = _isContinental(leagues);
    final String? homeTeamId = _sideId(
      catalog,
      _homeTeamController.text,
      _homePicked,
      continental: continental,
    );
    final String? awayTeamId = _sideId(
      catalog,
      _awayTeamController.text,
      _awayPicked,
      continental: continental,
    );
    // A side the list does not know blocks the add (script 91).
    final bool homeUnknown =
        !_isTest &&
        _homeTeamController.text.trim().isNotEmpty &&
        homeTeamId == null;
    final bool awayUnknown =
        !_isTest &&
        _awayTeamController.text.trim().isNotEmpty &&
        awayTeamId == null;
    final AsyncValue<AddMatchResult>? state = ref.watch(
      addMatchControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<AddMatchResult>;
    // A match added empties the form, so a second tap cannot add it twice;
    // the month and the league stay for the next one (audit L-12).
    ref.listen<AsyncValue<AddMatchResult>?>(addMatchControllerProvider, (
      AsyncValue<AddMatchResult>? previous,
      AsyncValue<AddMatchResult>? next,
    ) {
      if (next is AsyncData<AddMatchResult> &&
          previous is! AsyncData<AddMatchResult>) {
        setState(() {
          _homeTeamController.clear();
          _awayTeamController.clear();
          _homePicked = null;
          _awayPicked = null;
          _kickoffAt = null;
          _isTest = false;
        });
      }
    });
    final FixtureScheduleDto? unlinked = ref
        .read(addMatchControllerProvider.notifier)
        .unlinked;

    int nextDisplayOrder = 0;
    List<SeasonFixtureCardDto> monthFixtures = const <SeasonFixtureCardDto>[];
    if (_seasonId != null) {
      // Hidden fixtures included: they keep their place in the month.
      final AsyncValue<List<SeasonFixtureCardDto>> fixturesState = ref.watch(
        adminSeasonFixturesProvider(_seasonId!),
      );
      if (fixturesState is AsyncData<List<SeasonFixtureCardDto>>) {
        nextDisplayOrder = fixturesState.value.length;
        monthFixtures = fixturesState.value;
      }
    }

    final bool canSubmit =
        !inFlight &&
        _seasonId != null &&
        _leagueId != null &&
        _homeTeamController.text.trim().isNotEmpty &&
        _awayTeamController.text.trim().isNotEmpty &&
        _kickoffAt != null &&
        !homeUnknown &&
        !awayUnknown;

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
                  _homePicked = null;
                  _awayPicked = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              // A list that failed to load says so, with a retry: before
              // 2026-10-19 every club read as unknown instead.
              const TeamCatalogStatus(),
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
                  leagues: leagues,
                  monthFixtures: monthFixtures,
                ),
                // The side's id is read in build (_sideId): a change only
                // redraws.
                onChanged: () => setState(() {}),
              ),
              if (homeUnknown && catalogReady)
                UnresolvedTeamHint(
                  key: const Key('admin.fixtures.homeTeamUnresolved'),
                  message: l10n.adminTeamNotInCatalogHint,
                  buttonKey: const Key('admin.fixtures.homeTeamAddClub'),
                  onAddClub: inFlight || !catalogReady
                      ? null
                      : () => _addClub(catalog, leagues, home: true),
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
                  leagues: leagues,
                  monthFixtures: monthFixtures,
                ),
                onChanged: () => setState(() {}),
              ),
              if (awayUnknown && catalogReady)
                UnresolvedTeamHint(
                  key: const Key('admin.fixtures.awayTeamUnresolved'),
                  message: l10n.adminTeamNotInCatalogHint,
                  buttonKey: const Key('admin.fixtures.awayTeamAddClub'),
                  onAddClub: inFlight || !catalogReady
                      ? null
                      : () => _addClub(catalog, leagues, home: false),
                ),
              const SizedBox(height: AppSpacing.md),
              RiyadhKickoffField(
                buttonKey: const Key('admin.fixtures.kickoffPicker'),
                value: _kickoffAt,
                emptyLabel: l10n.adminPickKickoffButton,
                enabled: !inFlight,
                onPicked: (DateTime kickoff) =>
                    setState(() => _kickoffAt = kickoff),
              ),
              const SizedBox(height: AppSpacing.sm),
              // The card's background would hide the tile's ink (Flutter
              // asserts): the tile gets a Material of its own (script 91).
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const Key('admin.fixtures.testSwitch'),
                  contentPadding: EdgeInsets.zero,
                  value: _isTest,
                  onChanged: inFlight
                      ? null
                      : (bool value) => setState(() => _isTest = value),
                  title: const Text('مباراة تجريبية'),
                  subtitle: const Text(
                    'للاختبار فقط: يراها المشرفون وحدهم، ولا تُحتسب لها نقاط '
                    'ولا تدخل الترتيب. لا يمكن تغيير هذا بعد الإضافة.',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (state is AsyncError<AddMatchResult>)
                AdminErrorBanner(
                  key: const Key('admin.fixtures.error'),
                  message: ErrorPresenter.messageOf(state.error),
                ),
              if (state is AsyncError<AddMatchResult> && unlinked != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'سُجّلت ${unlinked.homeTeam} × ${unlinked.awayTeam} ولم '
                    'تُضف إلى الشهر بعد. اضغط «${l10n.adminAddMatchButton}» '
                    'مرة أخرى لإكمال إضافتها، بلا نسخة ثانية.',
                    key: const Key('admin.fixtures.unlinked'),
                  ),
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
                onPressed: canSubmit
                    ? () => _addMatch(
                        nextDisplayOrder,
                        homeTeamId: homeTeamId,
                        awayTeamId: awayTeamId,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the add-club dialog for one side (script 91): the club added,
  /// or a near name picked from the list, fills the side's field.
  Future<void> _addClub(
    List<TeamDto> catalog,
    List<LeagueDto> leagues, {
    required bool home,
  }) async {
    final TextEditingController field = home
        ? _homeTeamController
        : _awayTeamController;
    final TeamDto? club = await showAddClubDialog(
      context,
      name: field.text.trim(),
      catalog: catalog,
      league: _selectedLeague(leagues),
    );
    if (club == null || !mounted) return;
    setState(() {
      field.text = club.name;
      if (home) {
        _homePicked = club;
      } else {
        _awayPicked = club;
      }
    });
  }

  void _addMatch(
    int displayOrder, {
    required String? homeTeamId,
    required String? awayTeamId,
  }) {
    final seasonId = _seasonId;
    final leagueId = _leagueId;
    final homeTeam = _homeTeamController.text.trim();
    final awayTeam = _awayTeamController.text.trim();
    final kickoff = _kickoffAt;
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
          homeTeamId: homeTeamId,
          awayTeamId: awayTeamId,
          leagueId: leagueId,
          isTest: _isTest,
        );
  }
}
