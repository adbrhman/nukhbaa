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
  String get displayNameHint => 'Your name, shown to others';

  @override
  String get displayNameRequired => 'Please enter your name.';

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
  String get rulesCorrectPrediction => 'Correct prediction: 3 points';

  @override
  String get rulesWrongPrediction => 'Wrong prediction: 0 points';

  @override
  String get rulesDoubleMatch => 'Match picked as double: 6 points';

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
  String get adminDashboard => 'Admin dashboard';

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
    return 'in ${days}d';
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
  String get adminDailyDoublesTab => 'Daily Doubles';

  @override
  String get adminLeaderboardsTab => 'Leaderboards';

  @override
  String get adminCompetitionsTab => 'Competitions';

  @override
  String get adminTeamsTab => 'Teams';

  @override
  String get adminSocialTab => 'Social';

  @override
  String get adminNotificationsTab => 'Notifications';

  @override
  String get adminReportsAnalyticsTab => 'Reports & Analytics';

  @override
  String get adminSystemHealthTab => 'System Health';

  @override
  String get adminRolesPermissionsTab => 'Roles & Permissions';

  @override
  String get adminSettingsTab => 'Settings';

  @override
  String get adminSectionComingSoon =>
      'This section is under development — it will be enabled in a later batch.';

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
  String get notificationsMarkAsRead => 'Mark as read';

  @override
  String get adminAddMatchSectionTitle =>
      'Register a match and add it to a round';

  @override
  String get adminSelectSeasonLabel => 'Select season';

  @override
  String get adminSelectRoundLabel => 'Select round';

  @override
  String get adminNoSeasonsHint => 'This competition has no seasons.';

  @override
  String get adminNoRoundsHint =>
      'This season has no rounds. Open a round first in the Rounds tab.';

  @override
  String get adminSelectFixtureLabel => 'Select fixture';

  @override
  String get adminNoFixturesHint => 'This round has no fixtures.';

  @override
  String get adminFixtureIncompleteDataLabel => 'Fixture with incomplete data';

  @override
  String adminRoundOptionLabel(int sequence, String status) {
    return 'Round $sequence — $status';
  }

  @override
  String get adminAddMatchButton => 'Register match and add to round';

  @override
  String adminAddMatchSuccess(String home, String away) {
    return 'Added $home vs $away to the season.';
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
}
