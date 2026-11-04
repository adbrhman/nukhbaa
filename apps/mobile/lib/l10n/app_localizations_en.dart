// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Nukhba';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get loading => 'Loading…';

  @override
  String get error => 'Something went wrong';

  @override
  String get retry => 'Retry';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get markNotificationRead => 'Mark as read';

  @override
  String get createAccount => 'Create account';

  @override
  String get registerTitle => 'Create a Nukhbaa account';

  @override
  String get firstName => 'Real first name';

  @override
  String get firstNameHint => 'e.g. Mohammed';

  @override
  String get firstNameRequired => 'Enter your first name.';

  @override
  String get familyName => 'Real family name';

  @override
  String get familyNameHint => 'e.g. Ahmed';

  @override
  String get familyNameRequired =>
      'Enter your family name or your father\'s name.';

  @override
  String get realNameNote => 'Enter the name people know you by in your life.';

  @override
  String get signInSubtitle =>
      'Sign in with your email and password to continue.';

  @override
  String get signUpSubtitle => 'Create an account to start playing Nukhba.';

  @override
  String get email => 'Email';

  @override
  String get emailHint => 'you@example.com';

  @override
  String get emailRequired => 'Please enter your email.';

  @override
  String get password => 'Password';

  @override
  String get passwordRequired => 'Please enter your password.';

  @override
  String get displayName => 'Name';

  @override
  String get displayNameHint =>
      'Your first name and your father\'s name or surname, e.g. Mohammed Ali';

  @override
  String get displayNameRequired => 'Please enter your name.';

  @override
  String get displayNameTwoPart =>
      'Enter your first name and your father\'s name or surname, not one name.';

  @override
  String get rememberMe => 'Remember me';

  @override
  String get rememberShowPassword =>
      'Tap «Remember me» to show the saved password';

  @override
  String rememberedPassword(String password) {
    return 'Saved password: $password';
  }

  @override
  String get changeDisplayName => 'Change name';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get toggleToSignIn => 'Already have an account? Sign in';

  @override
  String get toggleToRegister => 'New here? Create an account';

  @override
  String get tagline => 'Football prediction platform';

  @override
  String get authTabSignIn => 'Sign in';

  @override
  String get authTabRegister => 'Register';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get confirmPasswordRequired => 'Please confirm your password.';

  @override
  String get passwordMismatch => 'Passwords do not match.';

  @override
  String get rulesTitle => 'How to play?';

  @override
  String get rulesTagline => 'Predict, compete, top the table, be Nukhba.';

  @override
  String get rulesPredictMajorLeagues =>
      'Predict matches from the major leagues';

  @override
  String get rulesCorrectPrediction => 'Exact score (e.g. 2-1): 3 points';

  @override
  String get rulesWrongPrediction =>
      'Any other prediction: 0 points, even with the right outcome (winner or draw)';

  @override
  String get rulesDoubleMatch =>
      'Your double doubles the points: an exact score on it is 6 points';

  @override
  String get rulesSoloExact =>
      'From 1 November 2026: the only player of all to call a match\'s exact score gets 6 points, or 9 on his double';

  @override
  String get rulesOneDoublePerDay =>
      'One double per day, picked from that day\'s matches';

  @override
  String get rulesLockAtKickoff =>
      'You can change your prediction until kick-off; then it locks';

  @override
  String get rulesMonthStartsAtZero =>
      'Each month is a new contest that starts from zero; the season (September to August) adds its months up';

  @override
  String get notifications => 'Notifications';

  @override
  String get signedIn => 'Signed in';

  @override
  String get userId => 'User ID';

  @override
  String get role => 'Role';

  @override
  String get status => 'Status';

  @override
  String get browseCompetitions => 'Browse competitions';

  @override
  String get hallOfFame => 'Hall of Fame';

  @override
  String get myPredictions => 'My Predictions';

  @override
  String get createGroup => 'Create a group';

  @override
  String get joinGroup => 'Join a group';

  @override
  String get adminDashboard => 'Nukhba admin';

  @override
  String get homePerformanceSection => 'Performance & Predictions';

  @override
  String get homeAdminSection => 'Admin';

  @override
  String get homeMatchesSubtitle => 'Predict this month\'s fixtures';

  @override
  String get hallOfFameEmpty => 'Nobody has earned any points yet.';

  @override
  String hallOfFameSeasonsPlayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seasons played',
      one: '1 season played',
      zero: 'No seasons played',
    );
    return '$_temp0';
  }

  @override
  String get competitionSeasonsEmpty => 'This competition has no seasons yet.';

  @override
  String leaderboardTitle(String label) {
    return '$label — Leaderboard';
  }

  @override
  String get seasonLeaderboardEmpty => 'No one has joined this season yet.';

  @override
  String get leaderboardsScreenTitle => 'Leaderboards';

  @override
  String get leaderboardsLoadFailed => 'Couldn\'t load active seasons.';

  @override
  String get leaderboardsJoinSeasonPrompt =>
      'Join a season to see your standings here.';

  @override
  String get leaderboardsSeasonEmpty =>
      'No results recorded for this season yet.';

  @override
  String leaderboardEntriesCounted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries counted',
      one: '1 entry counted',
      zero: 'No entries counted',
    );
    return '$_temp0';
  }

  @override
  String leaderboardAccuracy(int percent) {
    return '$percent% exact';
  }

  @override
  String pointsAbbreviated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pts',
      one: '1 pt',
      zero: '0 pts',
    );
    return '$_temp0';
  }

  @override
  String get seasonLeaderboardTab => 'Season points';

  @override
  String get fixtureLeaderboardTab => 'Fixture points';

  @override
  String get fixtureLeaderboardEmpty =>
      'No fixture has been scored yet this season.';

  @override
  String get selectRoundLabel => 'Select round';

  @override
  String get roundKingLabel => 'Round king';

  @override
  String get groupLeaderboardEmpty =>
      'No members of this group have joined the season yet.';

  @override
  String get groupLeaderboardSelectSeasonTitle => 'Select a season';

  @override
  String get groupLeaderboardNoActiveSeasons => 'No active season right now.';

  @override
  String get competitions => 'Competitions';

  @override
  String get competitionsEmpty => 'There are no competitions to browse yet.';

  @override
  String get visibilityPublic => 'Public';

  @override
  String get visibilityPrivate => 'Private';

  @override
  String get predictionHistoryEmpty =>
      'You have not submitted any predictions yet.';

  @override
  String historyKickoffAt(String moment) {
    return 'Kickoff · $moment';
  }

  @override
  String historySubmittedAt(String moment) {
    return 'Predicted · $moment';
  }

  @override
  String get historyStatusUpcoming => 'Not started';

  @override
  String get historyGradeExact => 'Exact score';

  @override
  String get historyGradeOutcome => 'Right outcome, wrong score';

  @override
  String get historyGradeWrong => 'Incorrect';

  @override
  String get historyGradeMissed => 'Not counted';

  @override
  String predictionHistoryScoreLine(
    String fixtureId,
    int homeGoals,
    int awayGoals,
  ) {
    return '$fixtureId: $homeGoals - $awayGoals';
  }

  @override
  String groupFeedTitle(String groupName) {
    return '$groupName Feed';
  }

  @override
  String get groupFeedEmpty => 'No activity yet.';

  @override
  String get activityRoundScored => 'Round scored';

  @override
  String get activityMemberJoined => 'New member joined';

  @override
  String activityRankShift(int oldRank, int newRank) {
    return 'Moved from #$oldRank to #$newRank';
  }

  @override
  String get activityRankShiftUnknown => 'Rank changed';

  @override
  String seasonRoundsTitle(String seasonLabel) {
    return '$seasonLabel — Rounds';
  }

  @override
  String get viewLeaderboardTooltip => 'View leaderboard';

  @override
  String get fixturePredictionTooltip => 'Predict season fixtures';

  @override
  String get seasonRoundsEmpty => 'This season has no rounds yet.';

  @override
  String roundItemTitle(int sequence) {
    return 'Round $sequence';
  }

  @override
  String roundDeadlineLine(String statusLabel, String deadline) {
    return '$statusLabel · Deadline $deadline';
  }

  @override
  String get roundStatusOpen => 'Open for predictions';

  @override
  String get roundStatusLocked => 'Locked';

  @override
  String get roundStatusScored => 'Scored';

  @override
  String get roundFixturesTitle => 'Round';

  @override
  String roundRulesLine(String statusLabel, int rulesetVersion) {
    return '$statusLabel · Rules v$rulesetVersion';
  }

  @override
  String get predictRoundButton => 'Predict this round';

  @override
  String get roundFixturesEmpty => 'This round has no fixtures yet.';

  @override
  String fixtureItemTitle(String fixtureId) {
    return 'Fixture $fixtureId';
  }

  @override
  String fixtureVsTitle(String home, String away) {
    return '$home vs $away';
  }

  @override
  String get predictionTitle => 'Predict';

  @override
  String predictionClosedMessage(String status) {
    return 'This round is $status. Predictions are closed.';
  }

  @override
  String get predictionNotYetPredictableMessage =>
      'You can predict this round once the earlier round is locked';

  @override
  String get genericErrorMessage => 'Something went wrong. Please try again.';

  @override
  String get tryAgainButton => 'Try again';

  @override
  String get predictionAlreadySubmitted =>
      'You have already submitted a prediction for this round. Editing and submitting again will update it.';

  @override
  String get predictionSaved => 'Your prediction was saved.';

  @override
  String get submitPredictionButton => 'Submit prediction';

  @override
  String get predictionDoubleLabel => 'Double';

  @override
  String get predictionMakeItDoubleLabel => 'Make it double ×2';

  @override
  String get accountDarkModeLabel => 'Dark mode';

  @override
  String get avatarChange => 'Change picture';

  @override
  String get avatarChoose => 'Choose from gallery';

  @override
  String get avatarRemove => 'Remove picture';

  @override
  String get avatarTooLarge => 'That picture is too large. Pick a smaller one.';

  @override
  String get avatarUploadFailed => 'Couldn\'t upload the picture.';

  @override
  String get predictionScorePickedLabel => 'Score picked';

  @override
  String get predictionFixtureLockedLabel => 'Started';

  @override
  String get predictionDoubleHint =>
      'Select exactly one open fixture as your double before submitting.';

  @override
  String get predictionIncompleteHint =>
      'Enter a score for every open fixture before submitting.';

  @override
  String get predictionNoOpenFixturesMessage =>
      'Every fixture in this round has already kicked off. There is nothing left to predict.';

  @override
  String get fixturePredictionTitle => 'Predict Season Fixtures';

  @override
  String get fixturePredictionEmptyMessage =>
      'No fixtures are linked to this season yet.';

  @override
  String get fixturePredictionSavedMessage =>
      'Your prediction for this fixture was saved.';

  @override
  String get submitFixturePredictionButton => 'Submit';

  @override
  String get matchesTitle => 'Matches';

  @override
  String get matchesEmpty => 'No open matches right now.';

  @override
  String kickoffCountdownDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'in ${days}d',
    );
    return '$_temp0';
  }

  @override
  String get fixtureCardExpandTooltip => 'Expand to predict';

  @override
  String get fixtureCardCollapseTooltip => 'Collapse';

  @override
  String get predictionQuickFillHomeWinTooltip => 'Quick-fill: home win';

  @override
  String get predictionQuickFillDrawTooltip => 'Quick-fill: draw';

  @override
  String get predictionQuickFillAwayWinTooltip => 'Quick-fill: away win';

  @override
  String get scoreStepperDecreaseTooltip => 'Decrease';

  @override
  String get scoreStepperIncreaseTooltip => 'Increase';

  @override
  String predictionYourForecastScoreLine(int homeGoals, int awayGoals) {
    return 'Your forecast: $homeGoals - $awayGoals';
  }

  @override
  String get predictionPendingResultLabel => 'Result pending';

  @override
  String get adminAuditLogTab => 'Audit Log';

  @override
  String get adminUsersTab => 'Users';

  @override
  String get adminLedgerLookupTab => 'Ledger Lookup';

  @override
  String get adminAuditLogEmpty => 'No audit entries yet.';

  @override
  String get adminReasonMandatoryLabel => 'Reason (mandatory)';

  @override
  String get adminSuspendButton => 'Suspend';

  @override
  String get adminReinstateButton => 'Reinstate';

  @override
  String get adminUsersSearchLabel => 'Search by email';

  @override
  String get adminUsersEmptyResults => 'No matching users.';

  @override
  String adminSanctionResultMessage(String userId, String status) {
    return '$userId is now $status';
  }

  @override
  String get adminParticipantIdLabel => 'Participant ID';

  @override
  String get adminLookUpButton => 'Look up';

  @override
  String get adminFixturesTab => 'Fixture Identity';

  @override
  String get adminFixtureIdOptionalLabel =>
      'Fixture ID (correction only — leave empty to register)';

  @override
  String get adminSelectCompetitionLabel => 'Select league (competitions)';

  @override
  String get adminHomeTeamLabel => 'Home team';

  @override
  String get adminAwayTeamLabel => 'Away team';

  @override
  String get adminPickKickoffButton => 'Pick kickoff time';

  @override
  String get adminRegisterFixtureButton => 'Register fixture';

  @override
  String get adminCorrectFixtureButton => 'Correct fixture';

  @override
  String get adminResultsScoringTab => 'Results & Scoring';

  @override
  String get adminDashboardTab => 'Home';

  @override
  String get adminMonthlyCompetitionsTab => 'Monthly Competitions';

  @override
  String get adminPredictionsTab => 'Predictions';

  @override
  String get adminMonthlyCompetitionsEmpty => 'No public competitions yet.';

  @override
  String get adminMonthlyCompetitionsNoActiveSeason =>
      'No active season this month';

  @override
  String get adminCreateCompetitionSectionTitle => 'Create competition';

  @override
  String get adminCompetitionNameLabel => 'Competition name';

  @override
  String get adminVisibilityLabel => 'Visibility';

  @override
  String get adminVisibilityPublicLabel => 'Public';

  @override
  String get adminVisibilityPrivateLabel => 'Private';

  @override
  String get adminCreateCompetitionButton => 'Create';

  @override
  String adminCreateCompetitionSuccess(String name) {
    return 'Created competition \"$name\"';
  }

  @override
  String get adminStartSeasonButton => 'Start season';

  @override
  String adminStartSeasonSuccess(String label) {
    return 'Started season $label';
  }

  @override
  String get adminSeasonIdLabel => 'Season ID';

  @override
  String get adminLinkFixtureSectionTitle => 'Link a fixture to a round';

  @override
  String get adminRoundIdLabel => 'Round ID';

  @override
  String get adminFixtureIdLabel => 'Fixture ID';

  @override
  String get adminDisplayOrderLabel => 'Display order';

  @override
  String get adminLinkFixtureButton => 'Link fixture to round';

  @override
  String get adminScoringTab => 'Results & Scoring';

  @override
  String get adminRecordResultSectionTitle => 'Record fixture result';

  @override
  String get adminHomeGoalsLabel => 'Home goals';

  @override
  String get adminAwayGoalsLabel => 'Away goals';

  @override
  String get adminRecordResultButton => 'Record result';

  @override
  String get adminScoreFixtureButton => 'Score fixture';

  @override
  String get adminPostFixtureLedgerButton => 'Post to ledger';

  @override
  String get adminScoreRoundSectionTitle => 'Score round';

  @override
  String get adminScoreRoundButton => 'Score round';

  @override
  String get adminPostToLedgerButton => 'Post to ledger';

  @override
  String get adminPostToLedgerSuccessLabel => 'Posted, new entries';

  @override
  String get adminRoundScoresSectionTitle => 'Round participant scores';

  @override
  String get adminViewScoresButton => 'View scores';

  @override
  String get adminTotalPointsLabel => 'Total points';

  @override
  String get adminRoundReportSectionTitle => 'Round report';

  @override
  String get adminViewRoundReportButton => 'View round report';

  @override
  String get adminRoundReportRankLabel => 'Rank';

  @override
  String get adminRoundReportShareButton => 'Copy to share';

  @override
  String get adminRoundReportCopiedMessage => 'Copied — share it on WhatsApp';

  @override
  String get adminRoundReportEmpty => 'No participants in this round';

  @override
  String get adminRoundReportSectionEmpty => 'No report for this round yet';

  @override
  String get adminViewFixtureReportButton => 'View fixture report';

  @override
  String get adminFixtureReportSectionEmpty => 'No report for this fixture yet';

  @override
  String get seasonRecord => 'Championship record';

  @override
  String get seasonRecordEmpty => 'You have no season result yet.';

  @override
  String get eliteCard => 'Elite card';

  @override
  String get eliteCardEmpty => 'Play a season and your card appears here.';

  @override
  String get eliteCardBestRank => 'Best finish';

  @override
  String get eliteCardBestAccuracy => 'Best accuracy';

  @override
  String get eliteCardTotalPoints => 'Total points';

  @override
  String get eliteCardRankTrend => 'Your finishes over time';

  @override
  String eliteCardSeasonsPlayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seasons',
      one: '1 season',
      zero: 'No seasons yet',
    );
    return '$_temp0';
  }

  @override
  String get badgeFirstSeason => 'First season';

  @override
  String get badgeFirstPodium => 'First podium';

  @override
  String get badgeSharpshooter => '50% exact';

  @override
  String get badgeTitleHolder => 'Title';

  @override
  String get myActiveSeasons => 'My Active Seasons';

  @override
  String get myActiveSeasonsEmpty => 'You have no active seasons right now.';

  @override
  String get myGroups => 'My Groups';

  @override
  String get myGroupsEmpty => 'You haven\'t joined any group yet.';

  @override
  String get groupRoleOwner => 'Owner';

  @override
  String get groupRoleMember => 'Member';

  @override
  String groupMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
      zero: 'No members',
    );
    return '$_temp0';
  }

  @override
  String get createGroupTitle => 'Create Group';

  @override
  String get groupNameLabel => 'Group name';

  @override
  String get createGroupButton => 'Create';

  @override
  String get joinGroupTitle => 'Join Group';

  @override
  String get inviteCodeLabel => 'Invite code';

  @override
  String get joinGroupButton => 'Join';

  @override
  String get groupCreatedTitle => 'Group created';

  @override
  String get groupInviteCodeHint =>
      'Share this code with anyone you want to invite';

  @override
  String get copyInviteCodeButton => 'Copy code';

  @override
  String get inviteCodeCopiedMessage => 'Invite code copied';

  @override
  String get doneButton => 'Done';

  @override
  String get ledgerTitle => 'My Points';

  @override
  String get myLedgerLabel => 'My points ledger';

  @override
  String get mySeasonsLabel => 'My seasons';

  @override
  String get mySeasonsEmpty => 'No season has finished yet.';

  @override
  String mySeasonsMonthCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String get ledgerEmpty => 'No points movements yet.';

  @override
  String ledgerEntryCount(int count) {
    return '$count movements counted';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmpty => 'You have no notifications yet.';

  @override
  String get notificationRoundScored => 'A round you predicted was scored';

  @override
  String get notificationGroupMemberJoined => 'Someone joined your group';

  @override
  String get notificationReactionReceived => 'You received a reaction';

  @override
  String get notificationFixtureScored =>
      'A match you predicted has been scored';

  @override
  String get notificationAdminAnnouncement => 'A message from the admins';

  @override
  String get notificationsMarkAsRead => 'Mark as read';

  @override
  String get adminAddMatchSectionTitle =>
      'Register a match and add it to a round';

  @override
  String get adminSelectSeasonLabel => 'Select season';

  @override
  String get adminNoSeasonsHint => 'This competition has no seasons.';

  @override
  String get adminSelectMonthLabel => 'Select month';

  @override
  String get adminFixtureEditTab => 'Edit fixture';

  @override
  String get adminFixtureDeleteTab => 'Delete fixture';

  @override
  String adminFixtureCurrentLeagueLabel(String league) {
    return 'Current league: $league';
  }

  @override
  String get adminFixtureNoLeagueLabel => 'This fixture has no league yet.';

  @override
  String get adminNoMonthsHint => 'No month has been opened yet.';

  @override
  String get adminSelectLeagueLabel => 'Select league';

  @override
  String get adminNoLeaguesHint => 'The league catalog is empty.';

  @override
  String get adminPickLeagueFirstHint => 'Pick a league to list its clubs.';

  @override
  String get adminSelectFixtureLabel => 'Select fixture';

  @override
  String get adminNoSeasonFixturesHint => 'This season has no fixtures.';

  @override
  String get adminFixtureIncompleteDataLabel => 'Fixture with incomplete data';

  @override
  String get adminAddMatchButton => 'Register match and add to round';

  @override
  String adminAddMatchSuccess(String home, String away) {
    return 'Added $home vs $away to the season.';
  }

  @override
  String get adminCorrectFixtureSectionTitle => 'Correct a registered fixture';

  @override
  String get adminCorrectFixtureSubtitle =>
      'Pick a registered fixture to fix a mistyped team name or kickoff time, before its round is linked or locked.';

  @override
  String adminCorrectFixtureSuccess(String home, String away) {
    return 'Updated $home vs $away.';
  }

  @override
  String get adminPredictionsSubtitle =>
      'Pick a competition, season and fixture to see every prediction recorded for it, scored or not.';

  @override
  String get adminLoadPredictionsButton => 'Show predictions';

  @override
  String get adminPredictionsEmpty =>
      'No predictions recorded for this fixture yet.';

  @override
  String adminPredictionSubmittedAtLabel(String submittedAt) {
    return 'Submitted $submittedAt';
  }

  @override
  String get adminSelectRoundFirst => 'Select a round first.';

  @override
  String get adminExistingFixturesSectionTitle => 'Fixtures in this round';

  @override
  String get adminRemoveFixtureTooltip => 'Remove this fixture from the round';

  @override
  String get adminRemoveFixtureConfirmTitle => 'Remove fixture?';

  @override
  String adminRemoveFixtureConfirmMessage(String home, String away) {
    return 'Remove $home vs $away from this round? This cannot be undone.';
  }

  @override
  String get adminRemoveFixtureConfirmButton => 'Remove';

  @override
  String get adminRemoveFixtureCancelButton => 'Cancel';

  @override
  String get adminRemoveFixtureSuccess => 'Fixture removed from the round.';

  @override
  String get fixturesDateToday => 'Today';

  @override
  String get fixturesDateYesterday => 'Yesterday';

  @override
  String get fixturesDateTomorrow => 'Tomorrow';

  @override
  String get fixturePredictionsButton => 'All predictions';

  @override
  String get fixturePredictionsTitle => 'Everyone\'s predictions';

  @override
  String get fixturePredictionsSearchHint => 'Search for a player';

  @override
  String get fixturePredictionsEmpty => 'No predictions for these matches yet.';

  @override
  String get fixturePredictionsNoMatch => 'No player by that name.';

  @override
  String get fixturePredictionsUnnamed => 'Player';

  @override
  String fixturePredictionsMine(String name) {
    return '$name (you)';
  }

  @override
  String get fixturePredictionsPlayerHeader => 'Player';

  @override
  String get fixturePredictionsNoStarted =>
      'No match of this day has kicked off yet.';

  @override
  String get fixturesCalendarTooltip => 'Calendar';

  @override
  String get fixturesDayEmpty => 'No matches on this day.';

  @override
  String get fixturesLiveLabel => 'Live';

  @override
  String get adminRemoveFixtureFromSeasonButton => 'Remove from the month';

  @override
  String adminRemoveFixtureFromSeasonConfirm(String home, String away) {
    return 'This unlinks \"$home vs $away\" from the month\'s competition. It cannot be removed once anyone has predicted it or a result is recorded.';
  }

  @override
  String get adminRemoveFixtureFromSeasonSuccess =>
      'Fixture removed from the month\'s competition.';

  @override
  String get adminTeamNotInCatalogHint =>
      'This name is not in the clubs list, so the match cannot be saved with it. Pick the club from the list, or add it to the list if it is missing.';

  @override
  String get myPoints => 'My points';

  @override
  String get myPointsEmpty => 'You have no counted points yet.';

  @override
  String get myPointsLatestScored => 'Through the latest counted match';

  @override
  String get myPointsPerformance => 'Performance';

  @override
  String get myPointsRank => 'Rank';

  @override
  String get myPointsLeaderGap => 'Gap to leader';

  @override
  String get myPointsNeededForFirst => 'Needed for first';

  @override
  String get myPointsLeading => 'You are in first';

  @override
  String get myPointsLeaderUnavailable => 'Leader gap is unavailable right now';

  @override
  String get myPointsSettledMatches => 'Counted matches';

  @override
  String get adminCountedFixturesTab => 'Counted fixtures';

  @override
  String get adminCountedFixturesEmpty =>
      'No counted fixtures in the current period.';

  @override
  String get adminCountedLabel => 'Counted';

  @override
  String get adminCountedFixturesSubtitle =>
      'Fixtures with completed point scoring';

  @override
  String get leaderboardsHeading => 'Leaderboard';

  @override
  String get leaderboardScopeMonth => 'Month';

  @override
  String get leaderboardScopeDay => 'Today';

  @override
  String get leaderboardScopeSeason => 'Season';

  @override
  String get leaderboardSubtitleMonth => 'Who leads this month?';

  @override
  String get leaderboardSubtitleDay => 'Who leads the day?';

  @override
  String get leaderboardSubtitleSeason => 'Who will be the season champion?';

  @override
  String get leaderboardDayEmpty =>
      'No results have been recorded for this day\'s matches yet.';

  @override
  String get leaderboardSeasonEmpty =>
      'No points have been recorded this season yet.';

  @override
  String get historyFilterAll => 'All';

  @override
  String get historyFilterUpcoming => 'Upcoming';

  @override
  String get historyFilterCompleted => 'Completed';

  @override
  String get historyFilterEmpty => 'No predictions in this category.';

  @override
  String get accountMyPredictionsSubtitle => 'View all your predictions';

  @override
  String get accountMyPointsSubtitle => 'Your points and statistics in detail';

  @override
  String get accountEliteCardSubtitle => 'Your Nukhba membership details';

  @override
  String get accountSettings => 'Settings';

  @override
  String get accountRecordsSection => 'My record';

  @override
  String get accountStatPoints => 'Points';

  @override
  String get accountStatMatches => 'Matches';

  @override
  String get accountStatAccuracy => 'Accuracy';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get forgotPasswordTitle => 'Reset your password';

  @override
  String get forgotPasswordSubtitle =>
      'Enter your email and we will send you a password reset link.';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get passwordResetEmailSent =>
      'If the email belongs to an account, you will receive a password reset link. Check your inbox.';

  @override
  String get resetPasswordTitle => 'Set a new password';

  @override
  String get resetPasswordSubtitle => 'Enter a new password for your account.';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmNewPassword => 'Confirm new password';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters.';

  @override
  String get saveNewPassword => 'Save new password';

  @override
  String get passwordResetSuccess =>
      'Your password has been changed successfully.';

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get rulesRegularTime =>
      'Regular matches: the score after 90 minutes plus stoppage time counts.';

  @override
  String get rulesKnockout =>
      'Knockout matches: the score after extra time counts when it is played; a match decided on penalties counts as a draw.';

  @override
  String get rulesKnockoutExample =>
      'Example: 1-1 after 120 minutes, then a shoot-out win → the result is 1-1, and picking either side to win scores nothing.';

  @override
  String get accountRules => 'How to play';

  @override
  String get adminResultRuleHint =>
      'Enter the score after extra time when it was played, without shoot-out goals.';

  @override
  String get dailyChallengeTitle => 'Today\'s challenge';

  @override
  String dailyChallengeProgress(int predicted, int total) {
    return '$predicted of $total';
  }

  @override
  String get dailyChallengeCta => 'Predict every match of the day';

  @override
  String get dailyChallengeComplete => 'Today is complete. Well played.';

  @override
  String get dailyChallengeEmpty => 'No matches today.';

  @override
  String streakBadgeLabel(int days) {
    return 'Streak: $days';
  }

  @override
  String get leaderboardScopeLeague => 'League';

  @override
  String get leaderboardSubtitleLeague => 'Climb a tier before the week ends';

  @override
  String get weeklyLeagueTierBronze => 'Bronze';

  @override
  String get weeklyLeagueTierSilver => 'Silver';

  @override
  String get weeklyLeagueTierGold => 'Gold';

  @override
  String get weeklyLeagueTierPlatinum => 'Platinum';

  @override
  String get weeklyLeagueTierElite => 'Elite';

  @override
  String weeklyLeagueGroup(int group) {
    return 'Group $group';
  }

  @override
  String weeklyLeaguePeriod(String start, String end) {
    return '$start to $end';
  }

  @override
  String weeklyLeaguePromotionZone(int count) {
    return 'Top $count go up';
  }

  @override
  String weeklyLeagueRelegationZone(int count) {
    return 'Bottom $count go down';
  }

  @override
  String get weeklyLeagueOutcomePromoted => 'Going up';

  @override
  String get weeklyLeagueOutcomeHeld => 'Staying';

  @override
  String get weeklyLeagueOutcomeRelegated => 'Going down';

  @override
  String get weeklyLeagueEmpty => 'Nobody is in your group yet.';

  @override
  String get weeklyLeagueUnnamedMember => 'Player';

  @override
  String get myBadges => 'My badges';

  @override
  String get accountBadgesSubtitle => 'What you earned and what is next';

  @override
  String badgeWallSummary(int held, int total) {
    return '$held of $total badges';
  }

  @override
  String badgeWallProgress(int current, int target) {
    return '$current / $target';
  }

  @override
  String badgeWallUnlockedOn(String date) {
    return 'Earned on $date';
  }

  @override
  String get badgeWallHeld => 'Earned';

  @override
  String get badgeWallFirstPredictionName => 'First prediction';

  @override
  String get badgeWallFirstPredictionHint => 'Place your first prediction';

  @override
  String get badgeWallPredictions25Name => '25 predictions';

  @override
  String get badgeWallPredictions25Hint => 'Place 25 predictions';

  @override
  String get badgeWallPredictions100Name => '100 predictions';

  @override
  String get badgeWallPredictions100Hint => 'Place 100 predictions';

  @override
  String get badgeWallFirstPerfectDayName => 'Perfect day';

  @override
  String get badgeWallFirstPerfectDayHint => 'Predict every match of one day';

  @override
  String get badgeWallPerfectDays7Name => '7 perfect days';

  @override
  String get badgeWallPerfectDays7Hint => 'Complete 7 match days';

  @override
  String get badgeWallPerfectDays30Name => '30 perfect days';

  @override
  String get badgeWallPerfectDays30Hint => 'Complete 30 match days';

  @override
  String get badgeWallLeagueFirstWeekName => 'First league week';

  @override
  String get badgeWallLeagueFirstWeekHint =>
      'Finish a week of the weekly league';

  @override
  String get badgeWallLeaguePromotedName => 'Promoted';

  @override
  String get badgeWallLeaguePromotedHint =>
      'Move up a tier in the weekly league';

  @override
  String get badgeWallLeagueChampionName => 'Group champion';

  @override
  String get badgeWallLeagueChampionHint => 'Finish first in your league group';

  @override
  String get badgeWallLeagueEliteName => 'Elite';

  @override
  String get badgeWallLeagueEliteHint => 'Finish a week in the Elite tier';

  @override
  String get badgeWallH2hFirstMonthName => 'First month';

  @override
  String get badgeWallH2hFirstMonthHint =>
      'Finish a month of the head-to-head league';

  @override
  String get badgeWallH2hPromotedName => 'Moving up';

  @override
  String get badgeWallH2hPromotedHint =>
      'Go up a division in the head-to-head league';

  @override
  String get badgeWallH2hChampionName => 'Month champion';

  @override
  String get badgeWallH2hChampionHint =>
      'Top your group in the head-to-head league';

  @override
  String get badgeWallH2hFirstDivisionName => 'First division';

  @override
  String get badgeWallH2hFirstDivisionHint =>
      'Finish a month in the first division';

  @override
  String get notificationSettingsTitle => 'Notifications';

  @override
  String get notificationSettingsReminderTitle => 'Prediction reminder';

  @override
  String get notificationSettingsReminderHint =>
      'Three hours before the first match of the day if you have not predicted yet, and about an hour and a half before a match you have not predicted if you predicted some of the day\'s matches';

  @override
  String get notificationSettingsSaveFailed =>
      'Could not save the setting. Try again.';

  @override
  String get notificationSettingsPreMatchTitle => 'Before your team plays';

  @override
  String get notificationSettingsPreMatchHint =>
      'About two hours before a match of a team you follow, if you have not predicted it';

  @override
  String get notificationSettingsStreakSaverTitle => 'Streak saver';

  @override
  String get notificationSettingsStreakSaverHint =>
      'About an hour before your run would break, if today is not predicted yet';

  @override
  String get notificationSettingsOvertakenTitle => 'Overtaken in your league';

  @override
  String get notificationSettingsOvertakenHint =>
      'When someone passes you in this week\'s league, at most once a week';

  @override
  String get insightsTitle => 'Learn from your predictions';

  @override
  String get insightsSubtitle => 'Your accuracy, your patterns, your week';

  @override
  String insightsMonthLine(int correct, int decided) {
    return '$correct right of $decided this month';
  }

  @override
  String insightsCommunity(int percent) {
    return 'Everyone: $percent%';
  }

  @override
  String get insightsWeeksTitle => 'The last weeks';

  @override
  String insightsLastWeek(int correct, int decided, int points) {
    return 'Last week: $correct right of $decided, $points points';
  }

  @override
  String insightsBestPrediction(String home, String away, int points) {
    return 'Best call: $home - $away (+$points)';
  }

  @override
  String insightsBestLeague(String name) {
    return 'Your best league: $name';
  }

  @override
  String insightsWorstLeague(String name) {
    return 'Your hardest league: $name';
  }

  @override
  String insightsFollowedBias(int followed, int others) {
    return 'Your teams: $followed% - others: $others%';
  }

  @override
  String insightsLongestRun(int count) {
    return 'Longest run of right calls: $count';
  }

  @override
  String get insightsEmpty =>
      'Nothing to learn yet: your first results will show here';

  @override
  String weeklyLeagueOvertakenBy(String name) {
    return '$name passed you this week';
  }

  @override
  String get favoriteTeamsTitle => 'Favorite teams';

  @override
  String get favoriteTeamsHint => 'Choose up to 3 teams to follow';

  @override
  String get favoriteTeamsLimitReached =>
      'You follow 3 teams, the most allowed. Remove one to pick another';

  @override
  String get favoriteTeamsSearchHint => 'Search teams';

  @override
  String streakLongestLabel(int days) {
    return 'Longest: $days';
  }

  @override
  String get boardYouLead => 'You lead 🥇';

  @override
  String boardGapToRank(String points, int rank) {
    return '$points to reach rank $rank';
  }

  @override
  String boardPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points',
      one: '1 point',
    );
    return '$_temp0';
  }

  @override
  String get boardNotRanked => 'You are not on this board yet';

  @override
  String get boardYourRank => 'Your rank';

  @override
  String boardYourRankIs(int rank) {
    return 'Your rank $rank';
  }

  @override
  String boardRankIs(int rank) {
    return 'Rank $rank';
  }

  @override
  String boardAccuracyIs(int percent) {
    return 'Accuracy $percent%';
  }

  @override
  String get boardYou => 'You';

  @override
  String get boardListSeparator => ', ';

  @override
  String get boardColRank => 'Rank';

  @override
  String get boardColPlayer => 'Player';

  @override
  String get boardColAccuracy => 'Accuracy';

  @override
  String get boardColMatches => 'Matches';

  @override
  String get boardColPoints => 'Points';

  @override
  String get boardColMovement => 'Move';

  @override
  String get historyShareHit => 'Share your hit';

  @override
  String get shareHitShareButton => 'Share';

  @override
  String get shareHitCloseButton => 'Close';

  @override
  String get shareHitTitle => 'Spot on! 🎯';

  @override
  String get shareHitDoubleTitle => 'Doubled and nailed it!';

  @override
  String get shareHitMyCall => 'My call';

  @override
  String get shareHitFinal => 'Final';

  @override
  String shareHitPoints(int points) {
    String _temp0 = intl.Intl.pluralLogic(
      points,
      locale: localeName,
      other: '+$points points',
      one: '+1 point',
    );
    return '$_temp0';
  }

  @override
  String shareHitRank(int rank) {
    return 'My month rank: $rank';
  }

  @override
  String shareHitMessage(String home, String score, String away) {
    return 'I called $home $score $away on Nukhba 🎯';
  }

  @override
  String shareHitJoin(String link) {
    return 'Play with me: $link';
  }

  @override
  String matchCardShareMessage(String home, String score, String away) {
    return 'My call: $home $score $away on Nukhba 🎯';
  }

  @override
  String get historyFinished => 'Full time';

  @override
  String get matchCardYourCall => 'Your call';

  @override
  String get signOutConfirmMessage =>
      'Sign out of your account on this device?';

  @override
  String get championCrownLabel => 'Month champion';

  @override
  String championTitleOne(String month) {
    return '$month champion';
  }

  @override
  String championTitleTwo(String month) {
    return '$month champions';
  }

  @override
  String get championsRecordTitle => 'Champions record';

  @override
  String get championsRecordEmpty => 'No champion has been crowned yet.';

  @override
  String get championsLoadFailed => 'Couldn\'t load the champions.';

  @override
  String get championSpotlightCollapse => 'Hide the celebration';

  @override
  String get championSpotlightExpand => 'Show the celebration';

  @override
  String get championCongrats => 'Congratulations on the crown';

  @override
  String championCongratsLine(String month) {
    return '$month champion';
  }

  @override
  String championPrize(String prize) {
    return 'and the prize: $prize';
  }

  @override
  String get championShareButton => 'Share your crown';

  @override
  String championShareMessage(String month) {
    return 'I was crowned the $month champion on Nukhba 👑';
  }

  @override
  String get leaderboardMonthStarting =>
      'A new month has begun: everyone starts from zero, and the standings appear with the first scored match.';

  @override
  String get versusShort => 'vs';

  @override
  String get problemCodeCopy => 'Copy problem code';

  @override
  String get problemCodeCopied => 'Problem code copied';

  @override
  String get accountTitle => 'Account';

  @override
  String get publisherSectionTitle => 'Smart sports publisher';

  @override
  String get publisherSectionSubtitle =>
      'Goals and final results of the matches you pick: Facebook and Instagram are posted to automatically, X is prepared for you to share.';

  @override
  String get publisherTabMatches => 'Matches';

  @override
  String get publisherTabSettings => 'Settings';

  @override
  String get publisherTabAccounts => 'Accounts';

  @override
  String get publisherTabBadges => 'Club colours';

  @override
  String get publisherTabLog => 'Log';

  @override
  String get publisherTabPerformance => 'Performance';

  @override
  String get publisherModeOff =>
      'The server does not publish (NUKHBA_PUBLISHER=off).';

  @override
  String get publisherModeDryRun =>
      'Dry run: every post is prepared and kept for review, nothing is sent (NUKHBA_PUBLISHER=dry_run).';

  @override
  String get publisherModeOn =>
      'Live: the platforms switched on post for real (NUKHBA_PUBLISHER=on).';

  @override
  String get publisherUnavailable =>
      'The sports publisher is off on the server. Set NUKHBA_PUBLISHER to dry_run to try it, then to on to publish.';

  @override
  String get publisherLoadFailed => 'Couldn\'t load the sports publisher.';

  @override
  String get publisherReload => 'Try again';

  @override
  String get publisherPlatformFacebook => 'Facebook';

  @override
  String get publisherPlatformInstagram => 'Instagram';

  @override
  String get publisherPlatformX => 'X';

  @override
  String get publisherCancel => 'Cancel';

  @override
  String get publisherClose => 'Close';

  @override
  String get publisherMatchesHint =>
      'Only the matches you pick are posted about. A match picked after kickoff starts from its score at that moment.';

  @override
  String publisherMatchesCount(int covered, int total) {
    return '$covered of $total picked';
  }

  @override
  String get publisherMatchesEmpty => 'No matches in the next three days.';

  @override
  String get publisherMatchesNoneCovered => 'No match picked yet.';

  @override
  String get publisherFilterAll => 'All';

  @override
  String get publisherFilterCovered => 'Picked';

  @override
  String get publisherFilterAttention => 'Needs you';

  @override
  String publisherCoverOn(String match) {
    return 'Covering $match';
  }

  @override
  String publisherCoverOff(String match) {
    return 'Stopped covering $match';
  }

  @override
  String get publisherSettingsHint =>
      'Every platform stays off until you switch it on. Each card is saved by its own button.';

  @override
  String get publisherFacebookNote =>
      'Posted to the Facebook page by the server.';

  @override
  String get publisherInstagramNote =>
      'Posted by the server. A post cannot be corrected once out, so a goal waits longer for the VAR.';

  @override
  String get publisherXNote =>
      'Not posted automatically: the post (picture and words) is prepared, and you share it from the log.';

  @override
  String get publisherNotLinkedWarning =>
      'No account is linked on the server: nothing will be sent here.';

  @override
  String get publisherGoals => 'Goals';

  @override
  String get publisherGoalsAll => 'Every goal';

  @override
  String get publisherGoalsKey => 'Key goals only';

  @override
  String get publisherGoalsNone => 'No goals';

  @override
  String get publisherFinalResult => 'Final result';

  @override
  String get publisherHold => 'Wait before posting a goal';

  @override
  String get publisherGap => 'Least time between two goal posts';

  @override
  String get publisherDailyCap => 'Goal posts a day, at most';

  @override
  String publisherMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String publisherCapValue(int count) {
    return '$count a day';
  }

  @override
  String get publisherSave => 'Save';

  @override
  String publisherSaved(String platform) {
    return '$platform settings saved';
  }

  @override
  String publisherEnableTitle(String platform) {
    return 'Switch $platform on?';
  }

  @override
  String publisherEnableLiveBody(String platform) {
    return 'The server is publishing for real: the goals and results of the picked matches will go out on $platform at once.';
  }

  @override
  String get publisherEnableConfirm => 'Switch on';

  @override
  String get publisherAccountsHint =>
      'The tokens stay on the server; only whether each account is linked, and its name, show here.';

  @override
  String get publisherLinked => 'Linked';

  @override
  String get publisherNotLinked => 'Not linked';

  @override
  String publisherNeedsVars(String vars) {
    return 'Needs on the server: $vars';
  }

  @override
  String get publisherXAccount =>
      'Shared by hand from your phone; no account on the server.';

  @override
  String get publisherTestAccounts => 'Test the accounts';

  @override
  String publisherAccountOk(String name) {
    return 'Works: $name';
  }

  @override
  String publisherAccountFailed(String reason) {
    return 'Does not work: $reason';
  }

  @override
  String get publisherAccountsNone =>
      'The server holds no token for any platform.';

  @override
  String get publisherBadgesHint =>
      'No club crests: each club is a disc of its colour with its name. A club with no colour set is drawn in navy.';

  @override
  String get publisherBadgeTeam => 'Club';

  @override
  String get publisherBadgeSearch => 'Search for a club';

  @override
  String get publisherBadgeSuggested =>
      'Clubs of the picked matches with no colour yet:';

  @override
  String get publisherBadgeNoTeam => 'No club by that name.';

  @override
  String get publisherBadgeColour => 'Colour (#RRGGBB)';

  @override
  String get publisherBadgeLabel => 'Words on the disc (optional)';

  @override
  String get publisherBadgeSave => 'Save the badge';

  @override
  String publisherBadgeSaved(String team) {
    return '$team badge saved';
  }

  @override
  String get publisherBadgePickTeam => 'Pick the club first.';

  @override
  String get publisherBadgeColourInvalid =>
      'Write the colour like this: #1978D1';

  @override
  String get publisherBadgeLabelInvalid =>
      'The words on the disc are 24 letters at most.';

  @override
  String get publisherBadgesSet => 'Clubs set';

  @override
  String get publisherBadgesEmpty => 'No club colour set yet.';

  @override
  String get publisherBadgeEdit => 'Edit';

  @override
  String get publisherLogEmpty => 'No posts yet.';

  @override
  String get publisherKindGoal => 'Goal';

  @override
  String get publisherKindFinal => 'Final result';

  @override
  String get publisherKindCorrection => 'Correction';

  @override
  String get publisherStateQueued => 'Queued';

  @override
  String get publisherStatePublished => 'Published';

  @override
  String get publisherStateDryRun => 'Dry run (not sent)';

  @override
  String get publisherStateReadyToShare => 'Ready to share';

  @override
  String get publisherStateShared => 'Shared';

  @override
  String get publisherStateFailed => 'Failed';

  @override
  String get publisherStateUncertain => 'Uncertain';

  @override
  String get publisherStateSkipped => 'Skipped (daily cap)';

  @override
  String get publisherStateCancelled => 'Cancelled';

  @override
  String publisherCreatedAt(String time) {
    return 'Prepared $time';
  }

  @override
  String publisherPublishedAt(String time) {
    return 'Out $time';
  }

  @override
  String publisherAttempts(int count) {
    return 'Attempts: $count';
  }

  @override
  String publisherError(String error) {
    return 'Error: $error';
  }

  @override
  String get publisherUncertainNote =>
      'The connection broke after the request reached the platform: this post may already be out. Check the page before trying again.';

  @override
  String get publisherPreview => 'Preview the picture';

  @override
  String get publisherCardMissing => 'This post has no picture.';

  @override
  String get publisherCopyText => 'Copy the words';

  @override
  String get publisherCopied => 'Words copied';

  @override
  String get publisherShareX => 'Share on X';

  @override
  String get publisherMarkShared => 'Shared';

  @override
  String get publisherShareFailed => 'Couldn\'t open sharing. Try again.';

  @override
  String get publisherRetryPost => 'Try again';

  @override
  String get publisherCancelPost => 'Cancel the post';

  @override
  String get publisherUncertainTitle => 'It may already be out';

  @override
  String publisherUncertainBody(String platform) {
    return 'The connection broke after the request reached $platform, so the post may already be there. Open the page and check first, or it may go out twice.';
  }

  @override
  String get publisherUncertainConfirm => 'Checked, try again';

  @override
  String get publisherCancelTitle => 'Cancel the post?';

  @override
  String get publisherCancelBody => 'This post will never be sent.';

  @override
  String get publisherCancelConfirm => 'Cancel it';

  @override
  String get publisherRetried => 'The post is back in the queue';

  @override
  String get publisherCancelled => 'The post is cancelled';

  @override
  String get publisherMarkedShared => 'Marked as shared';

  @override
  String get publisherPerformanceHint =>
      'Each post is read once, a day after it went out (Facebook and Instagram), among the latest posts of the log.';

  @override
  String publisherPublishedCount(int count) {
    return 'Published: $count';
  }

  @override
  String publisherMetricsWaiting(int count) {
    return 'Not read yet: $count';
  }

  @override
  String publisherSharedCount(int count) {
    return 'Shared by hand: $count. X numbers are not read.';
  }

  @override
  String get publisherReach => 'Reach';

  @override
  String get publisherReactions => 'Reactions';

  @override
  String get publisherComments => 'Comments';

  @override
  String get publisherShares => 'Shares';

  @override
  String get publisherTopPosts => 'Most engaging';

  @override
  String get publisherPerformanceEmpty => 'No post has been read yet.';
}
