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
  String get toggleToSignIn => 'Already have an account? Sign in';

  @override
  String get toggleToRegister => 'New here? Create an account';

  @override
  String get tagline => 'Football prediction platform';

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
  String get predictionTitle => 'Predict';

  @override
  String predictionClosedMessage(String status) {
    return 'This round is $status. Predictions are closed.';
  }

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
  String get adminParticipantIdLabel => 'Participant ID';

  @override
  String get adminLookUpButton => 'Look up';

  @override
  String get adminFixturesTab => 'Fixture Identity';

  @override
  String get adminFixtureIdOptionalLabel =>
      'Fixture ID (correction only — leave empty to register)';

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
}
