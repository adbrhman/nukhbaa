/// تعديل مباراة مسجّلة — شاشة مستقلة: الشهر ← المباراة ← الفريقان
/// والموعد، مع إمكانية إسناد دوري للمباراة التي بلا دوري.
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

/// شاشة تعديل مباراة مسجّلة.
///
/// كانت بطاقة أسفل شاشة الإضافة تشاركها منتقي المسابقة. صارت مستقلة
/// ومفتاحها الشهر لا المسابقة، تمامًا كشاشة الإضافة.
class FixtureEditSection extends ConsumerStatefulWidget {
  /// ينشئ القسم. [initialSeasonId] و[initialFixture] يفتحانه على مباراة
  /// بعينها (زر «تعديل» في قائمة «المباريات»).
  const FixtureEditSection({
    super.key,
    this.initialSeasonId,
    this.initialFixture,
  });

  /// The month the form opens on.
  final String? initialSeasonId;

  /// The fixture the form opens on, already filled in.
  final SeasonFixtureCardDto? initialFixture;

  @override
  ConsumerState<FixtureEditSection> createState() => _FixtureEditSectionState();
}

class _FixtureEditSectionState extends ConsumerState<FixtureEditSection> {
  final TextEditingController _homeTeamController = TextEditingController();
  final TextEditingController _awayTeamController = TextEditingController();
  final FocusNode _homeTeamFocusNode = FocusNode();
  final FocusNode _awayTeamFocusNode = FocusNode();

  String? _seasonId;
  String? _fixtureId;
  String? _homeTeamId;
  String? _awayTeamId;

  /// The kickoff instant (UTC), shown and picked on Riyadh's clock (L-12).
  DateTime? _kickoffAt;

  /// The league the admin picked, or `null` for "leave it as it is".
  ///
  /// Not prefilled, and deliberately so: the browse read carries the
  /// league's NAME but not its id, and the correction goes through an
  /// upsert that COALESCEs the league. Sending nothing therefore keeps
  /// whatever the row already has, while picking one overwrites it — which
  /// is how a fixture that migration 0035 could not recover a league for
  /// finally gets one.
  String? _leagueId;
  bool _isContinentalLeague = false;

  /// The league name shown on the selected fixture, for context only.
  String? _currentLeagueName;

  /// Whether the fixture is a test fixture (0098): its sides may stay names
  /// the list does not know (script 91).
  bool _isTest = false;

  @override
  void initState() {
    super.initState();
    _seasonId = widget.initialSeasonId;
    final SeasonFixtureCardDto? fixture = widget.initialFixture;
    if (fixture != null) _fill(fixture);
  }

  /// Fills the form from [fixture], as picking it from the list does.
  void _fill(SeasonFixtureCardDto fixture) {
    _fixtureId = fixture.fixtureId;
    _homeTeamController.text = fixture.homeTeam ?? '';
    _awayTeamController.text = fixture.awayTeam ?? '';
    _homeTeamId = fixture.homeTeamId;
    _awayTeamId = fixture.awayTeamId;
    _kickoffAt = DateTime.tryParse(fixture.kickoffAt ?? '')?.toUtc();
    _currentLeagueName = fixture.leagueName;
    _leagueId = null;
    _isContinentalLeague = false;
    _isTest = fixture.isTest;
  }

  @override
  void dispose() {
    _homeTeamController.dispose();
    _awayTeamController.dispose();
    _homeTeamFocusNode.dispose();
    _awayTeamFocusNode.dispose();
    super.dispose();
  }

  /// The clubs to suggest: the league's -- the one picked, else the one the
  /// fixture already carries -- first and alone
  /// (`team_picker_league_scope.dart`). The whole catalog when the fixture
  /// has no league or none of the league's clubs matches what is typed: an
  /// existing fixture's teams may well predate any league, and refusing to
  /// suggest them would make a name typo unfixable.
  Iterable<String> _teamOptions(
    String query, {
    required List<TeamDto> catalog,
    required List<LeagueDto> leagues,
    required List<SeasonFixtureCardDto> monthFixtures,
  }) {
    final LeagueDto? league = _effectiveLeague(leagues);
    if (league == null) {
      final Set<String> seen = <String>{};
      return <String>[
        for (final TeamDto team in catalog)
          if (teamPickerMatchesQuery(query, team.name) &&
              seen.add(team.name.trim().toLowerCase()))
            team.name,
      ]..sort();
    }
    return teamPickerLeagueOptions(
      query,
      catalog: catalog,
      league: league,
      monthFixtures: monthFixtures,
      fallbackToCatalog: true,
    );
  }

  /// The league whose clubs the team fields offer: the one picked, else the
  /// one named on the fixture (the browse read carries its name, not its
  /// id), else none.
  LeagueDto? _effectiveLeague(List<LeagueDto> leagues) {
    final String? picked = _leagueId;
    final String current = (_currentLeagueName ?? '').trim();
    for (final LeagueDto league in leagues) {
      if (picked != null) {
        if (league.id == picked) return league;
      } else if (current.isNotEmpty && league.name.trim() == current) {
        return league;
      }
    }
    return null;
  }

  String? _resolveTeamId(List<TeamDto> catalog, String text) {
    if (text.trim().isEmpty) return null;
    for (final TeamDto team in catalog) {
      if (_leagueId != null &&
          !_isContinentalLeague &&
          team.leagueId != _leagueId) {
        continue;
      }
      if (teamPickerExactMatch(text, team.name)) return team.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<TeamDto> catalog =
        ref.watch(teamCatalogProvider).value ?? const <TeamDto>[];
    // A club is added only against the list as it stands (script 91).
    final bool catalogReady = ref.watch(teamCatalogProvider).hasValue;
    final List<LeagueDto> leagues =
        ref.watch(leagueCatalogProvider).value ?? const <LeagueDto>[];
    final String? seasonId = _seasonId;
    final List<SeasonFixtureCardDto> monthFixtures = seasonId == null
        ? const <SeasonFixtureCardDto>[]
        : ref.watch(adminSeasonFixturesProvider(seasonId)).value ??
              const <SeasonFixtureCardDto>[];
    final AsyncValue<FixtureScheduleDto>? state = ref.watch(
      fixtureScheduleControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<FixtureScheduleDto>;
    // A side the list does not know blocks the correction (script 91): its
    // name carries no team id, so a second copy of the match goes unseen.
    final bool homeUnknown =
        !_isTest &&
        _homeTeamController.text.trim().isNotEmpty &&
        _homeTeamId == null;
    final bool awayUnknown =
        !_isTest &&
        _awayTeamController.text.trim().isNotEmpty &&
        _awayTeamId == null;
    final bool canSubmit =
        !inFlight &&
        _seasonId != null &&
        _fixtureId != null &&
        _homeTeamController.text.trim().isNotEmpty &&
        _awayTeamController.text.trim().isNotEmpty &&
        _kickoffAt != null &&
        !homeUnknown &&
        !awayUnknown;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminCorrectFixtureSectionTitle,
          subtitle: l10n.adminCorrectFixtureSubtitle,
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MonthPickerField(
                key: const Key('admin.fixtureEdit.monthField'),
                enabled: !inFlight,
                selectedId: _seasonId,
                onSelected: (SeasonDto month) => setState(() {
                  _seasonId = month.id;
                  _fixtureId = null;
                  _homeTeamController.clear();
                  _awayTeamController.clear();
                  _homeTeamId = null;
                  _awayTeamId = null;
                  _kickoffAt = null;
                  _leagueId = null;
                  _isContinentalLeague = false;
                  _currentLeagueName = null;
                }),
              ),
              if (_seasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonFixturePickerField(
                  keyPrefix: 'admin.fixtureEdit',
                  seasonId: _seasonId!,
                  enabled: !inFlight,
                  selectedId: _fixtureId,
                  onSelected: (SeasonFixtureCardDto fixture) =>
                      setState(() => _fill(fixture)),
                ),
              ],
              if (_fixtureId != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _currentLeagueName == null
                      ? l10n.adminFixtureNoLeagueLabel
                      : l10n.adminFixtureCurrentLeagueLabel(
                          _currentLeagueName!,
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                LeaguePickerField(
                  key: const Key('admin.fixtureEdit.leagueField'),
                  enabled: !inFlight,
                  selectedId: _leagueId,
                  onSelected: (LeagueDto league) => setState(() {
                    _leagueId = league.id;
                    _isContinentalLeague = league.isContinental;
                    _homeTeamId = _resolveTeamId(
                      catalog,
                      _homeTeamController.text,
                    );
                    _awayTeamId = _resolveTeamId(
                      catalog,
                      _awayTeamController.text,
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                // A list that failed to load says so, with a retry: before
                // 2026-10-19 every club read as unknown instead.
                const TeamCatalogStatus(),
                TeamPickerField(
                  fieldKey: const Key('admin.fixtureEdit.homeTeamField'),
                  controller: _homeTeamController,
                  focusNode: _homeTeamFocusNode,
                  label: l10n.adminHomeTeamLabel,
                  enabled: !inFlight,
                  catalog: catalog,
                  optionsBuilder: (q) => _teamOptions(
                    q,
                    catalog: catalog,
                    leagues: leagues,
                    monthFixtures: monthFixtures,
                  ),
                  onChanged: () => setState(() {
                    _homeTeamId = _resolveTeamId(
                      catalog,
                      _homeTeamController.text,
                    );
                  }),
                ),
                if (homeUnknown && catalogReady)
                  UnresolvedTeamHint(
                    key: const Key('admin.fixtureEdit.homeTeamUnresolved'),
                    message: l10n.adminTeamNotInCatalogHint,
                    buttonKey: const Key('admin.fixtureEdit.homeTeamAddClub'),
                    onAddClub: inFlight || !catalogReady
                        ? null
                        : () => _addClub(catalog, leagues, home: true),
                  ),
                const SizedBox(height: AppSpacing.md),
                TeamPickerField(
                  fieldKey: const Key('admin.fixtureEdit.awayTeamField'),
                  controller: _awayTeamController,
                  focusNode: _awayTeamFocusNode,
                  label: l10n.adminAwayTeamLabel,
                  enabled: !inFlight,
                  catalog: catalog,
                  optionsBuilder: (q) => _teamOptions(
                    q,
                    catalog: catalog,
                    leagues: leagues,
                    monthFixtures: monthFixtures,
                  ),
                  onChanged: () => setState(() {
                    _awayTeamId = _resolveTeamId(
                      catalog,
                      _awayTeamController.text,
                    );
                  }),
                ),
                if (awayUnknown && catalogReady)
                  UnresolvedTeamHint(
                    key: const Key('admin.fixtureEdit.awayTeamUnresolved'),
                    message: l10n.adminTeamNotInCatalogHint,
                    buttonKey: const Key('admin.fixtureEdit.awayTeamAddClub'),
                    onAddClub: inFlight || !catalogReady
                        ? null
                        : () => _addClub(catalog, leagues, home: false),
                  ),
                const SizedBox(height: AppSpacing.md),
                RiyadhKickoffField(
                  buttonKey: const Key('admin.fixtureEdit.kickoffPicker'),
                  value: _kickoffAt,
                  emptyLabel: l10n.adminPickKickoffButton,
                  enabled: !inFlight,
                  onPicked: (DateTime kickoff) =>
                      setState(() => _kickoffAt = kickoff),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (state is AsyncError<FixtureScheduleDto>)
                AdminErrorBanner(
                  key: const Key('admin.fixtureEdit.error'),
                  message: ErrorPresenter.messageOf(state.error),
                ),
              if (state is AsyncData<FixtureScheduleDto>)
                AdminSuccessBanner(
                  key: const Key('admin.fixtureEdit.result'),
                  message: l10n.adminCorrectFixtureSuccess(
                    state.value.homeTeam,
                    state.value.awayTeam,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.fixtureEdit.submit'),
                label: l10n.adminCorrectFixtureButton,
                icon: Icons.edit_calendar_rounded,
                loading: inFlight,
                onPressed: canSubmit ? _submit : null,
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
      league: _effectiveLeague(leagues),
    );
    if (club == null || !mounted) return;
    setState(() {
      field.text = club.name;
      if (home) {
        _homeTeamId = club.id;
      } else {
        _awayTeamId = club.id;
      }
    });
  }

  void _submit() {
    final fixtureId = _fixtureId;
    final seasonId = _seasonId;
    final homeTeam = _homeTeamController.text.trim();
    final awayTeam = _awayTeamController.text.trim();
    final kickoff = _kickoffAt;
    if (fixtureId == null ||
        seasonId == null ||
        homeTeam.isEmpty ||
        awayTeam.isEmpty ||
        kickoff == null) {
      return;
    }
    ref
        .read(fixtureScheduleControllerProvider.notifier)
        .correct(
          fixtureId: fixtureId,
          seasonId: seasonId,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          kickoffAt: kickoff.toUtc().toIso8601String(),
          homeTeamId: _homeTeamId,
          awayTeamId: _awayTeamId,
          leagueId: _leagueId,
        );
  }
}
