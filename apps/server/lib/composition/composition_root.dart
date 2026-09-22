import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:infrastructure/infrastructure.dart';
import 'package:meta/meta.dart';
import 'package:server/provider_sync/phase_one_rules.dart';
import 'package:shared/shared.dart';

/// The single place where the dependency graph is wired (Application ADR,
/// Section 13). Nothing else in the server constructs infrastructure directly.
///
/// This is the ONLY component permitted to depend on `infrastructure`
/// (Application ADR, Section 8: nothing depends on Infrastructure except the
/// composition root).
final class CompositionRoot {
  CompositionRoot._({
    required PostgresConnection connection,
    required JwksClient jwksClient,
    required this.checkHealth,
    required this.getLatestBuild,
    required this.authenticateRequest,
    required this.getCurrentUser,
    required this.enrolInOpenSeasons,
    required this.login,
    required this.register,
    required this.requestPasswordReset,
    required this.updatePassword,
    required this.updateDisplayName,
    required this.updateTimeZoneOffset,
    required this.getMyStreak,
    required this.getMyInsights,
    required this.getMyDailyChallenge,
    required this.getMyWeeklyLeague,
    required this.getMyBadges,
    required this.getMyNotificationPreferences,
    required this.updateMyNotificationPreferences,
    required this.getMyFavoriteTeams,
    required this.setMyFavoriteTeams,
    required this.resolveExperimentVariant,
    required this.setAvatar,
    required this.clearAvatar,
    required this.readAvatar,
    required this.createCompetition,
    required this.startSeason,
    required this.linkFixtureToRound,
    required this.removeFixtureFromRound,
    required this.joinCompetition,
    required this.getCompetition,
    required this.getRound,
    required this.listCompetitions,
    required this.listCompetitionSeasons,
    required this.getCurrentSeason,
    required this.listSeasonRounds,
    required this.browseRoundFixtures,
    required this.browseSeasonFixtures,
    required this.linkFixtureToSeason,
    required this.removeFixtureFromSeason,
    required this.listCurrentMonthFixtures,
    required this.submitPrediction,
    required this.submitFixturePrediction,
    required this.getMyPrediction,
    required this.listRoundPredictions,
    required this.recordFixtureResult,
    required this.registerFixtureSchedule,
    required this.correctFixtureSchedule,
    required this.scoreFixture,
    required this.readParticipantLedger,
    required this.getSeasonLeaderboard,
    required this.listMySeasonRecords,
    required this.getSeasonFixtureLeaderboard,
    required this.getFixtureScores,
    required this.getFixturePredictionDistribution,
    required this.adminGetFixtureScores,
    required this.getHallOfFame,
    required this.getSportingSeasonLeaderboard,
    required this.createGroup,
    required this.getGroup,
    required this.joinGroupByInvite,
    required this.renameGroup,
    required this.regenerateInvite,
    required this.listGroupMembers,
    required this.listMyGroups,
    required this.getGroupLeaderboard,
    required this.reactToRound,
    required this.removeReaction,
    required this.listRoundReactions,
    required this.postFixtureToLedger,
    required this.reactToFixture,
    required this.removeFixtureReaction,
    required this.listFixtureReactions,
    required this.getGroupActivityFeed,
    required this.listMyNotifications,
    required this.listMyNotificationFeed,
    required this.publishAnnouncement,
    required this.getUnreadCount,
    required this.markNotificationRead,
    required this.sendPredictionReminders,
    required this.sendPreMatchReminders,
    required this.sendStreakSavers,
    required this.sendOvertakenPushes,
    required this.recordPushOpen,
    required this.flushNotificationQueue,
    required this.ensureUpcomingMonthlySeasons,
    required this.settleMatchDays,
    required this.closeWeeklyLeague,
    required this.evaluateBadges,
    required this.providerSyncMode,
    this.syncProviderFixtures,
    this.syncProviderResults,
    this.liveScoreBoard,
    this.refreshLiveScores,
    required this.registerDeviceToken,
    required this.suspendUser,
    required this.reinstateUser,
    required this.listUsers,
    required this.listAuditLog,
    required this.viewParticipantLedger,
    required this.adminGetParticipantDisplayNames,
    required this.adminListRoundPredictions,
    required this.adminListFixturePredictions,
    required this.adminGetUserFixturePredictions,
    required this.listMyFixturePredictions,
    required this.listMyActiveSeasons,
    required this.listTeams,
    required this.listLeagues,
    required this.listMonthlySeasons,
  }) : _connection = connection,
       _jwksClient = jwksClient;

  // NOTE: the fields [submitPrediction], [getMyPrediction] and
  // [listRoundPredictions] are declared below alongside the competition
  // use-cases; the private constructor above already requires them so the
  // production graph must wire them, while [forTesting] supplies loud "absent"
  // stand-ins for any prediction slice a given route test does not exercise.

  /// Test-only constructor: builds a root around already-assembled use-cases
  /// (typically wired to in-memory fakes), without opening any real
  /// infrastructure.
  ///
  /// This preserves encapsulation — the production graph is still built solely
  /// via [bootstrap] — while letting route tests exercise the *real* wiring
  /// (`context.read<Future<CompositionRoot>>()` -> `root.<useCase>()`) against
  /// controllable use-cases. We deliberately avoid `implements CompositionRoot`,
  /// which is impossible here because the class is `final`.
  ///
  /// [dispose] is a no-op for roots created this way, since no connection or
  /// JWKS client was opened.
  ///
  /// Every use-case is optional: a route test wires only the slice it
  /// exercises (e.g. the `/health` test provides just [checkHealth]; the `/me`
  /// test provides [authenticateRequest] + [getCurrentUser]). Any use-case not
  /// supplied is replaced by an "absent" stand-in that throws a clear
  /// [StateError] if invoked, so a test that reaches an unwired slice fails
  /// loudly instead of dereferencing null.
  @visibleForTesting
  CompositionRoot.forTesting({
    CheckHealth? checkHealth,
    GetLatestBuild? getLatestBuild,
    LoginWithPassword? login,
    RegisterWithPassword? register,
    RequestPasswordReset? requestPasswordReset,
    UpdatePassword? updatePassword,
    AuthenticateRequest? authenticateRequest,
    GetCurrentUser? getCurrentUser,
    EnrolInOpenSeasons? enrolInOpenSeasons,
    UpdateDisplayName? updateDisplayName,
    UpdateTimeZoneOffset? updateTimeZoneOffset,
    GetMyStreak? getMyStreak,
    GetMyInsights? getMyInsights,
    GetMyDailyChallenge? getMyDailyChallenge,
    GetMyWeeklyLeague? getMyWeeklyLeague,
    GetMyBadges? getMyBadges,
    GetMyNotificationPreferences? getMyNotificationPreferences,
    UpdateMyNotificationPreferences? updateMyNotificationPreferences,
    GetMyFavoriteTeams? getMyFavoriteTeams,
    SetMyFavoriteTeams? setMyFavoriteTeams,
    ResolveExperimentVariant? resolveExperimentVariant,
    SetAvatar? setAvatar,
    ClearAvatar? clearAvatar,
    ReadAvatar? readAvatar,
    CreateCompetition? createCompetition,
    StartSeason? startSeason,
    LinkFixtureToRound? linkFixtureToRound,
    RemoveFixtureFromRound? removeFixtureFromRound,
    JoinCompetition? joinCompetition,
    GetCompetition? getCompetition,
    GetRound? getRound,
    ListCompetitions? listCompetitions,
    ListCompetitionSeasons? listCompetitionSeasons,
    GetCurrentSeason? getCurrentSeason,
    ListSeasonRounds? listSeasonRounds,
    BrowseRoundFixtures? browseRoundFixtures,
    BrowseSeasonFixtures? browseSeasonFixtures,
    LinkFixtureToSeason? linkFixtureToSeason,
    RemoveFixtureFromSeason? removeFixtureFromSeason,
    ListCurrentMonthFixtures? listCurrentMonthFixtures,
    SubmitPrediction? submitPrediction,
    SubmitFixturePrediction? submitFixturePrediction,
    GetMyPrediction? getMyPrediction,
    ListRoundPredictions? listRoundPredictions,
    RecordFixtureResult? recordFixtureResult,
    RegisterFixtureSchedule? registerFixtureSchedule,
    CorrectFixtureSchedule? correctFixtureSchedule,
    ScoreFixture? scoreFixture,
    ReadParticipantLedger? readParticipantLedger,
    GetSeasonLeaderboard? getSeasonLeaderboard,
    ListMySeasonRecords? listMySeasonRecords,
    GetSeasonFixtureLeaderboard? getSeasonFixtureLeaderboard,
    GetFixtureScores? getFixtureScores,
    GetFixturePredictionDistribution? getFixturePredictionDistribution,
    AdminGetFixtureScores? adminGetFixtureScores,
    GetHallOfFame? getHallOfFame,
    GetSportingSeasonLeaderboard? getSportingSeasonLeaderboard,
    CreateGroup? createGroup,
    GetGroup? getGroup,
    JoinGroupByInvite? joinGroupByInvite,
    RenameGroup? renameGroup,
    RegenerateInvite? regenerateInvite,
    ListGroupMembers? listGroupMembers,
    ListMyGroups? listMyGroups,
    GetGroupLeaderboard? getGroupLeaderboard,
    ReactToRound? reactToRound,
    RemoveReaction? removeReaction,
    ListRoundReactions? listRoundReactions,
    PostFixtureToLedger? postFixtureToLedger,
    ReactToFixture? reactToFixture,
    RemoveFixtureReaction? removeFixtureReaction,
    ListFixtureReactions? listFixtureReactions,
    GetGroupActivityFeed? getGroupActivityFeed,
    ListMyNotifications? listMyNotifications,
    ListMyNotificationFeed? listMyNotificationFeed,
    PublishAnnouncement? publishAnnouncement,
    GetUnreadCount? getUnreadCount,
    MarkNotificationRead? markNotificationRead,
    SendPredictionReminders? sendPredictionReminders,
    SendPreMatchReminders? sendPreMatchReminders,
    SendStreakSavers? sendStreakSavers,
    SendOvertakenPushes? sendOvertakenPushes,
    RecordPushOpen? recordPushOpen,
    FlushNotificationQueue? flushNotificationQueue,
    EnsureUpcomingMonthlySeasons? ensureUpcomingMonthlySeasons,
    SettleMatchDays? settleMatchDays,
    CloseWeeklyLeague? closeWeeklyLeague,
    EvaluateBadges? evaluateBadges,
    this.providerSyncMode = ProviderSyncMode.off,
    this.syncProviderFixtures,
    this.syncProviderResults,
    this.liveScoreBoard,
    this.refreshLiveScores,
    RegisterDeviceToken? registerDeviceToken,
    SuspendUser? suspendUser,
    ReinstateUser? reinstateUser,
    ListUsers? listUsers,
    ListAuditLog? listAuditLog,
    ViewParticipantLedger? viewParticipantLedger,
    AdminGetParticipantDisplayNames? adminGetParticipantDisplayNames,
    AdminListRoundPredictions? adminListRoundPredictions,
    AdminListFixturePredictions? adminListFixturePredictions,
    AdminGetUserFixturePredictions? adminGetUserFixturePredictions,
    ListMyFixturePredictions? listMyFixturePredictions,
    ListMyActiveSeasons? listMyActiveSeasons,
    ListTeams? listTeams,
    ListLeagues? listLeagues,
    ListMonthlySeasons? listMonthlySeasons,
  }) : checkHealth = checkHealth ?? _absentCheckHealth(),
       getLatestBuild = getLatestBuild ?? _absentGetLatestBuild(),
       login = login ?? _absentLogin(),
       register = register ?? _absentRegister(),
       requestPasswordReset =
           requestPasswordReset ?? _absentRequestPasswordReset(),
       updatePassword = updatePassword ?? _absentUpdatePassword(),
       authenticateRequest =
           authenticateRequest ?? _absentAuthenticateRequest(),
       getCurrentUser = getCurrentUser ?? _absentGetCurrentUser(),
       enrolInOpenSeasons = enrolInOpenSeasons ?? _absentEnrolInOpenSeasons(),
       updateDisplayName = updateDisplayName ?? _absentUpdateDisplayName(),
       updateTimeZoneOffset =
           updateTimeZoneOffset ?? _absentUpdateTimeZoneOffset(),
       getMyStreak = getMyStreak ?? _absentGetMyStreak(),
       getMyInsights = getMyInsights ?? _absentGetMyInsights(),
       getMyDailyChallenge =
           getMyDailyChallenge ?? _absentGetMyDailyChallenge(),
       getMyWeeklyLeague = getMyWeeklyLeague ?? _absentGetMyWeeklyLeague(),
       getMyBadges = getMyBadges ?? _absentGetMyBadges(),
       getMyNotificationPreferences =
           getMyNotificationPreferences ??
           _absentGetMyNotificationPreferences(),
       updateMyNotificationPreferences =
           updateMyNotificationPreferences ??
           _absentUpdateMyNotificationPreferences(),
       getMyFavoriteTeams = getMyFavoriteTeams ?? _absentGetMyFavoriteTeams(),
       setMyFavoriteTeams = setMyFavoriteTeams ?? _absentSetMyFavoriteTeams(),
       resolveExperimentVariant =
           resolveExperimentVariant ?? _absentResolveExperimentVariant(),
       setAvatar = setAvatar ?? _absentSetAvatar(),
       clearAvatar = clearAvatar ?? _absentClearAvatar(),
       readAvatar = readAvatar ?? _absentReadAvatar(),
       createCompetition = createCompetition ?? _absentCreateCompetition(),
       startSeason = startSeason ?? _absentStartSeason(),
       linkFixtureToRound = linkFixtureToRound ?? _absentLinkFixtureToRound(),
       removeFixtureFromRound =
           removeFixtureFromRound ?? _absentRemoveFixtureFromRound(),
       joinCompetition = joinCompetition ?? _absentJoinCompetition(),
       getCompetition = getCompetition ?? _absentGetCompetition(),
       getRound = getRound ?? _absentGetRound(),
       listCompetitions = listCompetitions ?? _absentListCompetitions(),
       listCompetitionSeasons =
           listCompetitionSeasons ?? _absentListCompetitionSeasons(),
       getCurrentSeason = getCurrentSeason ?? _absentGetCurrentSeason(),
       listSeasonRounds = listSeasonRounds ?? _absentListSeasonRounds(),
       browseRoundFixtures =
           browseRoundFixtures ?? _absentBrowseRoundFixtures(),
       browseSeasonFixtures =
           browseSeasonFixtures ?? _absentBrowseSeasonFixtures(),
       linkFixtureToSeason =
           linkFixtureToSeason ?? _absentLinkFixtureToSeason(),
       removeFixtureFromSeason =
           removeFixtureFromSeason ?? _absentRemoveFixtureFromSeason(),
       listCurrentMonthFixtures =
           listCurrentMonthFixtures ?? _absentListCurrentMonthFixtures(),
       submitPrediction = submitPrediction ?? _absentSubmitPrediction(),
       submitFixturePrediction =
           submitFixturePrediction ?? _absentSubmitFixturePrediction(),
       getMyPrediction = getMyPrediction ?? _absentGetMyPrediction(),
       listRoundPredictions =
           listRoundPredictions ?? _absentListRoundPredictions(),
       recordFixtureResult =
           recordFixtureResult ?? _absentRecordFixtureResult(),
       registerFixtureSchedule =
           registerFixtureSchedule ?? _absentRegisterFixtureSchedule(),
       correctFixtureSchedule =
           correctFixtureSchedule ?? _absentCorrectFixtureSchedule(),
       scoreFixture = scoreFixture ?? _absentScoreFixture(),
       adminGetParticipantDisplayNames =
           adminGetParticipantDisplayNames ??
           _absentAdminGetParticipantDisplayNames(),
       readParticipantLedger =
           readParticipantLedger ?? _absentReadParticipantLedger(),
       getSeasonLeaderboard =
           getSeasonLeaderboard ?? _absentGetSeasonLeaderboard(),
       listMySeasonRecords =
           listMySeasonRecords ?? _absentListMySeasonRecords(),
       getSeasonFixtureLeaderboard =
           getSeasonFixtureLeaderboard ?? _absentGetSeasonFixtureLeaderboard(),
       getFixtureScores = getFixtureScores ?? _absentGetFixtureScores(),
       getFixturePredictionDistribution =
           getFixturePredictionDistribution ??
           _absentGetFixturePredictionDistribution(),
       adminGetFixtureScores =
           adminGetFixtureScores ?? _absentAdminGetFixtureScores(),
       getHallOfFame = getHallOfFame ?? _absentGetHallOfFame(),
       getSportingSeasonLeaderboard =
           getSportingSeasonLeaderboard ??
           _absentGetSportingSeasonLeaderboard(),
       createGroup = createGroup ?? _absentCreateGroup(),
       getGroup = getGroup ?? _absentGetGroup(),
       joinGroupByInvite = joinGroupByInvite ?? _absentJoinGroupByInvite(),
       renameGroup = renameGroup ?? _absentRenameGroup(),
       regenerateInvite = regenerateInvite ?? _absentRegenerateInvite(),
       listGroupMembers = listGroupMembers ?? _absentListGroupMembers(),
       listMyGroups = listMyGroups ?? _absentListMyGroups(),
       getGroupLeaderboard =
           getGroupLeaderboard ?? _absentGetGroupLeaderboard(),
       reactToRound = reactToRound ?? _absentReactToRound(),
       removeReaction = removeReaction ?? _absentRemoveReaction(),
       listRoundReactions = listRoundReactions ?? _absentListRoundReactions(),
       postFixtureToLedger =
           postFixtureToLedger ?? _absentPostFixtureToLedger(),
       reactToFixture = reactToFixture ?? _absentReactToFixture(),
       removeFixtureReaction =
           removeFixtureReaction ?? _absentRemoveFixtureReaction(),
       listFixtureReactions =
           listFixtureReactions ?? _absentListFixtureReactions(),
       getGroupActivityFeed =
           getGroupActivityFeed ?? _absentGetGroupActivityFeed(),
       listMyNotifications =
           listMyNotifications ?? _absentListMyNotifications(),
       listMyNotificationFeed =
           listMyNotificationFeed ?? _absentListMyNotificationFeed(),
       publishAnnouncement =
           publishAnnouncement ?? _absentPublishAnnouncement(),
       getUnreadCount = getUnreadCount ?? _absentGetUnreadCount(),
       markNotificationRead =
           markNotificationRead ?? _absentMarkNotificationRead(),
       sendPredictionReminders =
           sendPredictionReminders ?? _absentSendPredictionReminders(),
       sendPreMatchReminders =
           sendPreMatchReminders ?? _absentSendPreMatchReminders(),
       sendStreakSavers = sendStreakSavers ?? _absentSendStreakSavers(),
       sendOvertakenPushes =
           sendOvertakenPushes ?? _absentSendOvertakenPushes(),
       recordPushOpen = recordPushOpen ?? _absentRecordPushOpen(),
       flushNotificationQueue =
           flushNotificationQueue ?? _absentFlushNotificationQueue(),
       ensureUpcomingMonthlySeasons =
           ensureUpcomingMonthlySeasons ??
           _absentEnsureUpcomingMonthlySeasons(),
       settleMatchDays = settleMatchDays ?? _absentSettleMatchDays(),
       closeWeeklyLeague = closeWeeklyLeague ?? _absentCloseWeeklyLeague(),
       evaluateBadges = evaluateBadges ?? _absentEvaluateBadges(),
       registerDeviceToken =
           registerDeviceToken ?? _absentRegisterDeviceToken(),
       suspendUser = suspendUser ?? _absentSuspendUser(),
       reinstateUser = reinstateUser ?? _absentReinstateUser(),
       listUsers = listUsers ?? _absentListUsers(),
       listAuditLog = listAuditLog ?? _absentListAuditLog(),
       viewParticipantLedger =
           viewParticipantLedger ?? _absentViewParticipantLedger(),
       adminListRoundPredictions =
           adminListRoundPredictions ?? _absentAdminListRoundPredictions(),
       adminListFixturePredictions =
           adminListFixturePredictions ?? _absentAdminListFixturePredictions(),
       adminGetUserFixturePredictions =
           adminGetUserFixturePredictions ??
           _absentAdminGetUserFixturePredictions(),
       listMyFixturePredictions =
           listMyFixturePredictions ?? _absentListMyFixturePredictions(),
       listMyActiveSeasons =
           listMyActiveSeasons ?? _absentListMyActiveSeasons(),
       listTeams = listTeams ?? _absentListTeams(),
       listLeagues = listLeagues ?? _absentListLeagues(),
       listMonthlySeasons = listMonthlySeasons ?? _absentListMonthlySeasons(),
       _connection = null,
       _jwksClient = null;

  /// Builds a [CheckHealth] wired to a repository that fails if pinged, so an
  /// unwired health slice surfaces immediately in a test.
  /// Backs an "absent" [AuthGateway]: throws if a test reaches the auth
  /// slice it never wired.
  static LoginWithPassword _absentLogin() =>
      LoginWithPassword(_UnwiredAuthGateway());

  /// Backs an "absent" [AuthGateway] for registration.
  static RegisterWithPassword _absentRegister() =>
      RegisterWithPassword(_UnwiredAuthGateway());

  static RequestPasswordReset _absentRequestPasswordReset() =>
      RequestPasswordReset(_UnwiredAuthGateway());

  static UpdatePassword _absentUpdatePassword() =>
      UpdatePassword(_UnwiredAuthGateway());

  static CheckHealth _absentCheckHealth() =>
      CheckHealth(_UnwiredHealthRepository());

  /// Backs an "absent" [GetLatestBuild] in [CompositionRoot.forTesting]:
  /// throws if a test reaches the update-check slice it never wired.
  static GetLatestBuild _absentGetLatestBuild() =>
      GetLatestBuild(_UnwiredBuildInfoRepository());

  /// Builds an [AuthenticateRequest] over a verifier that throws if invoked.
  static AuthenticateRequest _absentAuthenticateRequest() =>
      AuthenticateRequest(_UnwiredTokenVerifier());

  /// Builds a [GetCurrentUser] over a directory that throws if invoked.
  static GetCurrentUser _absentGetCurrentUser() =>
      GetCurrentUser(_UnwiredUserDirectory());

  /// Back the "absent" avatar use-cases over a directory that throws if a
  /// test reaches the avatar slice it never wired.
  static SetAvatar _absentSetAvatar() =>
      SetAvatar(userDirectory: _UnwiredUserDirectory());

  static ClearAvatar _absentClearAvatar() =>
      ClearAvatar(userDirectory: _UnwiredUserDirectory());

  static ReadAvatar _absentReadAvatar() =>
      ReadAvatar(userDirectory: _UnwiredUserDirectory());

  /// Backs an "absent" [EnrolInOpenSeasons] over a repository that throws if
  /// a test reaches the enrolment slice it never wired.
  static EnrolInOpenSeasons _absentEnrolInOpenSeasons() => EnrolInOpenSeasons(
    competitionRepository: _UnwiredCompetitionRepository(),
    idGenerator: _unwiredIdGenerator,
  );

  /// Builds an "absent" [UpdateDisplayName] over a directory that throws
  /// if a test reaches the display-name slice it never wired.
  static UpdateDisplayName _absentUpdateDisplayName() =>
      UpdateDisplayName(userDirectory: _UnwiredUserDirectory());

  /// Builds an "absent" [UpdateTimeZoneOffset] over a directory that throws
  /// if a test reaches the time-zone slice it never wired.
  static UpdateTimeZoneOffset _absentUpdateTimeZoneOffset() =>
      UpdateTimeZoneOffset(userDirectory: _UnwiredUserDirectory());

  /// Builds an "absent" [GetMyStreak] over a repository that throws if a
  /// test reaches the streak slice it never wired.
  static GetMyStreak _absentGetMyStreak() =>
      GetMyStreak(streaks: _UnwiredStreakRepository(), clock: _unwiredClock);

  /// Builds an "absent" [GetMyInsights] over a reader that throws if a
  /// test reaches the insights slice it never wired.
  static GetMyInsights _absentGetMyInsights() => GetMyInsights(
    outcomes: _UnwiredPredictionOutcomeReader(),
    clock: _unwiredClock,
  );

  /// Builds an "absent" [GetMyDailyChallenge] over repositories that throw
  /// if a test reaches the daily-challenge slice it never wired.
  static GetMyDailyChallenge _absentGetMyDailyChallenge() =>
      GetMyDailyChallenge(
        competitionRepository: _unwiredCompetitionRepository,
        dailyChallenges: _UnwiredDailyChallengeRepository(),
        clock: _unwiredClock,
      );

  /// Builds an "absent" [GetMyWeeklyLeague] over ports that throw if a test
  /// reaches the weekly-league slice it never wired.
  static GetMyWeeklyLeague _absentGetMyWeeklyLeague() => GetMyWeeklyLeague(
    join: JoinWeeklyLeague(
      leagues: _UnwiredWeeklyLeagueRepository(),
      idGenerator: _unwiredIdGenerator,
      clock: _unwiredClock,
    ),
    standings: _UnwiredWeeklyLeagueStandingsReader(),
    profiles: _UnwiredWeeklyLeagueProfileReader(),
  );

  /// Builds an "absent" [GetMyBadges] over a reader that throws if a test
  /// reaches the badge wall it never wired.
  static GetMyBadges _absentGetMyBadges() =>
      GetMyBadges(badges: _UnwiredPlayerBadgeReader());

  /// Builds an "absent" [GetMyNotificationPreferences] over a repository
  /// that throws if a test reaches the preference slice it never wired.
  static GetMyNotificationPreferences _absentGetMyNotificationPreferences() =>
      GetMyNotificationPreferences(
        preferences: _UnwiredNotificationPreferenceRepository(),
      );

  /// Builds an "absent" [UpdateMyNotificationPreferences] over a repository
  /// that throws if a test reaches the preference slice it never wired.
  static UpdateMyNotificationPreferences
  _absentUpdateMyNotificationPreferences() => UpdateMyNotificationPreferences(
    preferences: _UnwiredNotificationPreferenceRepository(),
  );

  /// Builds an "absent" [GetMyFavoriteTeams] over a repository that throws
  /// if a test reaches the favorite-teams slice it never wired.
  static GetMyFavoriteTeams _absentGetMyFavoriteTeams() =>
      GetMyFavoriteTeams(favorites: _UnwiredFavoriteTeamRepository());

  /// Builds an "absent" [SetMyFavoriteTeams]; see [_absentGetMyFavoriteTeams].
  static SetMyFavoriteTeams _absentSetMyFavoriteTeams() =>
      SetMyFavoriteTeams(favorites: _UnwiredFavoriteTeamRepository());

  /// Builds an "absent" [ResolveExperimentVariant] over a repository that
  /// throws if a test reaches the experiment slice it never wired.
  static ResolveExperimentVariant _absentResolveExperimentVariant() =>
      ResolveExperimentVariant(experiments: _UnwiredExperimentRepository());

  /// A single throwing repository backing every "absent" competition use-case,
  /// so a test that reaches an unwired competition slice fails loudly.
  static final CompetitionRepository _unwiredCompetitionRepository =
      _UnwiredCompetitionRepository();

  static final RulesetProvider _unwiredRulesetProvider =
      _UnwiredRulesetProvider();

  static final IdGenerator _unwiredIdGenerator = _UnwiredIdGenerator();

  static final Clock _unwiredClock = _UnwiredClock();

  static CreateCompetition _absentCreateCompetition() => CreateCompetition(
    repository: _unwiredCompetitionRepository,
    idGenerator: _unwiredIdGenerator,
  );

  static StartSeason _absentStartSeason() => StartSeason(
    repository: _unwiredCompetitionRepository,
    idGenerator: _unwiredIdGenerator,
  );

  static LinkFixtureToRound _absentLinkFixtureToRound() =>
      LinkFixtureToRound(_unwiredCompetitionRepository);

  static RemoveFixtureFromRound _absentRemoveFixtureFromRound() =>
      RemoveFixtureFromRound(
        competitionRepository: _unwiredCompetitionRepository,
        fixtureResultRepository: _unwiredFixtureResultRepository,
      );

  static JoinCompetition _absentJoinCompetition() => JoinCompetition(
    repository: _unwiredCompetitionRepository,
    idGenerator: _unwiredIdGenerator,
    clock: _unwiredClock,
  );

  // Read-only Competition-browse query use-cases (BLOCKER FA-1). Each stand-in
  // is wired to the same loud throwing repository as the write use-cases above,
  // so a route test that reaches an unwired browse slice fails loudly.
  static GetCompetition _absentGetCompetition() =>
      GetCompetition(repository: _unwiredCompetitionRepository);

  static GetRound _absentGetRound() =>
      GetRound(repository: _unwiredCompetitionRepository);

  static ListCompetitions _absentListCompetitions() =>
      ListCompetitions(repository: _unwiredCompetitionRepository);

  static ListCompetitionSeasons _absentListCompetitionSeasons() =>
      ListCompetitionSeasons(repository: _unwiredCompetitionRepository);

  static ListMonthlySeasons _absentListMonthlySeasons() =>
      ListMonthlySeasons(repository: _unwiredCompetitionRepository);

  static GetCurrentSeason _absentGetCurrentSeason() => GetCurrentSeason(
    repository: _unwiredCompetitionRepository,
    clock: _unwiredClock,
  );

  static ListSeasonRounds _absentListSeasonRounds() =>
      ListSeasonRounds(repository: _unwiredCompetitionRepository);

  static BrowseRoundFixtures _absentBrowseRoundFixtures() =>
      BrowseRoundFixtures(
        competitionRepository: _unwiredCompetitionRepository,
        fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
      );

  static BrowseSeasonFixtures _absentBrowseSeasonFixtures() =>
      BrowseSeasonFixtures(
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
        fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
      );

  static LinkFixtureToSeason _absentLinkFixtureToSeason() =>
      LinkFixtureToSeason(
        competitionRepository: _unwiredCompetitionRepository,
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
      );

  static RemoveFixtureFromSeason _absentRemoveFixtureFromSeason() =>
      RemoveFixtureFromSeason(
        competitionRepository: _unwiredCompetitionRepository,
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
        fixtureResultRepository: _unwiredFixtureResultRepository,
      );

  static ListCurrentMonthFixtures _absentListCurrentMonthFixtures() =>
      ListCurrentMonthFixtures(
        competitionRepository: _unwiredCompetitionRepository,
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
        fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
        clock: _unwiredClock,
      );

  /// A single throwing repository backing every "absent" prediction use-case,
  /// so a test that reaches an unwired prediction slice fails loudly instead of
  /// touching a real database.
  static final PredictionRepository _unwiredPredictionRepository =
      _UnwiredPredictionRepository();

  static SubmitPrediction _absentSubmitPrediction() => SubmitPrediction(
    predictionRepository: _unwiredPredictionRepository,
    competitionRepository: _unwiredCompetitionRepository,
    fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
    idGenerator: _unwiredIdGenerator,
    clock: _unwiredClock,
  );

  static GetMyPrediction _absentGetMyPrediction() => GetMyPrediction(
    predictionRepository: _unwiredPredictionRepository,
    competitionRepository: _unwiredCompetitionRepository,
  );

  static ListRoundPredictions _absentListRoundPredictions() =>
      ListRoundPredictions(
        predictionRepository: _unwiredPredictionRepository,
        competitionRepository: _unwiredCompetitionRepository,
      );

  /// Backs the "absent" fixture-prediction use-case, so a test that reaches
  /// an unwired Axiom-4-Amendment prediction slice fails loudly instead of
  /// touching a real database.
  static final FixturePredictionRepository _unwiredFixturePredictionRepository =
      _UnwiredFixturePredictionRepository();

  static SubmitFixturePrediction _absentSubmitFixturePrediction() =>
      SubmitFixturePrediction(
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
        competitionRepository: _unwiredCompetitionRepository,
        fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
        idGenerator: _unwiredIdGenerator,
        clock: _unwiredClock,
      );

  /// Throwing scoring repositories backing every "absent" scoring use-case, so
  /// a test that reaches an unwired scoring slice fails loudly instead of
  /// touching a real database.
  static final FixtureResultRepository _unwiredFixtureResultRepository =
      _UnwiredFixtureResultRepository();

  static RecordFixtureResult _absentRecordFixtureResult() =>
      RecordFixtureResult(
        resultRepository: _unwiredFixtureResultRepository,
        fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
        clock: _unwiredClock,
      );

  static final FixtureScheduleRepository _unwiredFixtureScheduleRepository =
      _UnwiredFixtureScheduleRepository();

  static RegisterFixtureSchedule _absentRegisterFixtureSchedule() =>
      RegisterFixtureSchedule(
        repository: _unwiredFixtureScheduleRepository,
        idGenerator: _unwiredIdGenerator,
      );

  static CorrectFixtureSchedule _absentCorrectFixtureSchedule() =>
      CorrectFixtureSchedule(
        _unwiredFixtureScheduleRepository,
        auditRecorder: _absentAuditRecorder(),
        clock: _unwiredClock,
      );

  static final TeamRepository _unwiredTeamRepository = _UnwiredTeamRepository();

  static ListTeams _absentListTeams() =>
      ListTeams(repository: _unwiredTeamRepository);

  static final LeagueRepository _unwiredLeagueRepository =
      _UnwiredLeagueRepository();

  static ListLeagues _absentListLeagues() =>
      ListLeagues(repository: _unwiredLeagueRepository);

  /// Backs the "absent" fixture-scoring use-case, so a test that reaches an
  /// unwired Axiom-4-Amendment scoring slice fails loudly instead of touching
  /// a real database.
  static final FixtureScoreRepository _unwiredFixtureScoreRepository =
      _UnwiredFixtureScoreRepository();

  static ScoreFixture _absentScoreFixture() => ScoreFixture(
    fixturePredictionRepository: _unwiredFixturePredictionRepository,
    resultRepository: _unwiredFixtureResultRepository,
    scoreRepository: _unwiredFixtureScoreRepository,
    rulesetProvider: _unwiredRulesetProvider,
  );

  /// Throwing ledger repositories backing every "absent" ledger use-case, so a
  /// test that reaches an unwired ledger slice fails loudly instead of touching
  /// a real database.
  static final LedgerRepository _unwiredLedgerRepository =
      _UnwiredLedgerRepository();

  static final ParticipantReader _unwiredParticipantReader =
      _UnwiredParticipantReader();

  // Unlike its siblings this one ANSWERS rather than throws. The snapshot is
  // decoration on a board: a root that wires the fixture-leaderboard slice
  // without a snapshot reader should render a board with no arrows, not fail.
  static final RankSnapshotReader _unwiredRankSnapshotReader =
      _EmptyRankSnapshotReader();

  static ReadParticipantLedger _absentReadParticipantLedger() =>
      ReadParticipantLedger(
        participantReader: _unwiredParticipantReader,
        ledgerRepository: _unwiredLedgerRepository,
      );

  /// A single throwing repository backing the "absent" leaderboard use-case, so
  /// a test that reaches an unwired leaderboard slice fails loudly instead of
  /// touching a real database.
  static final LeaderboardRepository _unwiredLeaderboardRepository =
      _UnwiredLeaderboardRepository();

  static GetSeasonLeaderboard _absentGetSeasonLeaderboard() =>
      GetSeasonLeaderboard(
        leaderboardRepository: _unwiredLeaderboardRepository,
        competitionRepository: _unwiredCompetitionRepository,
      );

  /// Backs the "absent" [ListMySeasonRecords] -- throws on use, mirroring
  /// [_absentGetSeasonLeaderboard].
  static ListMySeasonRecords _absentListMySeasonRecords() =>
      ListMySeasonRecords(leaderboardRepository: _unwiredLeaderboardRepository);

  /// Backs the "absent" [GetSeasonFixtureLeaderboard]'s repositories: throws
  /// so a test that reaches this path fails loudly instead of silently
  /// touching a real database — mirrors [_absentGetSeasonLeaderboard].
  static GetSeasonFixtureLeaderboard _absentGetSeasonFixtureLeaderboard() =>
      GetSeasonFixtureLeaderboard(
        competitionRepository: _unwiredCompetitionRepository,
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
        fixtureTotalsReader: _UnwiredFixtureTotalsReader(),
        fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
        participantReader: _unwiredParticipantReader,
        rankSnapshotReader: _unwiredRankSnapshotReader,
      );

  /// Backs the "absent" [GetFixtureScores]'s repositories: throws so a
  /// test that reaches this path fails loudly instead of silently touching
  /// a real database — mirrors [_absentGetSeasonFixtureLeaderboard].
  static GetFixturePredictionDistribution
  _absentGetFixturePredictionDistribution() => GetFixturePredictionDistribution(
    fixturePredictionRepository: _unwiredFixturePredictionRepository,
  );

  static GetFixtureScores _absentGetFixtureScores() => GetFixtureScores(
    competitionRepository: _unwiredCompetitionRepository,
    fixturePredictionRepository: _unwiredFixturePredictionRepository,
    fixtureScoreRepository: _unwiredFixtureScoreRepository,
  );

  /// Backs the "absent" [AdminGetFixtureScores]: throws so a test that
  /// reaches this admin-bypass path fails loudly instead of silently
  /// touching a real database — mirrors _absentAdminGetRoundScores.
  static AdminGetFixtureScores _absentAdminGetFixtureScores() =>
      AdminGetFixtureScores(
        fixtureScoreRepository: _unwiredFixtureScoreRepository,
      );

  /// Backs the "absent" [GetHallOfFame]: throws so a test that reaches an
  /// unwired Hall of Fame slice fails loudly instead of touching a real
  /// database.
  static GetHallOfFame _absentGetHallOfFame() =>
      GetHallOfFame(leaderboardRepository: _unwiredLeaderboardRepository);

  /// Backs the "absent" [GetSportingSeasonLeaderboard]: its reader and clock
  /// both throw, so a test that reaches it fails loudly.
  static GetSportingSeasonLeaderboard _absentGetSportingSeasonLeaderboard() =>
      GetSportingSeasonLeaderboard(
        reader: _UnwiredSportingSeasonStandingsReader(),
        clock: _unwiredClock,
      );

  /// A single throwing repository backing every "absent" group use-case, so a
  /// test that reaches an unwired group slice fails loudly instead of touching
  /// a real database. The same instance implements BOTH `GroupRepository` AND
  /// `GroupStandingsReader` (the production `PostgresGroupRepository` does too),
  /// so it also backs the absent group-leaderboard read.
  static final _UnwiredGroupRepository _unwiredGroupRepository =
      _UnwiredGroupRepository();

  static final InviteCodeGenerator _unwiredInviteCodeGenerator =
      _UnwiredInviteCodeGenerator();

  static CreateGroup _absentCreateGroup() => CreateGroup(
    repository: _unwiredGroupRepository,
    idGenerator: _unwiredIdGenerator,
    inviteCodeGenerator: _unwiredInviteCodeGenerator,
    clock: _unwiredClock,
  );

  static GetGroup _absentGetGroup() =>
      GetGroup(repository: _unwiredGroupRepository);

  static JoinGroupByInvite _absentJoinGroupByInvite() => JoinGroupByInvite(
    repository: _unwiredGroupRepository,
    idGenerator: _unwiredIdGenerator,
    clock: _unwiredClock,
  );

  static RenameGroup _absentRenameGroup() =>
      RenameGroup(repository: _unwiredGroupRepository);

  static RegenerateInvite _absentRegenerateInvite() => RegenerateInvite(
    repository: _unwiredGroupRepository,
    inviteCodeGenerator: _unwiredInviteCodeGenerator,
  );

  static ListGroupMembers _absentListGroupMembers() =>
      ListGroupMembers(repository: _unwiredGroupRepository);

  static ListMyGroups _absentListMyGroups() =>
      ListMyGroups(repository: _unwiredGroupRepository);

  static GetGroupLeaderboard _absentGetGroupLeaderboard() =>
      GetGroupLeaderboard(
        repository: _unwiredGroupRepository,
        standingsReader: _unwiredGroupRepository,
      );

  /// A single throwing reaction repository backing every "absent" Social
  /// reaction use-case, and a throwing feed reader backing the "absent" feed
  /// read, so a test that reaches an unwired social slice fails loudly instead
  /// of touching a real database. The group gate reuses the same
  /// `_unwiredGroupRepository` as the Groups slice.
  static final ReactionRepository _unwiredReactionRepository =
      _UnwiredReactionRepository();

  static final ActivityFeedReader _unwiredActivityFeedReader =
      _UnwiredActivityFeedReader();
  static final FixtureLedgerRepository _unwiredFixtureLedgerRepository =
      _UnwiredFixtureLedgerRepository();
  static final FixtureReactionRepository _unwiredFixtureReactionRepository =
      _UnwiredFixtureReactionRepository();

  static ReactToRound _absentReactToRound() => ReactToRound(
    reactions: _unwiredReactionRepository,
    groups: _unwiredGroupRepository,
    idGenerator: _unwiredIdGenerator,
    clock: _unwiredClock,
  );

  static RemoveReaction _absentRemoveReaction() => RemoveReaction(
    reactions: _unwiredReactionRepository,
    groups: _unwiredGroupRepository,
  );

  static ListRoundReactions _absentListRoundReactions() => ListRoundReactions(
    reactions: _unwiredReactionRepository,
    groups: _unwiredGroupRepository,
  );

  static PostFixtureToLedger _absentPostFixtureToLedger() =>
      PostFixtureToLedger(
        fixtureScoreRepository: _unwiredFixtureScoreRepository,
        fixtureLedgerRepository: _unwiredFixtureLedgerRepository,
        idGenerator: _unwiredIdGenerator,
        clock: _unwiredClock,
      );

  static ReactToFixture _absentReactToFixture() => ReactToFixture(
    reactions: _unwiredFixtureReactionRepository,
    groups: _unwiredGroupRepository,
    idGenerator: _unwiredIdGenerator,
    clock: _unwiredClock,
  );

  static RemoveFixtureReaction _absentRemoveFixtureReaction() =>
      RemoveFixtureReaction(
        reactions: _unwiredFixtureReactionRepository,
        groups: _unwiredGroupRepository,
      );

  static ListFixtureReactions _absentListFixtureReactions() =>
      ListFixtureReactions(
        reactions: _unwiredFixtureReactionRepository,
        groups: _unwiredGroupRepository,
      );

  static GetGroupActivityFeed _absentGetGroupActivityFeed() =>
      GetGroupActivityFeed(
        feed: _unwiredActivityFeedReader,
        groups: _unwiredGroupRepository,
      );

  /// A single throwing notification repository backing every "absent"
  /// Notifications use-case, so a test that reaches an unwired notification
  /// slice fails loudly instead of touching a real database. The three
  /// recipient-facing use-cases (`ListMyNotifications`/`GetUnreadCount`/
  /// `MarkNotificationRead`) are the only client-callable notification surface
  /// (decision #4 — creation is server-triggered only, no client route).
  static final NotificationRepository _unwiredNotificationRepository =
      _UnwiredNotificationRepository();

  /// Backs the "absent" [EnsureUpcomingMonthlySeasons]: its repository
  /// throws, so a test that reaches it fails loudly.
  static EnsureUpcomingMonthlySeasons _absentEnsureUpcomingMonthlySeasons() =>
      EnsureUpcomingMonthlySeasons(
        repository: _unwiredCompetitionRepository,
        idGenerator: _unwiredIdGenerator,
      );

  /// Backs the "absent" [SettleMatchDays]: its store throws, so a test that
  /// reaches it fails loudly.
  static SettleMatchDays _absentSettleMatchDays() =>
      SettleMatchDays(store: _UnwiredMatchDaySettlementStore());

  /// Backs the "absent" [CloseWeeklyLeague]: its store throws, so a test that
  /// reaches it fails loudly.
  static CloseWeeklyLeague _absentCloseWeeklyLeague() => CloseWeeklyLeague(
    closures: _UnwiredWeeklyLeagueClosureStore(),
    standings: _UnwiredWeeklyLeagueStandingsReader(),
    events: _UnwiredGamificationEventSink(),
    idGenerator: _unwiredIdGenerator,
  );

  /// Backs the "absent" [EvaluateBadges]: its reader throws, so a test that
  /// reaches it fails loudly.
  static EvaluateBadges _absentEvaluateBadges() => EvaluateBadges(
    progress: _UnwiredBadgeProgressReader(),
    events: _UnwiredGamificationEventSink(),
    idGenerator: _unwiredIdGenerator,
  );

  /// Backs an "absent" [SendPredictionReminders]: the reminder sweep is
  /// never exercised by a route test, and a silent no-op would hide a
  /// wiring bug in the one test that does reach it.
  static SendPredictionReminders _absentSendPredictionReminders() =>
      SendPredictionReminders(
        reminders: _UnwiredPredictionReminderRepository(),
        sender: const NoopPushSender(),
        preferences: _UnwiredNotificationPreferenceRepository(),
      );

  /// Backs an "absent" [SendPreMatchReminders]: like the reminder sweep,
  /// never reached by a route test, and loud if one ever does.
  static SendPreMatchReminders _absentSendPreMatchReminders() =>
      SendPreMatchReminders(
        reminders: _UnwiredPreMatchReminderRepository(),
        budget: _UnwiredPredictionReminderRepository(),
        sender: const NoopPushSender(),
      );

  /// Backs an "absent" [SendStreakSavers]: never reached by a route test.
  static SendStreakSavers _absentSendStreakSavers() => SendStreakSavers(
    savers: _UnwiredStreakSaverRepository(),
    streaks: _UnwiredStreakRepository(),
    budget: _UnwiredPredictionReminderRepository(),
    sender: const NoopPushSender(),
  );

  /// Backs an "absent" [SendOvertakenPushes]: never reached by a route test.
  static SendOvertakenPushes _absentSendOvertakenPushes() =>
      SendOvertakenPushes(
        overtaken: _UnwiredOvertakenRepository(),
        standings: _UnwiredWeeklyLeagueStandingsReader(),
        profiles: _UnwiredWeeklyLeagueProfileReader(),
        budget: _UnwiredPredictionReminderRepository(),
        sender: const NoopPushSender(),
      );

  /// Builds an "absent" [RecordPushOpen] over a repository that throws if a
  /// test reaches the slice it never wired.
  static RecordPushOpen _absentRecordPushOpen() =>
      RecordPushOpen(opens: _UnwiredPushOpenRepository(), clock: _unwiredClock);

  /// Backs an "absent" [FlushNotificationQueue]: like the reminder sweep,
  /// never reached by a route test, and loud if one ever does.
  static FlushNotificationQueue _absentFlushNotificationQueue() =>
      FlushNotificationQueue(
        queue: _UnwiredNotificationQueue(),
        sender: const NoopPushSender(),
      );

  /// Backs an "absent" [RegisterDeviceToken]: a test that reaches the
  /// device-token slice without wiring it has a wiring bug, and a silent
  /// no-op would hide it. Separate from the notification repository -- a
  /// different table (notification.device_tokens), not the aggregate.
  static final DeviceTokenRepository _unwiredDeviceTokenRepository =
      _UnwiredDeviceTokenRepository();

  static RegisterDeviceToken _absentRegisterDeviceToken() =>
      RegisterDeviceToken(deviceTokens: _unwiredDeviceTokenRepository);

  static ListMyNotifications _absentListMyNotifications() =>
      ListMyNotifications(notifications: _unwiredNotificationRepository);

  /// A single throwing announcement repository backing every "absent"
  /// announcement use-case, so a test that reaches the broadcast slice
  /// without wiring it fails loudly instead of touching a real database.
  static final AnnouncementRepository _unwiredAnnouncementRepository =
      _UnwiredAnnouncementRepository();

  static ListMyNotificationFeed _absentListMyNotificationFeed() =>
      ListMyNotificationFeed(
        list: _absentListMyNotifications(),
        announcements: _unwiredAnnouncementRepository,
      );

  static PublishAnnouncement _absentPublishAnnouncement() =>
      PublishAnnouncement(
        announcements: _unwiredAnnouncementRepository,
        create: CreateNotification(
          notifications: _unwiredNotificationRepository,
          idGenerator: _unwiredIdGenerator,
          clock: _unwiredClock,
        ),
        sender: const NoopPushSender(),
        idGenerator: _unwiredIdGenerator,
        clock: _unwiredClock,
        queue: _UnwiredNotificationQueue(),
      );

  static GetUnreadCount _absentGetUnreadCount() =>
      GetUnreadCount(notifications: _unwiredNotificationRepository);

  static MarkNotificationRead _absentMarkNotificationRead() =>
      MarkNotificationRead(
        notifications: _unwiredNotificationRepository,
        clock: _unwiredClock,
      );

  /// Throwing admin repositories backing every "absent" Admin Panel use-case,
  /// so a test that reaches an unwired admin slice fails loudly instead of
  /// touching a real database. The user-sanction path (`SuspendUser`/
  /// `ReinstateUser`) and the support-read path (`ViewParticipantLedger`) both
  /// record to the audit trail, so their stand-ins share one throwing
  /// `AuditRecorder` over a throwing `_UnwiredAuditLogRepository`; the support
  /// read reuses the same throwing participant reader + ledger repository as the
  /// Ledger slice.
  static final UserAdminRepository _unwiredUserAdminRepository =
      _UnwiredUserAdminRepository();

  static final AuditLogRepository _unwiredAuditLogRepository =
      _UnwiredAuditLogRepository();

  static AuditRecorder _absentAuditRecorder() => AuditRecorder(
    auditLog: _unwiredAuditLogRepository,
    idGenerator: _unwiredIdGenerator,
    clock: _unwiredClock,
  );

  static SuspendUser _absentSuspendUser() => SuspendUser(
    users: _unwiredUserAdminRepository,
    auditRecorder: _absentAuditRecorder(),
  );

  static ReinstateUser _absentReinstateUser() => ReinstateUser(
    users: _unwiredUserAdminRepository,
    auditRecorder: _absentAuditRecorder(),
  );

  static ListUsers _absentListUsers() =>
      ListUsers(users: _unwiredUserAdminRepository);

  static ListAuditLog _absentListAuditLog() =>
      ListAuditLog(auditLog: _unwiredAuditLogRepository);

  static ViewParticipantLedger _absentViewParticipantLedger() =>
      ViewParticipantLedger(
        participantReader: _unwiredParticipantReader,
        ledgerRepository: _unwiredLedgerRepository,
        auditRecorder: _absentAuditRecorder(),
      );
  static AdminListRoundPredictions _absentAdminListRoundPredictions() =>
      AdminListRoundPredictions(
        competitionRepository: _unwiredCompetitionRepository,
        predictionRepository: _unwiredPredictionRepository,
        auditRecorder: _absentAuditRecorder(),
      );

  static AdminListFixturePredictions _absentAdminListFixturePredictions() =>
      AdminListFixturePredictions(
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
        auditRecorder: _absentAuditRecorder(),
      );

  static AdminGetUserFixturePredictions
  _absentAdminGetUserFixturePredictions() => AdminGetUserFixturePredictions(
    userAdminRepository: _unwiredUserAdminRepository,
    fixturePredictionRepository: _unwiredFixturePredictionRepository,
    fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
    fixtureResultRepository: _unwiredFixtureResultRepository,
    fixtureScoreRepository: _unwiredFixtureScoreRepository,
    auditRecorder: _absentAuditRecorder(),
  );

  static ListMyFixturePredictions _absentListMyFixturePredictions() =>
      ListMyFixturePredictions(
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
      );

  static ListMyActiveSeasons _absentListMyActiveSeasons() =>
      ListMyActiveSeasons(
        competitionRepository: _unwiredCompetitionRepository,
        clock: _unwiredClock,
      );

  /// The Postgres connection owned by a production root. Null for roots built
  /// via [CompositionRoot.forTesting], which own no infrastructure.
  final PostgresConnection? _connection;

  /// The JWKS client owned by a production root, closed on [dispose]. Null for
  /// test roots.
  final JwksClient? _jwksClient;

  /// The health use-case, ready to be invoked by routes.
  final CheckHealth checkHealth;

  /// Reports the newest published Android build, ready to be invoked by
  /// routes.
  final GetLatestBuild getLatestBuild;

  /// Logs in with email/password, exchanging credentials for a session.
  final LoginWithPassword login;

  /// Registers a new email/password account.
  final RegisterWithPassword register;
  final RequestPasswordReset requestPasswordReset;
  final UpdatePassword updatePassword;

  /// Changes the caller's own display name (backs `PATCH /me/display-name`).
  final UpdateDisplayName updateDisplayName;

  /// Records the caller's own offset from UTC (backs `POST /me/time-zone`).
  /// Notification timing only — no day boundary is derived from it.
  final UpdateTimeZoneOffset updateTimeZoneOffset;

  /// Counts the caller's run of completed match days (backs
  /// `GET /me/streak`). Derived from the event stream on every read.
  final GetMyStreak getMyStreak;

  /// The caller's accuracy, patterns and last week's recap (backs
  /// `GET /me/insights`, plan P4-4).
  final GetMyInsights getMyInsights;

  /// Reports how much of today's match day the caller has covered (backs
  /// `GET /me/daily-challenge`). Computed per request over the caller's
  /// active seasons; nothing is stored.
  final GetMyDailyChallenge getMyDailyChallenge;

  /// Reads the caller's own weekly-league group, ranked (backs
  /// `GET /me/weekly-league`). Seats the caller on first sight; computed per
  /// request from the one source of points, nothing weekly is stored.
  final GetMyWeeklyLeague getMyWeeklyLeague;

  /// Reads the caller's badge wall: every catalog badge, progress and grant
  /// moment (backs `GET /me/badges`). Read-only; the evaluator grants.
  final GetMyBadges getMyBadges;

  /// Reads the caller's notification switches, defaults when never changed
  /// (backs `GET /me/notification-preferences`).
  final GetMyNotificationPreferences getMyNotificationPreferences;

  /// Stores the caller's notification switches (backs
  /// `PUT /me/notification-preferences`). The reminder sweep reads them.
  final UpdateMyNotificationPreferences updateMyNotificationPreferences;

  /// Reads the teams the caller follows (backs `GET /me/favorite-teams`).
  final GetMyFavoriteTeams getMyFavoriteTeams;

  /// Replaces the teams the caller follows, at most three (backs
  /// `PUT /me/favorite-teams`).
  final SetMyFavoriteTeams setMyFavoriteTeams;

  /// Decides which arm of a flagged experiment a user is in (P1-8).
  ///
  /// Backend-only and, as of P1-8, deliberately unreferenced: the
  /// machinery ships before the first experiment so that starting one is a
  /// flag row and a call site, not a three-layer change. Do not delete it
  /// as dead code.
  final ResolveExperimentVariant resolveExperimentVariant;

  /// Establishes the request principal from an `Authorization` header.
  final AuthenticateRequest authenticateRequest;

  /// Resolves the canonical [User] for a verified principal (backs `/me`).
  final GetCurrentUser getCurrentUser;

  /// Puts the caller into whatever contest is running, on every `/me`.
  final EnrolInOpenSeasons enrolInOpenSeasons;

  /// Sets or replaces the caller's own profile picture.
  final SetAvatar setAvatar;

  /// Removes the caller's own profile picture.
  final ClearAvatar clearAvatar;

  /// Serves a user's stored picture -- the only path image bytes travel.
  final ReadAvatar readAvatar;

  /// Creates a competition (admin-only command).
  final CreateCompetition createCompetition;

  /// Starts a season under a competition (admin-only command).
  final StartSeason startSeason;

  /// Links a fixture to an open round (admin-only command).
  final LinkFixtureToRound linkFixtureToRound;
  final RemoveFixtureFromRound removeFixtureFromRound;

  /// Enrols the calling user into a season (any authenticated user).
  final JoinCompetition joinCompetition;

  /// Reads a single competition by id (any authenticated user; the browse
  /// detail read — BLOCKER FA-1). Read-only, no side effect.
  final GetCompetition getCompetition;

  /// Reads a single round by id (any authenticated user; renders a round's
  /// status/deadline before the prediction form — BLOCKER FA-1).
  final GetRound getRound;

  /// Lists the browsable public competition catalogue (any authenticated user;
  /// the discovery read — BLOCKER FA-1). Never a points/write path.
  final ListCompetitions listCompetitions;

  /// Lists the monthly contest seasons (label `MM/YYYY`) across every
  /// competition, newest first -- the months an admin files fixtures
  /// into. Any authenticated user.
  final ListMonthlySeasons listMonthlySeasons;

  /// Lists a competition's seasons ordered by label (any authenticated user;
  /// the browse navigation step competition → season — BLOCKER FA-1 / DEFECT
  /// AD-2). The domain has no "current/active season" concept, so a multi-season
  /// competition must be browsed season-by-season. Read-only, no side effect.
  final ListCompetitionSeasons listCompetitionSeasons;

  /// Resolves the single "current" monthly season of a competition (any
  /// authenticated user; 7.7 step 4). Computed fresh from `start_at`/`end_at`
  /// against "now" -- never a stored/persisted flag. Absent for the current
  /// month is a legitimate `null`, never an error.
  final GetCurrentSeason getCurrentSeason;

  /// Lists a season's rounds in sequence order (any authenticated user; the
  /// browse navigation step competition → season → round — BLOCKER FA-1).
  final ListSeasonRounds listSeasonRounds;

  /// Lists a round's fixtures in matchday order, each enriched with its
  /// schedule identity (team names + kickoff), for the prediction-form
  /// render (any authenticated user; Session decision 2026-08-07 widened
  /// the former `ListRoundFixtures` read instead of a new endpoint). This is
  /// the Competition-context browse read, distinct from the Prediction phase's
  /// internal `PredictionRepository.listRoundFixtures`.
  final BrowseRoundFixtures browseRoundFixtures;

  /// Lists a season's fixtures in display order, each enriched with its
  /// schedule identity (team names + kickoff), for the per-fixture
  /// prediction browse read (any authenticated user; Axiom 4 Amendment — the
  /// season-scoped sibling of [browseRoundFixtures], since a fixture's
  /// prediction belongs to its season directly via `SeasonFixture`, never a
  /// round). Read-only, no side effect.
  final BrowseSeasonFixtures browseSeasonFixtures;

  /// Links a fixture to a season (admin-only command; Axiom 4 Amendment —
  /// the per-fixture sibling of [linkFixtureToRound]).
  final LinkFixtureToSeason linkFixtureToSeason;

  /// Removes a fixture from a season (admin-only command), refusing once the
  /// fixture carries any prediction or a recorded result — see
  /// [RemoveFixtureFromSeason] for why those are hard refusals.
  final RemoveFixtureFromSeason removeFixtureFromSeason;

  /// The current-month fixture feed: every public competition's current
  /// (calendar-month) season, fixtures flattened into one ordered list --
  /// the Monthly Competitions home read (project-context.md section 9).
  /// Read-only, no side effect.
  final ListCurrentMonthFixtures listCurrentMonthFixtures;

  /// Submits (or idempotently amends) the caller's prediction for a round.
  final SubmitPrediction submitPrediction;

  /// Submits (or idempotently amends) the caller's prediction for a single
  /// fixture (Axiom 4 Amendment; per-fixture sibling of [submitPrediction]).
  final SubmitFixturePrediction submitFixturePrediction;

  /// Reads the caller's own prediction for a round (any status; self-read).
  final GetMyPrediction getMyPrediction;

  /// Lists every participant's prediction for a locked round (visibility-gated).
  final ListRoundPredictions listRoundPredictions;

  /// Records the actual result of a fixture (admin-only ingestion; the Axiom-3
  /// football seam).
  final RecordFixtureResult recordFixtureResult;

  final RegisterFixtureSchedule registerFixtureSchedule;

  final CorrectFixtureSchedule correctFixtureSchedule;

  /// Scores every prediction recorded for a single fixture (Axiom 4
  /// Amendment; "ScoreFixture replaces ScoreRound" — per-fixture sibling of
  /// scoreRound, admin-only, computed and written server-side).
  final ScoreFixture scoreFixture;

  final AdminGetParticipantDisplayNames adminGetParticipantDisplayNames;

  static AdminGetParticipantDisplayNames
  _absentAdminGetParticipantDisplayNames() => AdminGetParticipantDisplayNames(
    participantReader: _unwiredParticipantReader,
  );

  /// Reads a participant's projected balance / append-only entry stream
  /// (self-read only — a caller sees only a participant they own).
  final ReadParticipantLedger readParticipantLedger;

  /// Reads a season's ranked standings — its leaderboard (a read-side projection
  /// over the append-only ledger; season-membership gated, never a points
  /// write — Axioms 1/5).
  final GetSeasonLeaderboard getSeasonLeaderboard;

  /// Reads the caller's own season-by-season record (`GET /me/seasons`) --
  /// one row per season they have played, scoped to their own user id by the
  /// use-case, never a points write.
  final ListMySeasonRecords listMySeasonRecords;

  /// Reads a season's live, "monthly" fixture leaderboard (Axiom 4
  /// Amendment; a read-side projection aggregating every already-computed
  /// per-fixture score for the season, live/partial by construction — never
  /// gated on the season being finished; season-membership gated only).
  final GetSeasonFixtureLeaderboard getSeasonFixtureLeaderboard;
  final GetFixtureScores getFixtureScores;

  /// Reads the aggregated home/away win shares displayed on fixture cards.
  final GetFixturePredictionDistribution getFixturePredictionDistribution;

  /// Admin fixture-scores read — same shape as [getFixtureScores] but
  /// without the participant-of-season gate (added so an admin can
  /// investigate a user's complaint on any fixture regardless of the
  /// admin's own season membership).
  final AdminGetFixtureScores adminGetFixtureScores;

  /// Reads the platform-wide, all-time standings (the Hall of Fame) — a
  /// read-side projection over the SAME append-only ledger aggregated across
  /// every season (Axiom 5); visible to any authenticated user, unlike the
  /// season board.
  final GetHallOfFame getHallOfFame;

  /// Reads the current sporting season's standings: the monthly boards from
  /// September to August summed per user.
  final GetSportingSeasonLeaderboard getSportingSeasonLeaderboard;

  /// Creates a new private group (any authenticated user; the creator becomes
  /// the sole owner, owner membership written atomically — Groups decision #2).
  final CreateGroup createGroup;

  /// Reads a single group + its member count (member-only visibility gate, no
  /// existence oracle — Groups decision #3).
  final GetGroup getGroup;

  /// Joins a group via its shareable invite code (any authenticated user;
  /// zero-friction instant join, idempotent — Groups decision #2/#3).
  final JoinGroupByInvite joinGroupByInvite;

  /// Renames a group (owner-only, per-group `GroupRole` gate in the use-case —
  /// Groups decision #2).
  final RenameGroup renameGroup;

  /// Regenerates a group's invite code, revoking the previously-shared link
  /// (owner-only — Groups decision #2/#3).
  final RegenerateInvite regenerateInvite;

  /// Lists a group's members (member-only visibility gate, no existence oracle —
  /// Groups decision #3).
  final ListGroupMembers listGroupMembers;

  /// Lists every group the caller belongs to ("My Groups") — an OWNERSHIP
  /// read (mirror of [readParticipantLedger]'s "only my own ledger" shape),
  /// NOT the per-group member-only gate [listGroupMembers]/[getGroup] use.
  final ListMyGroups listMyGroups;

  /// Reads a group's ranked standings for a season — the season leaderboard
  /// projection filtered to the group's membership (member-only; NO new points
  /// source, NO new ranking logic — Groups decision #4, Axiom 5).
  final GetGroupLeaderboard getGroupLeaderboard;

  /// Records (or idempotently changes) a member's emoji reaction to a
  /// round-result within a group (any authenticated user, member-gated;
  /// Tier-3 — a failure never blocks a Tier-1 core operation — Social
  /// decisions #1/#2/#4).
  final ReactToRound reactToRound;

  /// Removes the caller's own reaction to a round-result within a group
  /// (member-gated, idempotent — Social decision #2).
  final RemoveReaction removeReaction;

  /// Lists a round-result's reactions within a group (member-gated read —
  /// Social decision #3).
  final ListRoundReactions listRoundReactions;

  /// Posts a scored fixture to the append-only Ledger (Axiom 4 Amendment;
  /// admin-only, enforced inside the use-case — the per-fixture sibling of
  /// postRoundToLedger).
  final PostFixtureToLedger postFixtureToLedger;

  /// Reacts (or changes a reaction) to a fixture-result within a group
  /// (member-gated — Axiom 4 Amendment; the per-fixture sibling of
  /// [reactToRound]).
  final ReactToFixture reactToFixture;

  /// Removes the caller's own reaction to a fixture-result within a group
  /// (member-gated, idempotent — Axiom 4 Amendment; the per-fixture sibling
  /// of [removeReaction]).
  final RemoveFixtureReaction removeFixtureReaction;

  /// Lists a fixture-result's reactions within a group (member-gated read —
  /// Axiom 4 Amendment; the per-fixture sibling of [listRoundReactions]).
  final ListFixtureReactions listFixtureReactions;

  /// Reads a group's activity feed — a pure read projection over already-
  /// ratified data (member-gated; NO table, NEVER a source of truth — Social
  /// decision #2).
  final GetGroupActivityFeed getGroupActivityFeed;

  /// Lists the caller's OWN notifications, newest-first (recipient-only —
  /// Notifications decision #4; no membership check). The recipient is bound
  /// from the verified token, never a body/path.
  final ListMyNotifications listMyNotifications;

  /// The same inbox read as [listMyNotifications], with any admin-announcement
  /// text already resolved so the client renders a readable row rather than a
  /// bare kind token. This is what `GET /notifications` serves.
  final ListMyNotificationFeed listMyNotificationFeed;

  /// Publishes one admin instruction to every active user (admin-only; the
  /// audience is resolved server-side, never from the request body).
  final PublishAnnouncement publishAnnouncement;

  /// Reads the caller's OWN unread-notification count (recipient-only badge
  /// count — Notifications decision #4).
  final GetUnreadCount getUnreadCount;

  /// Marks the caller's OWN notification read (recipient-only, idempotent; a
  /// foreign/unknown id is refused identically as `notification.not_found` with
  /// no existence oracle — Notifications decision #4). The one client-safe
  /// Tier-3 mutation.
  final MarkNotificationRead markNotificationRead;

  /// Reminds everyone who has not predicted, three hours before the day's
  /// first kickoff. Driven by the scheduler, never by a request.
  final SendPredictionReminders sendPredictionReminders;

  /// Pushes the followers of a team whose match starts soon and who have
  /// not predicted it (plan P3-4a). Driven by the scheduler.
  final SendPreMatchReminders sendPreMatchReminders;

  /// Warns a player whose run breaks at the next kickoff (plan P3-4b).
  /// Driven by the scheduler.
  final SendStreakSavers sendStreakSavers;

  /// Tells a weekly-league member who was just overtaken (plan P3-4c).
  /// Driven by the scheduler.
  final SendOvertakenPushes sendOvertakenPushes;

  /// Records a tap on a push (backs `POST /me/push-opened`, plan P3-8).
  final RecordPushOpen recordPushOpen;

  /// Delivers the pushes deferred out of quiet hours once their time has
  /// come (P3-2). Driven by the scheduler, never by a request.
  final FlushNotificationQueue flushNotificationQueue;

  /// Creates the next monthly contest a week before it starts. Driven by
  /// the scheduler, never by a request.
  final EnsureUpcomingMonthlySeasons ensureUpcomingMonthlySeasons;

  /// Freezes each finished Riyadh match day for the streak calendar. Driven
  /// by the scheduler, never by a request.
  final SettleMatchDays settleMatchDays;

  /// Judges each finished weekly-league week and writes its standings into
  /// the event stream. Driven by the scheduler, never by a request.
  final CloseWeeklyLeague closeWeeklyLeague;

  /// Awards each catalog badge a player has earned and not yet been given.
  /// Driven by the scheduler, never by a request.
  final EvaluateBadges evaluateBadges;

  /// Automatic fixtures/results mode (`NUKHBA_PROVIDER_SYNC`); `off` when
  /// no provider key is configured.
  final ProviderSyncMode providerSyncMode;

  /// Adds the provider's selected fixtures; null while the sync is off.
  final SyncProviderFixtures? syncProviderFixtures;

  /// Records the provider's results; null while the sync is off.
  final SyncProviderResults? syncProviderResults;

  /// Running scores for the fixtures feed (display only); null in tests
  /// that do not provide one.
  final LiveScoreBoard? liveScoreBoard;

  /// Refreshes [liveScoreBoard]; null while the sync is off.
  final RefreshLiveScores? refreshLiveScores;

  /// Registers the caller's OWN device token for push delivery. Self-only:
  /// the owner is bound from the verified principal, never a body field.
  final RegisterDeviceToken registerDeviceToken;

  /// Suspends a user — the reversible admin sanction (admin-only, gated inside
  /// the use-case; a mandatory reason feeds the immutable audit record — Admin
  /// Panel decisions OPEN-A #1 / OPEN-B). The genuinely-new domain capability of
  /// the phase.
  final SuspendUser suspendUser;

  /// Reinstates a suspended user — the mirror of [suspendUser] (admin-only,
  /// mandatory reason, audited — decision OPEN-A #1).
  final ReinstateUser reinstateUser;

  /// Browses platform users by an optional email-contains search — the admin
  /// find-a-user flow feeding [suspendUser]/[reinstateUser] (admin-only).
  final ListUsers listUsers;

  /// Reads the append-only admin audit trail, newest-first (admin-only — the
  /// trail is itself a privileged surface; decision OPEN-B).
  final ListAuditLog listAuditLog;

  /// The narrow cross-user read-for-support: an admin reads a SINGLE
  /// participant's ledger by explicit id, the read itself audited (admin-only;
  /// never a bulk/export view — decision OPEN-A #3).
  final ViewParticipantLedger viewParticipantLedger;

  /// The admin round-report bulk read: every participant's raw prediction for
  /// one scored round, itself audited (admin-only — mirrors
  /// [viewParticipantLedger]'s no-silent-exemption rule).
  final AdminListRoundPredictions adminListRoundPredictions;

  /// The admin fixture-report bulk read: every participant's raw prediction
  /// for one fixture, itself audited (admin-only — mirrors
  /// [adminListRoundPredictions], but carries no fixture-status gate).
  final AdminListFixturePredictions adminListFixturePredictions;

  /// Reads the prediction history of exactly one selected platform user,
  /// itself audited and scoped by user id.
  final AdminGetUserFixturePredictions adminGetUserFixturePredictions;

  /// Lists the caller's own aggregated fixture-prediction history — every
  /// per-fixture prediction they have ever submitted, across every fixture
  /// and season, newest first. Always the caller's own forecasts; no
  /// season-membership gate.
  final ListMyFixturePredictions listMyFixturePredictions;

  /// Lists every season [principal] is an active participant in right now
  /// (participant-scoped analogue of [listMyFixturePredictions]; the client
  /// fans out per season to [browseSeasonFixtures]).
  final ListMyActiveSeasons listMyActiveSeasons;

  /// Lists the Football Data team catalog (backs `GET /teams`), so a client
  /// can resolve a fixture's team ids into a display name + crest without
  /// hardcoding either client-side. Any authenticated user.
  final ListTeams listTeams;

  /// Lists the Football Data league catalog (backs `GET /leagues`).
  final ListLeagues listLeagues;

  /// Builds the graph from process environment, failing fast on misconfig.
  static Future<CompositionRoot> bootstrap(Map<String, String> env) async {
    final config = _require(PostgresConfig.fromEnv(env), 'Postgres config');
    final authConfig = _require(
      AuthConfig.fromEnv(env),
      'Supabase auth config',
    );

    final connectionResult = await PostgresConnection.open(config);
    final connection = switch (connectionResult) {
      Ok<PostgresConnection>(:final value) => value,
      Err<PostgresConnection>(:final error) => throw StateError(
        'Cannot start: $error',
      ),
    };

    // Health slice.
    final checkHealth = CheckHealth(PostgresHealthRepository(connection));

    // Platform update-check slice: reads the newest published Android build
    // from GitHub Releases. Public/unauthenticated, like health.
    final getLatestBuild = GetLatestBuild(
      GithubBuildInfoRepository(http.Client()),
    );

    // Identity slice: JWKS-backed ES256 verifier (+ HS256 legacy fallback) and
    // the Postgres-backed canonical user directory.
    final jwksClient = JwksClient(authConfig.jwksUri);
    const jwksWarmupAttempts = 3;
    Result<void>? jwksWarmResult;
    for (var attempt = 1; attempt <= jwksWarmupAttempts; attempt++) {
      jwksWarmResult = await jwksClient.warmUp();
      if (jwksWarmResult is Ok<void>) break;
      if (attempt < jwksWarmupAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    if (jwksWarmResult is Err<void>) {
      throw StateError(
        'Cannot start: failed to warm JWKS cache after '
        '$jwksWarmupAttempts attempts: ${jwksWarmResult.error}',
      );
    }
    final verifier = SupabaseJwtVerifier(authConfig, jwksClient);
    final directory = CachedUserDirectory(PostgresUserDirectory(connection));

    // Identity slice (continued): email/password auth proxy, backed by
    // the existing SupabaseAuthClient adapted to the AuthGateway port.
    final authGateway = SupabaseAuthGateway(
      SupabaseAuthClient(config: authConfig, httpClient: http.Client()),
    );
    final login = LoginWithPassword(authGateway);
    final register = RegisterWithPassword(authGateway);
    final requestPasswordReset = RequestPasswordReset(authGateway);
    final updatePassword = UpdatePassword(authGateway);

    // Competition slice: the Postgres-backed repository, the configured
    // ruleset provider (the placeholder-free Scoring seam), and the shared
    // id/clock adapters. Every competition use-case is wired here so nothing
    // else in the server constructs infrastructure.
    final competitionRepository = PostgresCompetitionRepository(connection);
    const rulesetProvider = ConfiguredRulesetProvider();
    final idGenerator = UuidIdGenerator();
    const clock = SystemClock();

    // Prediction slice: the platform's highest-volume integrity-critical write
    // path, kept on its own Postgres-backed repository (aggregate separate from
    // Competition, Database ADR §2.1). Each use-case also reads the Competition
    // repository (round/participant resolution) without contending on its
    // writes. Points are never wired here — Scoring is a later phase.
    final predictionRepository = PostgresPredictionRepository(connection);

    // Axiom 4 Amendment: the per-fixture Prediction context, its own
    // Postgres-backed repository (kept separate, same reasoning as
    // predictionRepository above).
    final fixturePredictionRepository = PostgresFixturePredictionRepository(
      connection,
    );

    // The batched win-share read behind the current-month feed. Its own tiny
    // adapter rather than another method on the repository above -- see
    // FixturePredictionTallyReader for why.
    final fixturePredictionTallyReader = CachedFixturePredictionTallyReader(
      PostgresFixturePredictionTallyReader(connection),
    );

    // Scoring slice: its own Postgres-backed adapters over the scoring.* tables
    // (the actual-result seam — Axiom 3 option (a) — and the server-computed
    // round scores). ScoreRound reuses the competition + prediction repos
    // (round/ruleset/participant resolution + the one prediction per round) and
    // the pure domain scoring service; points are written server-side only
    // (Axioms 2/5). GetRoundScores gates the read to a scored round.
    final fixtureResultRepository = PostgresFixtureResultRepository(connection);

    // Axiom 4 Amendment: the per-fixture Scoring context, its own
    // Postgres-backed repository.
    final fixtureScoreRepository = CachedFixtureScoreRepository(
      PostgresFixtureScoreRepository(connection),
    );

    final fixtureScheduleRepository = CachedFixtureScheduleRepository(
      PostgresFixtureScheduleRepository(connection),
    );

    // Football Data slice: read-only team catalog backing `GET /teams`
    // (previously unwired schema — `football_data.teams`, migration
    // `0013_football_data.sql`), so a client can resolve a fixture's team ids
    // into a display name + crest without hardcoding either client-side.
    final teamRepository = CachedTeamRepository(
      PostgresTeamRepository(connection),
    );

    // Ledger slice: its own Postgres-backed adapters over the ledger.* tables
    // (the append-only PointEntry stream). PostRoundToLedger reads the scored
    // round (competition repo, gated on RoundStatus.scored) + its already-
    // persisted scores (score repo) and appends one round_score credit per
    // participant, idempotently on the ratified dedupe key (Axioms 2/4/5).
    // ReadParticipantLedger resolves a participant by id (the narrow
    // ParticipantReader port, over competition.participants) to gate the read
    // to a self-owned participant, then projects the balance / lists the stream.
    final ledgerRepository = PostgresLedgerRepository(connection);
    final participantReader = PostgresParticipantReader(connection);

    // Leaderboards slice: a read-only Postgres-backed adapter over the
    // season-scoped projection VIEW leaderboard.season_standings (a SUM(amount)
    // over the append-only ledger — never a second points source, Axiom 5).
    // GetSeasonLeaderboard reads the unranked projection + gates the read to a
    // member of the season (competition repo) and ranks it in the pure domain.
    final leaderboardRepository = PostgresLeaderboardRepository(connection);

    // Groups slice: a single Postgres-backed adapter over the group.* tables
    // (`PostgresGroupRepository` implements BOTH `GroupRepository` AND
    // `GroupStandingsReader`, so the same instance backs the group commands and
    // the group-leaderboard read). Groups are an orthogonal social container
    // (decision #1: NO competition/round/prediction/leaderboard object gains a
    // group ref). The invite code is server-generated via a crypto-strong
    // adapter (`UuidInviteCodeGenerator`, `dart:math` `Random.secure` — §3: no
    // new dependency). The group leaderboard reuses the ratified
    // `leaderboard.season_standings` VIEW intersected with group membership
    // (decision #4 — no new points source), ranked by the pure domain in the
    // use-case. Owner-authority (rename/regenerate) is a per-group `GroupRole`
    // gate inside the use-case, never the platform role.
    final groupRepository = PostgresGroupRepository(connection);
    final inviteCodeGenerator = UuidInviteCodeGenerator();

    // Social slice (Tier-3, peripheral, rebuildable — NEVER a source of truth;
    // Database ADR §3 / Deployment ADR §Tier-3). One Postgres-backed adapter
    // over the single new stored surface `social.reactions`
    // (`PostgresReactionRepository`) plus a pure read-projection reader for the
    // Activity Feed (`PostgresActivityFeedReader` — NO table, decision #2). All
    // social use-cases reuse the ratified group member gate
    // (`group.not_a_member`, no existence oracle — decision #3) via the same
    // `groupRepository` the Groups slice uses; the author is bound from the
    // verified token inside each use-case, never a body (Security ADR §2).
    // Social carries NO points (Axiom 5) and NO open-graph edge (ADR-001); a
    // Social failure is confined to its endpoint and never blocks a Tier-1
    // core operation (decision #4).
    final reactionRepository = PostgresReactionRepository(connection);
    final fixtureLedgerRepository = PostgresFixtureLedgerRepository(connection);
    final fixtureReactionRepository = PostgresFixtureReactionRepository(
      connection,
    );
    final activityFeedReader = PostgresActivityFeedReader(connection);

    // Notifications slice (Tier-3, peripheral, rebuildable — NEVER a source of
    // truth; Database ADR §3 / Deployment ADR §Tier-3). One Postgres-backed
    // adapter over the single new stored surface `notification.notifications`
    // (`PostgresNotificationRepository`). Only the three RECIPIENT-facing
    // use-cases are wired to a client route (decision #4: the read/mark surface
    // is recipient-only — a notification's recipient must equal the verified
    // principal; there is NO group/season membership check and NO client route
    // that creates a notification). Each recipient use-case binds the recipient
    // from the verified token, never a body (Security ADR §2); a foreign/unknown
    // id is refused identically as `notification.not_found` (no existence
    // oracle — mirror of the Ledger self-read). Notifications carries NO points
    // (Axiom 5) and NO open-graph edge (ADR-001); a failure is confined to its
    // endpoint and never blocks a Tier-1 core operation (decision #4).
    //
    // NOTE (composition gap — recorded in §4, not silently ignored): the three
    // server-side creation commands (`CreateNotification` + `NotifyRoundScored`/
    // `NotifyGroupMemberJoined`/`NotifyReactionReceived`) are complete and
    // exported by the application layer, but are NOT client-callable and so are
    // deliberately NOT wired here — they must be invoked as best-effort Tier-3
    // effects at the ScoreRound/JoinGroup/ReactToRound composition edges. That
    // trigger-edge wiring is a separate, explicit step tracked in §4; this
    // bootstrap wires only the recipient-facing read/mark surface that has an
    // HTTP route.
    final notificationRepository = PostgresNotificationRepository(connection);

    // Push delivery. A missing/unparsable service account degrades to a
    // no-op sender rather than refusing to boot: Tier-3 (ADR 0007 §2.4),
    // and a server that cannot remind is still a server that can score.
    final pushSender =
        FcmPushSender.tryParse(env['FIREBASE_SERVICE_ACCOUNT_JSON']) ??
        const NoopPushSender();
    final deviceTokenRepository = PostgresDeviceTokenRepository(connection);
    final announcementRepository = PostgresAnnouncementRepository(connection);
    // The one deferred-push queue: the exact-hit announcement and the admin
    // broadcast fill it in quiet hours, the flush sweep empties it.
    final notificationQueue = PostgresNotificationQueue(connection);

    // Admin slice (phase 11). The ONE new stored surface is the append-only
    // `admin.audit_log` (migration 0010); the user sanction toggles the
    // EXISTING `identity.users.status` (no new user table — decision §2 #1,
    // reuse over duplication). A single audit-write path (`AuditRecorder`,
    // reusing the shared `idGenerator`/`clock`) is shared by every audited
    // admin use-case, so the trail is written one way (Security ADR §2.4). The
    // support read (`ViewParticipantLedger`) reuses the same `participantReader`
    // + `ledgerRepository` already built for the Ledger slice above (decision
    // §2 #1); it is a DIFFERENT gate from `ReadParticipantLedger` (admin cross-
    // user read, itself audited — decision OPEN-A #3), never a duplicate.
    // Suspend/reinstate write identity.users through this repository, so it
    // drops the user from the per-request cache in `directory` at once.
    final userAdminRepository = UserCacheEvictingAdminRepository(
      PostgresUserAdminRepository(connection),
      onUserChanged: directory.forget,
    );
    final auditLogRepository = PostgresAuditLogRepository(connection);
    final auditRecorder = AuditRecorder(
      auditLog: auditLogRepository,
      idGenerator: idGenerator,
      clock: clock,
    );

    // Automatic fixtures/results (phase 1): football-data.org serves the
    // Premier League, Champions League, Bundesliga, La Liga and Serie A;
    // Highlightly the Roshan League, Europa League and League Cup. Off unless
    // NUKHBA_PROVIDER_SYNC (shadow|on) and at least one provider key are set;
    // a rule whose provider has no key is skipped. Results go through the same
    // RecordFixtureResult + ScoreFixture pair as the admin endpoint, under a
    // service principal; `root` is bound below.
    final highlightlyKey = (env['NUKHBA_HIGHLIGHTLY_API_KEY'] ?? '').trim();
    final footballDataKey = (env['NUKHBA_FOOTBALL_DATA_API_KEY'] ?? '').trim();
    final providers = <String, FootballDataProvider>{
      if (highlightlyKey.isNotEmpty)
        highlightlySource: HighlightlyFootballDataProvider(
          apiKey: highlightlyKey,
        ),
      if (footballDataKey.isNotEmpty)
        footballDataSource: FootballDataOrgProvider(apiKey: footballDataKey),
    };
    final providerSyncMode = providers.isEmpty
        ? ProviderSyncMode.off
        : ProviderSyncMode.parse(env['NUKHBA_PROVIDER_SYNC']);
    // Running scores for the fixtures feed (display only), refreshed by the
    // provider scheduler; empty until a poll fills it.
    final liveScoreBoard = InMemoryLiveScoreBoard();
    RefreshLiveScores? refreshLiveScores;
    late final CompositionRoot root;
    SyncProviderFixtures? syncProviderFixtures;
    SyncProviderResults? syncProviderResults;
    if (providerSyncMode != ProviderSyncMode.off) {
      final syncStore = PostgresProviderSyncStore(connection);
      final syncLeagues = PostgresLeagueRepository(connection);
      const systemPrincipal = AuthenticatedUser(
        userId: UserId(_providerSyncUserId),
        role: PlatformRole.service,
      );
      syncProviderFixtures = SyncProviderFixtures(
        providers: providers,
        store: syncStore,
        leagueRepository: syncLeagues,
        teamRepository: teamRepository,
        competitionRepository: competitionRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
        fixturePredictionRepository: fixturePredictionRepository,
        idGenerator: idGenerator,
        rules: phaseOneRules,
        // Highlightly allows 100 requests a day and they are wanted for
        // results; two days of schedules still sees every day twice.
        daysBySource: const <String, int>{highlightlySource: 2},
      );
      refreshLiveScores = RefreshLiveScores(
        providers: providers,
        store: syncStore,
        leagueRepository: syncLeagues,
        rules: phaseOneRules,
        board: liveScoreBoard,
        // Highlightly's 100 daily requests are kept for results.
        liveSources: const {footballDataSource},
      );
      syncProviderResults = SyncProviderResults(
        providers: providers,
        store: syncStore,
        leagueRepository: syncLeagues,
        rules: phaseOneRules,
        recorder:
            ({
              required String fixtureId,
              required int homeGoals,
              required int awayGoals,
            }) async {
              final recorded = await root.recordFixtureResult(
                principal: systemPrincipal,
                fixtureId: fixtureId,
                homeGoals: homeGoals,
                awayGoals: awayGoals,
              );
              if (recorded is Err<FixtureResult>) {
                return Result.err(recorded.error);
              }
              final scored = await root.scoreFixture(
                principal: systemPrincipal,
                fixtureId: fixtureId,
              );
              if (scored is Err<List<ParticipantFixtureScore>>) {
                return Result.err(scored.error);
              }
              // Third step, the one the admin flow also runs:
              // ScoreFixture only fills scoring.fixture_scores, and a
              // leaderboard reads the ledger. Without this the sync
              // recorded results that stood at zero points for
              // everyone. PostFixtureToLedger is idempotent.
              final posted = await root.postFixtureToLedger(
                principal: systemPrincipal,
                fixtureId: fixtureId,
              );
              if (posted is Err<List<FixturePointEntry>>) {
                return Result.err(posted.error);
              }
              return const Result.ok(null);
            },
      );
    }

    return root = CompositionRoot._(
      connection: connection,
      jwksClient: jwksClient,
      checkHealth: checkHealth,
      getLatestBuild: getLatestBuild,
      authenticateRequest: AuthenticateRequest(verifier, directory: directory),
      getCurrentUser: GetCurrentUser(directory),
      enrolInOpenSeasons: EnrolInOpenSeasons(
        competitionRepository: competitionRepository,
        idGenerator: idGenerator,
      ),
      login: login,
      register: register,
      requestPasswordReset: requestPasswordReset,
      updatePassword: updatePassword,
      updateDisplayName: UpdateDisplayName(userDirectory: directory),
      updateTimeZoneOffset: UpdateTimeZoneOffset(userDirectory: directory),
      getMyStreak: GetMyStreak(
        streaks: PostgresStreakRepository(connection),
        clock: clock,
      ),
      getMyInsights: GetMyInsights(
        outcomes: PostgresPredictionOutcomeReader(connection),
        clock: clock,
      ),
      getMyDailyChallenge: GetMyDailyChallenge(
        competitionRepository: competitionRepository,
        dailyChallenges: PostgresDailyChallengeRepository(connection),
        clock: clock,
      ),
      getMyWeeklyLeague: GetMyWeeklyLeague(
        join: JoinWeeklyLeague(
          leagues: PostgresWeeklyLeagueRepository(connection),
          idGenerator: idGenerator,
          clock: clock,
        ),
        standings: PostgresWeeklyLeagueStandingsReader(connection),
        profiles: PostgresWeeklyLeagueProfileReader(connection),
        notices: PostgresOvertakenRepository(connection),
      ),
      getMyBadges: GetMyBadges(badges: PostgresPlayerBadgeReader(connection)),
      getMyNotificationPreferences: GetMyNotificationPreferences(
        preferences: PostgresNotificationPreferenceRepository(connection),
      ),
      updateMyNotificationPreferences: UpdateMyNotificationPreferences(
        preferences: PostgresNotificationPreferenceRepository(connection),
      ),
      getMyFavoriteTeams: GetMyFavoriteTeams(
        favorites: PostgresFavoriteTeamRepository(connection),
      ),
      setMyFavoriteTeams: SetMyFavoriteTeams(
        favorites: PostgresFavoriteTeamRepository(connection),
      ),
      resolveExperimentVariant: ResolveExperimentVariant(
        experiments: PostgresExperimentRepository(connection),
      ),
      setAvatar: SetAvatar(userDirectory: directory),
      clearAvatar: ClearAvatar(userDirectory: directory),
      readAvatar: ReadAvatar(userDirectory: directory),
      sendPredictionReminders: SendPredictionReminders(
        reminders: PostgresPredictionReminderRepository(connection),
        sender: pushSender,
        preferences: PostgresNotificationPreferenceRepository(connection),
      ),
      sendPreMatchReminders: SendPreMatchReminders(
        reminders: PostgresPreMatchReminderRepository(connection),
        budget: PostgresPredictionReminderRepository(connection),
        sender: pushSender,
      ),
      sendStreakSavers: SendStreakSavers(
        savers: PostgresStreakSaverRepository(connection),
        streaks: PostgresStreakRepository(connection),
        budget: PostgresPredictionReminderRepository(connection),
        sender: pushSender,
      ),
      recordPushOpen: RecordPushOpen(
        opens: PostgresPushOpenRepository(connection),
        clock: clock,
      ),
      sendOvertakenPushes: SendOvertakenPushes(
        overtaken: PostgresOvertakenRepository(connection),
        standings: PostgresWeeklyLeagueStandingsReader(connection),
        profiles: PostgresWeeklyLeagueProfileReader(connection),
        budget: PostgresPredictionReminderRepository(connection),
        sender: pushSender,
      ),
      flushNotificationQueue: FlushNotificationQueue(
        queue: notificationQueue,
        sender: pushSender,
      ),
      ensureUpcomingMonthlySeasons: EnsureUpcomingMonthlySeasons(
        repository: competitionRepository,
        idGenerator: idGenerator,
      ),
      settleMatchDays: SettleMatchDays(
        store: PostgresMatchDaySettlementStore(connection),
      ),
      closeWeeklyLeague: CloseWeeklyLeague(
        closures: PostgresWeeklyLeagueClosureStore(connection),
        standings: PostgresWeeklyLeagueStandingsReader(connection),
        events: PostgresGamificationEventSink(connection),
        idGenerator: idGenerator,
      ),
      evaluateBadges: EvaluateBadges(
        progress: PostgresBadgeProgressReader(connection),
        events: PostgresGamificationEventSink(connection),
        idGenerator: idGenerator,
      ),
      providerSyncMode: providerSyncMode,
      syncProviderFixtures: syncProviderFixtures,
      syncProviderResults: syncProviderResults,
      liveScoreBoard: liveScoreBoard,
      refreshLiveScores: refreshLiveScores,
      registerDeviceToken: RegisterDeviceToken(
        deviceTokens: deviceTokenRepository,
      ),
      createCompetition: CreateCompetition(
        repository: competitionRepository,
        idGenerator: idGenerator,
      ),
      startSeason: StartSeason(
        repository: competitionRepository,
        idGenerator: idGenerator,
      ),
      linkFixtureToRound: LinkFixtureToRound(competitionRepository),
      removeFixtureFromRound: RemoveFixtureFromRound(
        competitionRepository: competitionRepository,
        fixtureResultRepository: fixtureResultRepository,
      ),
      joinCompetition: JoinCompetition(
        repository: competitionRepository,
        idGenerator: idGenerator,
        clock: clock,
      ),
      // Read-only Competition-browse query use-cases (BLOCKER FA-1): every one
      // reuses the same `competitionRepository` as the write commands (its new
      // list reads are strictly additive — DEFECT FA-2 closed). No side effect,
      // no points, no new infrastructure.
      getCompetition: GetCompetition(repository: competitionRepository),
      getRound: GetRound(repository: competitionRepository),
      listCompetitions: ListCompetitions(repository: competitionRepository),
      listMonthlySeasons: ListMonthlySeasons(repository: competitionRepository),
      listCompetitionSeasons: ListCompetitionSeasons(
        repository: competitionRepository,
      ),
      getCurrentSeason: GetCurrentSeason(
        repository: competitionRepository,
        clock: clock,
      ),
      listSeasonRounds: ListSeasonRounds(repository: competitionRepository),
      browseRoundFixtures: BrowseRoundFixtures(
        competitionRepository: competitionRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
      ),
      browseSeasonFixtures: BrowseSeasonFixtures(
        fixturePredictionRepository: fixturePredictionRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
      ),
      linkFixtureToSeason: LinkFixtureToSeason(
        competitionRepository: competitionRepository,
        fixturePredictionRepository: fixturePredictionRepository,
      ),
      removeFixtureFromSeason: RemoveFixtureFromSeason(
        competitionRepository: competitionRepository,
        fixturePredictionRepository: fixturePredictionRepository,
        fixtureResultRepository: fixtureResultRepository,
      ),
      listCurrentMonthFixtures: ListCurrentMonthFixtures(
        competitionRepository: competitionRepository,
        fixturePredictionRepository: fixturePredictionRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
        clock: clock,
        predictionTallyReader: fixturePredictionTallyReader,
      ),
      submitPrediction: SubmitPrediction(
        predictionRepository: predictionRepository,
        competitionRepository: competitionRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
        idGenerator: idGenerator,
        clock: clock,
      ),
      submitFixturePrediction: SubmitFixturePrediction(
        fixturePredictionRepository: fixturePredictionRepository,
        competitionRepository: competitionRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
        idGenerator: idGenerator,
        clock: clock,
        gamificationEventSink: PostgresGamificationEventSink(connection),
        dailyChallengeRepository: PostgresDailyChallengeRepository(connection),
        awardStreakBonus: AwardStreakBonus(
          getMyStreak: GetMyStreak(
            streaks: PostgresStreakRepository(connection),
            clock: clock,
          ),
          fixtureLedgerRepository: fixtureLedgerRepository,
          idGenerator: idGenerator,
        ),
      ),
      getMyPrediction: GetMyPrediction(
        predictionRepository: predictionRepository,
        competitionRepository: competitionRepository,
      ),
      listRoundPredictions: ListRoundPredictions(
        predictionRepository: predictionRepository,
        competitionRepository: competitionRepository,
      ),
      recordFixtureResult: RecordFixtureResult(
        resultRepository: fixtureResultRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
        clock: clock,
      ),
      registerFixtureSchedule: RegisterFixtureSchedule(
        repository: fixtureScheduleRepository,
        idGenerator: idGenerator,
      ),
      correctFixtureSchedule: CorrectFixtureSchedule(
        fixtureScheduleRepository,
        auditRecorder: auditRecorder,
        clock: clock,
      ),
      scoreFixture: ScoreFixture(
        fixturePredictionRepository: fixturePredictionRepository,
        resultRepository: fixtureResultRepository,
        scoreRepository: fixtureScoreRepository,
        rulesetProvider: rulesetProvider,
        // The exact-hit announcement rides the same proven transport as the
        // daily reminder: same FCM sender, same device_tokens table. With no
        // service account configured `pushSender` is the no-op, so scoring
        // still works and simply says nothing.
        winnerNotifier: NotifyFixtureWinners(
          announcements: PostgresScoreAnnouncementRepository(connection),
          sender: pushSender,
          create: CreateNotification(
            notifications: notificationRepository,
            idGenerator: idGenerator,
            clock: clock,
          ),
          queue: notificationQueue,
          idGenerator: idGenerator,
          clock: clock,
        ),
      ),
      adminGetParticipantDisplayNames: AdminGetParticipantDisplayNames(
        participantReader: participantReader,
      ),
      readParticipantLedger: ReadParticipantLedger(
        participantReader: participantReader,
        ledgerRepository: ledgerRepository,
      ),
      getSeasonLeaderboard: GetSeasonLeaderboard(
        leaderboardRepository: leaderboardRepository,
        competitionRepository: competitionRepository,
      ),
      listMySeasonRecords: ListMySeasonRecords(
        leaderboardRepository: leaderboardRepository,
      ),
      getSeasonFixtureLeaderboard: GetSeasonFixtureLeaderboard(
        competitionRepository: competitionRepository,
        fixturePredictionRepository: fixturePredictionRepository,
        fixtureTotalsReader: CachedFixtureTotalsReader(
          PostgresFixtureTotalsReader(connection),
        ),
        fixtureScheduleRepository: fixtureScheduleRepository,
        participantReader: participantReader, // already built (Ledger slice)
        rankSnapshotReader: PostgresRankSnapshotReader(connection),
      ),
      getFixtureScores: GetFixtureScores(
        competitionRepository: competitionRepository,
        fixturePredictionRepository: fixturePredictionRepository,
        fixtureScoreRepository: fixtureScoreRepository,
      ),
      getFixturePredictionDistribution: GetFixturePredictionDistribution(
        fixturePredictionRepository: fixturePredictionRepository,
      ),
      adminGetFixtureScores: AdminGetFixtureScores(
        fixtureScoreRepository: fixtureScoreRepository,
      ),
      getHallOfFame: GetHallOfFame(
        leaderboardRepository: leaderboardRepository,
      ),
      getSportingSeasonLeaderboard: GetSportingSeasonLeaderboard(
        reader: CachedSportingSeasonStandingsReader(
          PostgresSportingSeasonStandingsReader(connection),
        ),
        clock: clock,
      ),
      createGroup: CreateGroup(
        repository: groupRepository,
        idGenerator: idGenerator,
        inviteCodeGenerator: inviteCodeGenerator,
        clock: clock,
      ),
      getGroup: GetGroup(repository: groupRepository),
      joinGroupByInvite: JoinGroupByInvite(
        repository: groupRepository,
        idGenerator: idGenerator,
        clock: clock,
      ),
      renameGroup: RenameGroup(repository: groupRepository),
      regenerateInvite: RegenerateInvite(
        repository: groupRepository,
        inviteCodeGenerator: inviteCodeGenerator,
      ),
      listGroupMembers: ListGroupMembers(repository: groupRepository),
      listMyGroups: ListMyGroups(repository: groupRepository),
      getGroupLeaderboard: GetGroupLeaderboard(
        repository: groupRepository,
        standingsReader: groupRepository,
      ),
      reactToRound: ReactToRound(
        reactions: reactionRepository,
        groups: groupRepository,
        idGenerator: idGenerator,
        clock: clock,
      ),
      removeReaction: RemoveReaction(
        reactions: reactionRepository,
        groups: groupRepository,
      ),
      listRoundReactions: ListRoundReactions(
        reactions: reactionRepository,
        groups: groupRepository,
      ),
      postFixtureToLedger: PostFixtureToLedger(
        fixtureScoreRepository: fixtureScoreRepository,
        fixtureLedgerRepository: fixtureLedgerRepository,
        idGenerator: idGenerator,
        clock: clock,
      ),
      reactToFixture: ReactToFixture(
        reactions: fixtureReactionRepository,
        groups: groupRepository,
        idGenerator: idGenerator,
        clock: clock,
      ),
      removeFixtureReaction: RemoveFixtureReaction(
        reactions: fixtureReactionRepository,
        groups: groupRepository,
      ),
      listFixtureReactions: ListFixtureReactions(
        reactions: fixtureReactionRepository,
        groups: groupRepository,
      ),
      getGroupActivityFeed: GetGroupActivityFeed(
        feed: activityFeedReader,
        groups: groupRepository,
      ),
      listMyNotifications: ListMyNotifications(
        notifications: notificationRepository,
      ),
      listMyNotificationFeed: ListMyNotificationFeed(
        list: ListMyNotifications(notifications: notificationRepository),
        announcements: announcementRepository,
      ),
      publishAnnouncement: PublishAnnouncement(
        announcements: announcementRepository,
        create: CreateNotification(
          notifications: notificationRepository,
          idGenerator: idGenerator,
          clock: clock,
        ),
        // Same transport as the reminder and the exact-hit announcement: with
        // no service account configured this is the no-op sender, so the
        // broadcast still lands in every inbox and simply rings nothing.
        sender: pushSender,
        idGenerator: idGenerator,
        clock: clock,
        queue: notificationQueue,
      ),
      getUnreadCount: GetUnreadCount(notifications: notificationRepository),
      markNotificationRead: MarkNotificationRead(
        notifications: notificationRepository,
        clock: clock,
      ),
      suspendUser: SuspendUser(
        users: userAdminRepository,
        auditRecorder: auditRecorder,
      ),
      reinstateUser: ReinstateUser(
        users: userAdminRepository,
        auditRecorder: auditRecorder,
      ),
      listUsers: ListUsers(users: userAdminRepository),
      listAuditLog: ListAuditLog(auditLog: auditLogRepository),
      viewParticipantLedger: ViewParticipantLedger(
        participantReader: participantReader, // already built (Ledger slice)
        ledgerRepository: ledgerRepository, // already built (Ledger slice)
        auditRecorder: auditRecorder,
      ),
      adminListRoundPredictions: AdminListRoundPredictions(
        competitionRepository: competitionRepository, // already built
        predictionRepository: predictionRepository, // already built
        auditRecorder: auditRecorder,
      ),
      adminListFixturePredictions: AdminListFixturePredictions(
        fixturePredictionRepository:
            fixturePredictionRepository, // already built
        auditRecorder: auditRecorder,
      ),
      adminGetUserFixturePredictions: AdminGetUserFixturePredictions(
        userAdminRepository: userAdminRepository,
        fixturePredictionRepository: fixturePredictionRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
        fixtureResultRepository: fixtureResultRepository,
        fixtureScoreRepository: fixtureScoreRepository,
        auditRecorder: auditRecorder,
      ),
      listMyFixturePredictions: ListMyFixturePredictions(
        fixturePredictionRepository:
            fixturePredictionRepository, // already built
      ),
      listMyActiveSeasons: ListMyActiveSeasons(
        competitionRepository: competitionRepository,
        clock: clock,
      ),
      listTeams: ListTeams(repository: teamRepository),
      listLeagues: ListLeagues(
        repository: PostgresLeagueRepository(connection),
      ),
    );
  }

  /// Unwraps a config [Result], throwing a fatal [StateError] on failure so the
  /// process refuses to start with invalid configuration (fail-fast).
  static T _require<T>(Result<T> result, String what) => switch (result) {
    Ok<T>(:final value) => value,
    Err<T>(:final error) => throw StateError('Invalid $what: $error'),
  };

  /// Graceful shutdown hook. A no-op for test roots, which own no resources.
  Future<void> dispose() async {
    _jwksClient?.close();
    await _connection?.close();
  }

  /// Cached bootstrap future for the running process.
  ///
  /// We cache the *Future*, not the resolved instance, so that concurrent
  /// callers awaiting [instance] before the first bootstrap completes all
  /// share the single in-flight bootstrap rather than triggering a race that
  /// opens multiple connection pools.
  static Future<CompositionRoot>? _instanceFuture;

  /// Returns the process-wide root, building it once on first access.
  ///
  /// A *failed* bootstrap is deliberately not kept: `??=` cached the rejected
  /// Future, so one bad moment at startup (the pooler briefly unreachable, a
  /// slow JWKS warm-up) poisoned every later request with the same error and
  /// nothing short of a container restart could clear it. Concurrent callers
  /// still share one in-flight attempt; only a failure reopens the door.
  static Future<CompositionRoot> instance() {
    final cached = _instanceFuture;
    if (cached != null) return cached;
    late final Future<CompositionRoot> attempt;
    attempt = bootstrap(Platform.environment).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (identical(_instanceFuture, attempt)) {
        _instanceFuture = null;
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
    _instanceFuture = attempt;
    return attempt;
  }

  /// Resets the cached root. Intended for tests and controlled shutdown; not
  /// used on the request hot path.
  static Future<void> reset() async {
    final existing = _instanceFuture;
    _instanceFuture = null;
    if (existing != null) {
      final root = await existing;
      await root.dispose();
    }
  }
}

/// Backs an "absent" [CheckHealth] in [CompositionRoot.forTesting]: throws if a
/// test reaches a health slice it never wired.
final class _UnwiredHealthRepository implements HealthRepository {
  @override
  Future<Result<bool>> pingDatabase() =>
      throw StateError('CheckHealth was not wired into this test root');
}

/// Backs an "absent" [GetLatestBuild] in [CompositionRoot.forTesting]: throws
/// if a test reaches the update-check slice it never wired.
final class _UnwiredBuildInfoRepository implements BuildInfoRepository {
  @override
  Future<Result<LatestBuild>> fetchLatest() =>
      throw StateError('GetLatestBuild was not wired into this test root');
}

/// Backs an "absent" [GetMyInsights]: throws if a test reaches the insights
/// slice it never wired.
final class _UnwiredPredictionOutcomeReader implements PredictionOutcomeReader {
  static Never _unwired() =>
      throw StateError('GetMyInsights was not wired into this test root');

  @override
  Future<Result<List<PredictionOutcome>>> outcomesOf({
    required UserId userId,
    required DateTime from,
    required DateTime to,
  }) => _unwired();

  @override
  Future<Result<AccuracyTally>> communityTally({
    required DateTime from,
    required DateTime to,
  }) => _unwired();
}

/// Backs an "absent" [GetMyStreak]: throws if a test reaches the streak slice
/// it never wired.
final class _UnwiredStreakRepository implements StreakRepository {
  @override
  Future<Result<List<MatchDayCompletion>>> completionCalendar({
    required UserId userId,
    required DateTime upToDay,
    required int limitDays,
  }) => throw StateError('GetMyStreak was not wired into this test root');
}

/// Backs an "absent" [GetMyDailyChallenge]: throws if a test reaches the
/// daily-challenge slice it never wired.
final class _UnwiredDailyChallengeRepository
    implements DailyChallengeRepository {
  @override
  Future<Result<DailyChallengeProgress>> progressOn({
    required SeasonId seasonId,
    required ParticipantId participantId,
    required DateTime day,
  }) =>
      throw StateError('GetMyDailyChallenge was not wired into this test root');
}

/// Backs an "absent" [GetMyWeeklyLeague]: throws if a test reaches the
/// weekly-league slice it never wired.
final class _UnwiredWeeklyLeagueRepository implements WeeklyLeagueRepository {
  @override
  Future<Result<WeeklyLeagueSeat?>> seatFor({
    required UserId userId,
    required DateTime weekStart,
  }) => throw StateError('GetMyWeeklyLeague was not wired into this test root');

  @override
  Future<Result<WeeklyLeagueSeat>> place({
    required UserId userId,
    required DateTime weekStart,
    required WeeklyLeagueTier tier,
    required WeeklyLeagueId newLeagueId,
    required int capacity,
  }) => throw StateError('GetMyWeeklyLeague was not wired into this test root');

  @override
  Future<Result<WeeklyLeagueFinish?>> lastFinishOf({required UserId userId}) =>
      throw StateError('GetMyWeeklyLeague was not wired into this test root');
}

/// Backs an "absent" [GetMyWeeklyLeague]: throws if a test reaches the
/// weekly-league standings it never wired.
final class _UnwiredWeeklyLeagueStandingsReader
    implements WeeklyLeagueStandingsReader {
  @override
  Future<Result<List<WeeklyLeagueEntry>>> entriesOf({
    required WeeklyLeagueId leagueId,
    required DateTime weekStart,
  }) => throw StateError('GetMyWeeklyLeague was not wired into this test root');
}

/// Backs an "absent" [GetMyWeeklyLeague]: throws if a test reaches the
/// weekly-league profiles it never wired.
final class _UnwiredWeeklyLeagueProfileReader
    implements WeeklyLeagueProfileReader {
  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) => throw StateError('GetMyWeeklyLeague was not wired into this test root');
}

/// Backs an "absent" [GetMyBadges]: throws if a test reaches the badge wall
/// it never wired.
final class _UnwiredPlayerBadgeReader implements PlayerBadgeReader {
  @override
  Future<Result<PlayerBadgeRecord>> recordOf(UserId userId) =>
      throw StateError('GetMyBadges was not wired into this test root');
}

/// Backs an "absent" [ResolveExperimentVariant]: throws if a test reaches
/// the experiment slice it never wired.
final class _UnwiredExperimentRepository implements ExperimentRepository {
  @override
  Future<Result<bool>> isFlagEnabled(String flagKey) => throw StateError(
    'ResolveExperimentVariant was not wired into this test root',
  );

  @override
  Future<Result<String?>> readAssignment({
    required UserId userId,
    required String flagKey,
  }) => throw StateError(
    'ResolveExperimentVariant was not wired into this test root',
  );

  @override
  Future<Result<String>> assign({
    required UserId userId,
    required String flagKey,
    required String variant,
  }) => throw StateError(
    'ResolveExperimentVariant was not wired into this test root',
  );
}

final class _UnwiredMatchDaySettlementStore implements MatchDaySettlementStore {
  @override
  Future<Result<DateTime?>> lastSettledDay() =>
      throw StateError('SettleMatchDays was not wired into this test root');

  @override
  Future<Result<DateTime?>> firstFixtureDay() =>
      throw StateError('SettleMatchDays was not wired into this test root');

  @override
  Future<Result<int>> settle({
    required DateTime from,
    required DateTime through,
  }) => throw StateError('SettleMatchDays was not wired into this test root');
}

/// Backs an "absent" [CloseWeeklyLeague]: throws if a test reaches the
/// weekly-league closing slice it never wired.
final class _UnwiredWeeklyLeagueClosureStore
    implements WeeklyLeagueClosureStore {
  @override
  Future<Result<DateTime?>> nextUnclosedWeek() =>
      throw StateError('CloseWeeklyLeague was not wired into this test root');

  @override
  Future<Result<List<WeeklyLeagueGroupRef>>> groupsOf(DateTime weekStart) =>
      throw StateError('CloseWeeklyLeague was not wired into this test root');

  @override
  Future<Result<void>> markClosed({
    required DateTime weekStart,
    required int memberCount,
  }) => throw StateError('CloseWeeklyLeague was not wired into this test root');
}

/// Backs an "absent" [CloseWeeklyLeague]: throws if a test reaches the event
/// stream it never wired.
final class _UnwiredGamificationEventSink implements GamificationEventSink {
  @override
  Future<Result<void>> record(GamificationEvent event) =>
      throw StateError('CloseWeeklyLeague was not wired into this test root');
}

/// Backs an "absent" [EvaluateBadges]: throws if a test reaches the badge
/// slice it never wired.
final class _UnwiredBadgeProgressReader implements BadgeProgressReader {
  @override
  Future<Result<List<UserBadgeStanding>>> readAll() =>
      throw StateError('EvaluateBadges was not wired into this test root');
}

/// Backs an "absent" [AuthenticateRequest]: throws if a test reaches the auth
/// slice it never wired.
final class _UnwiredTokenVerifier implements TokenVerifier {
  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) =>
      throw StateError('AuthenticateRequest was not wired into this test root');
}

/// Backs an "absent" [GetCurrentUser]: throws if a test reaches the directory
/// slice it never wired.
final class _UnwiredUserDirectory implements UserDirectory {
  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) =>
      throw StateError('GetCurrentUser was not wired into this test root');

  @override
  @override
  Future<Result<User>> updateDisplayName(UserId userId, String displayName) =>
      throw StateError('UpdateDisplayName was not wired into this test root');

  @override
  Future<Result<void>> updateUtcOffsetMinutes(UserId userId, int minutes) =>
      throw StateError(
        'UpdateTimeZoneOffset was not wired into this test root',
      );

  @override
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime) =>
      throw StateError('SetAvatar was not wired into this test root');

  @override
  Future<Result<User>> clearAvatar(UserId userId) =>
      throw StateError('ClearAvatar was not wired into this test root');

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) =>
      throw StateError('ReadAvatar was not wired into this test root');

  @override
  Future<Result<User?>> findUser(UserId id) {
    throw StateError('GetCurrentUser was not wired into this test root');
  }
}

/// Backs every "absent" competition use-case: any method throws so a test that
/// reaches an unwired competition slice fails loudly instead of touching a
/// real database.
final class _UnwiredCompetitionRepository implements CompetitionRepository {
  static Never _unwired() =>
      throw StateError('A competition use-case was not wired into this root');

  // Deliberately NOT _unwired(). Every other method here throws so a test
  // that reaches an unwired competition slice fails loudly. This one is
  // different: automatic enrolment runs on GET /me, so a root that wires only
  // the identity slice would otherwise explode on a path it never asked for.
  // "Not wired" means "no contest is running" - the same answer a real
  // repository gives before the month's fixtures are filed.
  @override
  Future<Result<List<CompetitionSeason>>> listOpenSeasonsWithFixtures(
    DateTime at,
  ) async => const Result.ok(<CompetitionSeason>[]);

  @override
  Future<Result<List<CompetitionSeason>>> listMonthlySeasons() => _unwired();

  @override
  Future<Result<void>> saveCompetition(Competition competition) => _unwired();

  @override
  Future<Result<Competition>> findCompetition(CompetitionId id) => _unwired();

  @override
  Future<Result<void>> saveSeason(CompetitionSeason season) => _unwired();

  @override
  Future<Result<CompetitionSeason>> findSeason(SeasonId id) => _unwired();

  @override
  Future<Result<CompetitionSeason?>> findCurrentSeason({
    required CompetitionId competitionId,
    required DateTime nowUtc,
  }) => _unwired();

  @override
  Future<Result<void>> saveRound(Round round) => _unwired();

  @override
  Future<Result<Round>> findRound(RoundId id) => _unwired();

  @override
  Future<Result<void>> updateRoundStatus(
    Round round,
    RoundStatus expectedPriorStatus,
  ) => _unwired();

  @override
  Future<Result<void>> saveRoundFixture(RoundFixture link) => _unwired();

  @override
  Future<Result<bool>> deleteRoundFixture({
    required RoundId roundId,
    required FixtureRef fixture,
  }) => _unwired();

  @override
  Future<Result<void>> saveParticipant(Participant participant) => _unwired();

  @override
  Future<Result<Participant?>> findParticipant(
    SeasonId seasonId,
    UserId userId,
  ) => _unwired();

  @override
  Future<Result<List<Competition>>> listCompetitions() => _unwired();

  @override
  Future<Result<List<CompetitionSeason>>> listCompetitionSeasons(
    CompetitionId competitionId,
  ) => _unwired();

  @override
  Future<Result<List<Round>>> listSeasonRounds(SeasonId seasonId) => _unwired();

  @override
  Future<Result<List<RoundFixture>>> listRoundFixtures(RoundId roundId) =>
      _unwired();

  @override
  Future<Result<List<RoundId>>> listRoundsByFixture(FixtureRef fixture) =>
      _unwired();

  @override
  Future<Result<List<ParticipantSeasonFeedEntry>>>
  listActiveParticipantSeasons({
    required UserId userId,
    required DateTime nowUtc,
  }) => _unwired();
}

/// Backs an "absent" ruleset-dependent use-case's ruleset provider.
final class _UnwiredRulesetProvider implements RulesetProvider {
  @override
  Future<Result<RulesetSnapshot>> currentSnapshotFor(FormatType format) =>
      throw StateError(
        'A ruleset-dependent use-case was not wired into this root',
      );
}

/// Backs "absent" competition use-cases' id generator.
final class _UnwiredIdGenerator implements IdGenerator {
  @override
  String newUuid() =>
      throw StateError('A competition use-case was not wired into this root');
}

final class _UnwiredFixtureTotalsReader implements FixtureTotalsReader {
  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) => throw StateError(
    'GetSeasonFixtureLeaderboard was not wired into this root',
  );
}

final class _UnwiredSportingSeasonStandingsReader
    implements SportingSeasonStandingsReader {
  @override
  Future<Result<List<SportingSeasonStanding>>> standings(
    SportingSeason season,
  ) => throw StateError(
    'GetSportingSeasonLeaderboard was not wired into this root',
  );
}

/// Backs "absent" competition use-cases' clock.
final class _UnwiredClock implements Clock {
  @override
  DateTime nowUtc() =>
      throw StateError('JoinCompetition was not wired into this root');
}

/// Backs every "absent" prediction use-case: any method throws so a test that
/// reaches an unwired prediction slice fails loudly instead of touching a real
/// database.
final class _UnwiredPredictionRepository implements PredictionRepository {
  static Never _unwired() =>
      throw StateError('A prediction use-case was not wired into this root');

  @override
  Future<Result<PredictionView?>> findByRoundAndParticipant(
    RoundId roundId,
    ParticipantId participantId,
  ) => _unwired();

  @override
  Future<Result<void>> save(Prediction prediction, DateTime submittedAt) =>
      _unwired();

  @override
  Future<Result<void>> update(Prediction prediction, DateTime submittedAt) =>
      _unwired();

  @override
  Future<Result<List<PredictionView>>> listByRound(RoundId roundId) =>
      _unwired();

  @override
  Future<Result<List<RoundFixture>>> listRoundFixtures(RoundId roundId) =>
      _unwired();
}

/// Backs the "absent" fixture-prediction use-case's port (Axiom 4 Amendment):
/// any method throws so a test that reaches an unwired slice fails loudly
/// instead of touching a real database.
final class _UnwiredFixturePredictionRepository
    implements FixturePredictionRepository {
  static Never _unwired() => throw StateError(
    'A fixture-prediction use-case was not wired into this root',
  );

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) => _unwired();

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) => _unwired();

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) => _unwired();

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) => _unwired();

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) => _unwired();

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) => _unwired();

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) => _unwired();

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) => _unwired();

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) =>
      _unwired();

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) =>
      _unwired();
}

/// Backs every "absent" scoring use-case's fixture-result port: any method
/// throws so a test that reaches an unwired scoring slice fails loudly instead
/// of touching a real database.
final class _UnwiredFixtureResultRepository implements FixtureResultRepository {
  static Never _unwired() =>
      throw StateError('A scoring use-case was not wired into this root');

  @override
  Future<Result<void>> upsert(FixtureResult result, DateTime recordedAt) =>
      _unwired();

  @override
  Future<Result<FixtureResult?>> findByFixture(FixtureRef fixture) =>
      _unwired();

  @override
  Future<Result<List<FixtureResult>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) => _unwired();
}

final class _UnwiredFixtureScheduleRepository
    implements FixtureScheduleRepository {
  static Never _unwired() => throw StateError(
    'A fixture-identity use-case was not wired into this root',
  );

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) => _unwired();

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) =>
      _unwired();

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) => _unwired();
}

/// Backs the "absent" fixture-scoring use-case's port (Axiom 4 Amendment): any
/// method throws so a test that reaches an unwired slice fails loudly instead
/// of touching a real database.
final class _UnwiredFixtureScoreRepository implements FixtureScoreRepository {
  static Never _unwired() => throw StateError(
    'A fixture-scoring use-case was not wired into this root',
  );

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) => _unwired();

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) => _unwired();

  @override
  Future<Result<List<ParticipantFixtureScore>>> listBySeasonFixtures(
    List<FixtureRef> fixtures,
  ) => _unwired();
}

/// Backs every "absent" ledger use-case's ledger port: any method throws so a
/// test that reaches an unwired ledger slice fails loudly instead of touching a
/// real database.
final class _UnwiredLedgerRepository implements LedgerRepository {
  static Never _unwired() =>
      throw StateError('A ledger use-case was not wired into this root');

  @override
  Future<Result<List<PointEntry>>> appendEntries(List<PointEntry> entries) =>
      _unwired();

  @override
  Future<Result<List<PointEntry>>> listEntries(ParticipantId participantId) =>
      _unwired();

  @override
  Future<Result<LedgerBalance>> balanceFor(ParticipantId participantId) =>
      _unwired();
}

/// Backs every "absent" Admin Panel user-sanction use-case
/// (`SuspendUser`/`ReinstateUser`): any method throws so a test that reaches an
/// unwired admin slice fails loudly instead of touching a real database.
final class _UnwiredUserAdminRepository implements UserAdminRepository {
  static Never _unwired() =>
      throw StateError('An admin use-case was not wired into this root');

  @override
  Future<Result<User?>> findUserById(UserId id) => _unwired();

  @override
  Future<Result<User>> updateUser(User user) => _unwired();

  @override
  Future<Result<List<User>>> listUsers({String? search, required int limit}) =>
      _unwired();
}

/// Backs the "absent" audit trail behind every unwired admin use-case: any
/// method throws so a test that reaches an unwired audit path fails loudly
/// instead of silently dropping an audit record.
final class _UnwiredAuditLogRepository implements AuditLogRepository {
  static Never _unwired() =>
      throw StateError('An admin use-case was not wired into this root');

  @override
  Future<Result<AuditEntry>> append(AuditEntry entry) => _unwired();

  @override
  Future<Result<List<AuditEntry>>> list({required int limit}) => _unwired();
}

/// Backs an "absent" [ReadParticipantLedger]'s participant reader: throws so a
/// test that reaches an unwired ledger read slice fails loudly.
/// Backs an unwired [RankSnapshotReader] with "no capture has run yet" -- the
/// same answer a real reader gives on a season's first day, and the reason
/// this one does not throw.
final class _EmptyRankSnapshotReader implements RankSnapshotReader {
  @override
  Future<Result<Map<String, int>>> latestRanks(SeasonId seasonId) async =>
      const Result.ok(<String, int>{});
}

final class _UnwiredParticipantReader implements ParticipantReader {
  @override
  Future<Result<Participant?>> findParticipantById(ParticipantId id) =>
      throw StateError('A ledger use-case was not wired into this root');

  @override
  Future<Result<Map<String, String>>> findDisplayNames(
    List<ParticipantId> ids,
  ) => throw StateError('A ledger use-case was not wired into this root');

  @override
  Future<Result<Map<String, ParticipantAvatarRef>>> findAvatarRefs(
    List<ParticipantId> ids,
  ) => throw StateError('A ledger use-case was not wired into this root');
}

/// Backs an "absent" [ListTeams]: throws if a test reaches the Football Data
/// team-catalog slice it never wired.
final class _UnwiredLeagueRepository implements LeagueRepository {
  @override
  Future<Result<List<League>>> listAll() =>
      throw StateError('ListLeagues was not wired into this test root');
}

final class _UnwiredTeamRepository implements TeamRepository {
  @override
  Future<Result<List<Team>>> listAll() =>
      throw StateError('ListTeams was not wired into this test root');
}

/// Backs the "absent" [GetSeasonLeaderboard]'s repository: throws so a test that
/// reaches an unwired leaderboard slice fails loudly instead of touching a real
/// database.
final class _UnwiredLeaderboardRepository implements LeaderboardRepository {
  @override
  Future<Result<List<LeaderboardEntry>>> seasonStandings(SeasonId seasonId) =>
      throw StateError('The leaderboard use-case was not wired into this root');

  @override
  Future<Result<List<HallOfFameEntry>>> allTimeStandings({
    required int limit,
  }) =>
      throw StateError('The leaderboard use-case was not wired into this root');

  @override
  Future<Result<List<ParticipantSeasonRecord>>> userSeasonRecords({
    required UserId userId,
  }) =>
      throw StateError('The leaderboard use-case was not wired into this root');
}

/// Backs every "absent" group use-case: any method throws so a test that
/// reaches an unwired group slice fails loudly instead of touching a real
/// database. Implements BOTH `GroupRepository` AND `GroupStandingsReader`
/// (mirroring the production `PostgresGroupRepository`), so a single instance
/// backs the group commands and the group-leaderboard read alike.
final class _UnwiredGroupRepository
    implements GroupRepository, GroupStandingsReader {
  static Never _unwired() =>
      throw StateError('A group use-case was not wired into this root');

  @override
  Future<Result<void>> createGroupWithOwner(
    Group group,
    GroupMembership ownerMembership,
  ) => _unwired();

  @override
  Future<Result<Group?>> findGroup(GroupId id) => _unwired();

  @override
  Future<Result<Group?>> findByInviteCode(InviteCode inviteCode) => _unwired();

  @override
  Future<Result<void>> updateGroup(Group group) => _unwired();

  @override
  Future<Result<void>> saveMembership(GroupMembership membership) => _unwired();

  @override
  Future<Result<GroupMembership?>> findMembership(
    GroupId groupId,
    UserId userId,
  ) => _unwired();

  @override
  Future<Result<List<GroupMembership>>> listMemberships(GroupId groupId) =>
      _unwired();

  @override
  Future<Result<List<MyGroupSummary>>> listGroupsForUser(UserId userId) =>
      _unwired();

  @override
  Future<Result<List<GroupStandingEntry>>> groupSeasonStandings({
    required GroupId groupId,
    required SeasonId seasonId,
  }) => _unwired();
}

/// Backs an "absent" group create/regenerate use-case's invite-code generator:
/// throws if a test reaches a group slice it never wired.
final class _UnwiredInviteCodeGenerator implements InviteCodeGenerator {
  @override
  InviteCode newCode() =>
      throw StateError('A group use-case was not wired into this root');
}

/// Backs every "absent" Social reaction use-case: any method throws so a test
/// that reaches an unwired social slice fails loudly instead of touching a real
/// database.
final class _UnwiredReactionRepository implements ReactionRepository {
  static Never _unwired() =>
      throw StateError('A social use-case was not wired into this root');

  @override
  Future<Result<void>> upsertReaction(Reaction reaction) => _unwired();

  @override
  Future<Result<Reaction?>> findReaction(
    GroupId groupId,
    RoundId roundId,
    UserId userId,
  ) => _unwired();

  @override
  Future<Result<List<Reaction>>> listReactionsForRound(
    GroupId groupId,
    RoundId roundId,
  ) => _unwired();

  @override
  Future<Result<bool>> removeReaction(
    GroupId groupId,
    RoundId roundId,
    UserId userId,
  ) => _unwired();
}

/// Backs every "absent" fixture-ledger use-case's port (Axiom 4 Amendment):
/// any method throws so a test that reaches an unwired slice fails loudly
/// instead of touching a real database.
final class _UnwiredFixtureLedgerRepository implements FixtureLedgerRepository {
  static Never _unwired() => throw StateError(
    'A fixture-ledger use-case was not wired into this root',
  );

  @override
  Future<Result<List<FixturePointEntry>>> appendEntries(
    List<FixturePointEntry> entries,
  ) => _unwired();

  @override
  Future<Result<List<FixturePointEntry>>> listEntries(
    ParticipantId participantId,
  ) => _unwired();

  @override
  Future<Result<List<FixturePointEntry>>> findByFixture(FixtureRef fixture) =>
      _unwired();
}

/// Backs every "absent" fixture-social use-case's port (Axiom 4 Amendment):
/// any method throws so a test that reaches an unwired slice fails loudly
/// instead of touching a real database.
final class _UnwiredFixtureReactionRepository
    implements FixtureReactionRepository {
  static Never _unwired() => throw StateError(
    'A fixture-social use-case was not wired into this root',
  );

  @override
  Future<Result<void>> upsertReaction(FixtureReaction reaction) => _unwired();

  @override
  Future<Result<FixtureReaction?>> findReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  ) => _unwired();

  @override
  Future<Result<List<FixtureReaction>>> listReactionsForFixture(
    GroupId groupId,
    FixtureRef fixture,
  ) => _unwired();

  @override
  Future<Result<bool>> removeReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  ) => _unwired();
}

/// Backs an "absent" [GetGroupActivityFeed]'s feed reader: throws if a test
/// reaches the social feed slice it never wired.
final class _UnwiredActivityFeedReader implements ActivityFeedReader {
  @override
  Future<Result<List<ActivityEvent>>> groupActivityFeed({
    required GroupId groupId,
    required int limit,
  }) => throw StateError('A social use-case was not wired into this root');
}

/// Backs every "absent" Notifications use-case: any method throws so a test
/// that reaches an unwired notification slice fails loudly instead of touching
/// a real database.
/// Refuses every call: see [_unwiredDeviceTokenRepository].
final class _UnwiredDeviceTokenRepository implements DeviceTokenRepository {
  @override
  Future<Result<void>> upsert({
    required UserId userId,
    required String token,
    required String platform,
  }) => throw StateError(
    'DeviceTokenRepository was not wired into this test root',
  );
}

/// Backs the "absent" notification-preference use-cases and the absent
/// reminder sweep: throws if a test reaches a preference slice it never
/// wired.
final class _UnwiredNotificationPreferenceRepository
    implements NotificationPreferenceRepository {
  static Never _unwired() => throw StateError(
    'Notification preferences were not wired into this test root',
  );

  @override
  Future<Result<NotificationPreferences>> preferencesOf(UserId userId) =>
      _unwired();

  @override
  Future<Result<NotificationPreferences>> save(
    UserId userId,
    NotificationPreferences preferences,
  ) => _unwired();

  @override
  Future<Result<Set<String>>> predictionReminderOptOuts() => _unwired();
}

/// Backs the "absent" favorite-teams use-cases: throws if a test reaches the
/// slice it never wired.
final class _UnwiredFavoriteTeamRepository implements FavoriteTeamRepository {
  static Never _unwired() =>
      throw StateError('Favorite teams were not wired into this test root');

  @override
  Future<Result<FavoriteTeams>> favoritesOf(UserId userId) => _unwired();

  @override
  Future<Result<FavoriteTeams>> replace(UserId userId, FavoriteTeams teams) =>
      _unwired();
}

/// Refuses every call: see [_absentFlushNotificationQueue].
final class _UnwiredNotificationQueue implements NotificationQueue {
  @override
  Future<Result<void>> enqueue(List<PushToQueue> pushes) =>
      throw StateError('The notification queue was not wired into this root');

  @override
  Future<Result<List<QueuedPush>>> claimDue({
    required DateTime now,
    required int limit,
  }) => throw StateError('The notification queue was not wired into this root');

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) =>
      throw StateError('The notification queue was not wired into this root');
}

/// Refuses every call: see [_absentRecordPushOpen].
final class _UnwiredPushOpenRepository implements PushOpenRepository {
  @override
  Future<Result<void>> record({
    required UserId userId,
    required String link,
    required DateTime openedAt,
  }) => throw StateError('RecordPushOpen was not wired into this test root');
}

/// Refuses every call: see [_absentSendStreakSavers].
final class _UnwiredStreakSaverRepository implements StreakSaverRepository {
  static Never _unwired() =>
      throw StateError('The streak-saver sweep was not wired into this root');

  @override
  Future<Result<List<StreakSaverTarget>>> dueTargets({
    required String today,
    required DateTime from,
    required DateTime to,
  }) => _unwired();

  @override
  Future<Result<void>> markSent({
    required StreakSaverTarget target,
    required String sendDate,
    required DateTime now,
  }) => _unwired();

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) => _unwired();
}

/// Refuses every call: see [_absentSendOvertakenPushes].
final class _UnwiredOvertakenRepository implements OvertakenRepository {
  static Never _unwired() =>
      throw StateError('The overtaken sweep was not wired into this root');

  @override
  Future<Result<List<WeeklyLeagueId>>> openLeagues({
    required DateTime weekStart,
  }) => _unwired();

  @override
  Future<Result<Map<UserId, int>>> rankMarks(WeeklyLeagueId leagueId) =>
      _unwired();

  @override
  Future<Result<void>> saveRankMarks({
    required WeeklyLeagueId leagueId,
    required Map<UserId, int> ranks,
    required Map<UserId, UserId> passedBy,
    required DateTime now,
  }) => _unwired();

  @override
  Future<Result<Map<UserId, OvertakenRecipient>>> recipients({
    required WeeklyLeagueId leagueId,
    required List<UserId> userIds,
  }) => _unwired();

  @override
  Future<Result<void>> markSent({
    required UserId userId,
    required WeeklyLeagueId leagueId,
    required String sendDate,
    required DateTime now,
  }) => _unwired();

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) => _unwired();
}

/// Refuses every call: see [_absentSendPreMatchReminders].
final class _UnwiredPreMatchReminderRepository
    implements PreMatchReminderRepository {
  static Never _unwired() =>
      throw StateError('The pre-match sweep was not wired into this root');

  @override
  Future<Result<List<PreMatchTarget>>> dueTargets({
    required DateTime from,
    required DateTime to,
  }) => _unwired();

  @override
  Future<Result<void>> markSent({
    required PreMatchTarget target,
    required String sendDate,
    required DateTime now,
  }) => _unwired();

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) => _unwired();
}

/// Refuses every call: see [_absentSendPredictionReminders].
final class _UnwiredPredictionReminderRepository
    implements PredictionReminderRepository {
  static Never _unwired() =>
      throw StateError('The reminder sweep was not wired into this root');

  @override
  Future<Result<DateTime?>> firstKickoffInWindow({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) => _unwired();

  @override
  Future<Result<List<ReminderTarget>>> pendingTargets({
    required DateTime windowStart,
    required DateTime windowEnd,
    required String reminderDate,
  }) => _unwired();

  @override
  Future<Result<void>> markSent({
    required List<UserId> userIds,
    required String reminderDate,
    required DateTime now,
  }) => _unwired();

  @override
  Future<Result<Map<String, int>>> sentCountsSince({
    required List<UserId> userIds,
    required String fromDate,
  }) => _unwired();

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) => _unwired();
}

final class _UnwiredNotificationRepository implements NotificationRepository {
  static Never _unwired() =>
      throw StateError('A notification use-case was not wired into this root');

  @override
  Future<Result<bool>> createIfAbsent(Notification notification) => _unwired();

  @override
  Future<Result<List<Notification>>> listForRecipient(
    UserId recipientId, {
    required int limit,
  }) => _unwired();

  @override
  Future<Result<Notification?>> findForRecipient(
    NotificationId id,
    UserId recipientId,
  ) => _unwired();

  @override
  Future<Result<bool?>> markRead(
    NotificationId id,
    UserId recipientId,
    DateTime readAt,
  ) => _unwired();

  @override
  Future<Result<int>> unreadCount(UserId recipientId) => _unwired();
}

final class _UnwiredAnnouncementRepository implements AnnouncementRepository {
  static Never _unwired() =>
      throw StateError('An announcement use-case was not wired into this root');

  @override
  Future<Result<void>> save(Announcement announcement) => _unwired();

  @override
  Future<Result<List<Announcement>>> findByIds(List<AnnouncementId> ids) =>
      _unwired();

  @override
  Future<Result<List<AnnouncementRecipient>>> audience() => _unwired();
}

/// Backs an "absent" [AuthGateway]: throws if a test reaches the auth
/// slice it never wired.
final class _UnwiredAuthGateway implements AuthGateway {
  @override
  Future<Result<IssuedSession>> signInWithPassword({
    required String email,
    required String password,
  }) => throw StateError('An auth use-case was not wired into this root');

  @override
  Future<Result<IssuedSession>> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
  }) => throw StateError('An auth use-case was not wired into this root');

  @override
  Future<Result<void>> requestPasswordReset({required String email}) =>
      throw StateError('An auth use-case was not wired into this root');

  @override
  Future<Result<void>> updatePassword({
    required String recoveryToken,
    required String password,
  }) => throw StateError('An auth use-case was not wired into this root');
}

/// The service principal the provider sync records results under. Not a
/// person; never issued to a session.
const String _providerSyncUserId = '00000000-0000-4000-8000-00000000517c';
