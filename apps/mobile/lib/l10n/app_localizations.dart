import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Nukhba'**
  String get appTitle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @markNotificationRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markNotificationRead;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your email and password to continue.'**
  String get signInSubtitle;

  /// No description provided for @signUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account to start playing Nukhba.'**
  String get signUpSubtitle;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get emailHint;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email.'**
  String get emailRequired;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password.'**
  String get passwordRequired;

  /// No description provided for @toggleToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get toggleToSignIn;

  /// No description provided for @toggleToRegister.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get toggleToRegister;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Football prediction platform'**
  String get tagline;

  /// No description provided for @authTabSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authTabSignIn;

  /// No description provided for @authTabRegister.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get authTabRegister;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @confirmPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password.'**
  String get confirmPasswordRequired;

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get passwordMismatch;

  /// No description provided for @rulesTitle.
  ///
  /// In en, this message translates to:
  /// **'How to play?'**
  String get rulesTitle;

  /// No description provided for @rulesTagline.
  ///
  /// In en, this message translates to:
  /// **'Predict, compete, top the table, be Nukhba.'**
  String get rulesTagline;

  /// No description provided for @rulesPredictMajorLeagues.
  ///
  /// In en, this message translates to:
  /// **'Predict matches from the major leagues'**
  String get rulesPredictMajorLeagues;

  /// No description provided for @rulesCorrectPrediction.
  ///
  /// In en, this message translates to:
  /// **'Correct prediction: 3 points'**
  String get rulesCorrectPrediction;

  /// No description provided for @rulesWrongPrediction.
  ///
  /// In en, this message translates to:
  /// **'Wrong prediction: 0 points'**
  String get rulesWrongPrediction;

  /// No description provided for @rulesDoubleMatch.
  ///
  /// In en, this message translates to:
  /// **'Match picked as double: 6 points'**
  String get rulesDoubleMatch;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @signedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get signedIn;

  /// No description provided for @userId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get userId;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @browseCompetitions.
  ///
  /// In en, this message translates to:
  /// **'Browse competitions'**
  String get browseCompetitions;

  /// No description provided for @hallOfFame.
  ///
  /// In en, this message translates to:
  /// **'Hall of Fame'**
  String get hallOfFame;

  /// No description provided for @myPredictions.
  ///
  /// In en, this message translates to:
  /// **'My Predictions'**
  String get myPredictions;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create a group'**
  String get createGroup;

  /// No description provided for @joinGroup.
  ///
  /// In en, this message translates to:
  /// **'Join a group'**
  String get joinGroup;

  /// No description provided for @adminDashboard.
  ///
  /// In en, this message translates to:
  /// **'Admin dashboard'**
  String get adminDashboard;

  /// No description provided for @hallOfFameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody has earned any points yet.'**
  String get hallOfFameEmpty;

  /// Number of seasons a user has played, shown on the Hall of Fame leaderboard row.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No seasons played} =1{1 season played} other{{count} seasons played}}'**
  String hallOfFameSeasonsPlayed(int count);

  /// No description provided for @competitionSeasonsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This competition has no seasons yet.'**
  String get competitionSeasonsEmpty;

  /// Title of the season leaderboard screen.
  ///
  /// In en, this message translates to:
  /// **'{label} — Leaderboard'**
  String leaderboardTitle(String label);

  /// No description provided for @seasonLeaderboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No one has joined this season yet.'**
  String get seasonLeaderboardEmpty;

  /// Number of prediction entries counted toward a participant's leaderboard score.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No entries counted} =1{1 entry counted} other{{count} entries counted}}'**
  String leaderboardEntriesCounted(int count);

  /// Abbreviated points total, shown on leaderboard rows (e.g. Hall of Fame, season leaderboard).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 pts} =1{1 pt} other{{count} pts}}'**
  String pointsAbbreviated(int count);

  /// No description provided for @roundLeaderboardTab.
  ///
  /// In en, this message translates to:
  /// **'Round points'**
  String get roundLeaderboardTab;

  /// No description provided for @seasonLeaderboardTab.
  ///
  /// In en, this message translates to:
  /// **'Season points'**
  String get seasonLeaderboardTab;

  /// No description provided for @selectRoundLabel.
  ///
  /// In en, this message translates to:
  /// **'Select round'**
  String get selectRoundLabel;

  /// No description provided for @roundLeaderboardNoScoredRounds.
  ///
  /// In en, this message translates to:
  /// **'This season has no scored rounds yet.'**
  String get roundLeaderboardNoScoredRounds;

  /// No description provided for @roundLeaderboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody predicted this round.'**
  String get roundLeaderboardEmpty;

  /// No description provided for @roundKingLabel.
  ///
  /// In en, this message translates to:
  /// **'Round king'**
  String get roundKingLabel;

  /// No description provided for @groupLeaderboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No members of this group have joined the season yet.'**
  String get groupLeaderboardEmpty;

  /// No description provided for @competitions.
  ///
  /// In en, this message translates to:
  /// **'Competitions'**
  String get competitions;

  /// No description provided for @competitionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no competitions to browse yet.'**
  String get competitionsEmpty;

  /// No description provided for @visibilityPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get visibilityPublic;

  /// No description provided for @visibilityPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get visibilityPrivate;

  /// No description provided for @predictionHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have not submitted any predictions yet.'**
  String get predictionHistoryEmpty;

  /// One fixture's predicted scoreline within a submitted prediction history row.
  ///
  /// In en, this message translates to:
  /// **'{fixtureId}: {homeGoals} - {awayGoals}'**
  String predictionHistoryScoreLine(
    String fixtureId,
    int homeGoals,
    int awayGoals,
  );

  /// App bar title for a group's activity feed screen.
  ///
  /// In en, this message translates to:
  /// **'{groupName} Feed'**
  String groupFeedTitle(String groupName);

  /// No description provided for @groupFeedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No activity yet.'**
  String get groupFeedEmpty;

  /// No description provided for @activityRoundScored.
  ///
  /// In en, this message translates to:
  /// **'Round scored'**
  String get activityRoundScored;

  /// No description provided for @activityMemberJoined.
  ///
  /// In en, this message translates to:
  /// **'New member joined'**
  String get activityMemberJoined;

  /// Describes a member's rank change in the group activity feed.
  ///
  /// In en, this message translates to:
  /// **'Moved from #{oldRank} to #{newRank}'**
  String activityRankShift(int oldRank, int newRank);

  /// No description provided for @activityRankShiftUnknown.
  ///
  /// In en, this message translates to:
  /// **'Rank changed'**
  String get activityRankShiftUnknown;

  /// App bar title for the season rounds browse screen.
  ///
  /// In en, this message translates to:
  /// **'{seasonLabel} — Rounds'**
  String seasonRoundsTitle(String seasonLabel);

  /// Tooltip for the app bar action that navigates to the season leaderboard.
  ///
  /// In en, this message translates to:
  /// **'View leaderboard'**
  String get viewLeaderboardTooltip;

  /// Empty state message when a season has no rounds.
  ///
  /// In en, this message translates to:
  /// **'This season has no rounds yet.'**
  String get seasonRoundsEmpty;

  /// Title of a round list item, showing its 1-based sequence number.
  ///
  /// In en, this message translates to:
  /// **'Round {sequence}'**
  String roundItemTitle(int sequence);

  /// Subtitle of a round list item combining its humanised status and formatted prediction deadline.
  ///
  /// In en, this message translates to:
  /// **'{statusLabel} · Deadline {deadline}'**
  String roundDeadlineLine(String statusLabel, String deadline);

  /// Humanised label for a round in the open lifecycle status.
  ///
  /// In en, this message translates to:
  /// **'Open for predictions'**
  String get roundStatusOpen;

  /// Humanised label for a round in the locked lifecycle status.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get roundStatusLocked;

  /// Humanised label for a round in the scored lifecycle status.
  ///
  /// In en, this message translates to:
  /// **'Scored'**
  String get roundStatusScored;

  /// No description provided for @roundFixturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Round'**
  String get roundFixturesTitle;

  /// Round header status line combining the humanised status and the ruleset version applied to this round.
  ///
  /// In en, this message translates to:
  /// **'{statusLabel} · Rules v{rulesetVersion}'**
  String roundRulesLine(String statusLabel, int rulesetVersion);

  /// No description provided for @predictRoundButton.
  ///
  /// In en, this message translates to:
  /// **'Predict this round'**
  String get predictRoundButton;

  /// No description provided for @roundFixturesEmpty.
  ///
  /// In en, this message translates to:
  /// **'This round has no fixtures yet.'**
  String get roundFixturesEmpty;

  /// Title of a fixture list item, showing its stable fixture id.
  ///
  /// In en, this message translates to:
  /// **'Fixture {fixtureId}'**
  String fixtureItemTitle(String fixtureId);

  /// Title of a fixture list item when its schedule identity is known.
  ///
  /// In en, this message translates to:
  /// **'{home} vs {away}'**
  String fixtureVsTitle(String home, String away);

  /// App bar title on the prediction submit/amend screen.
  ///
  /// In en, this message translates to:
  /// **'Predict'**
  String get predictionTitle;

  /// Shown when a round is not open for predictions; status is the lowercase lifecycle label.
  ///
  /// In en, this message translates to:
  /// **'This round is {status}. Predictions are closed.'**
  String predictionClosedMessage(String status);

  /// No description provided for @predictionNotYetPredictableMessage.
  ///
  /// In en, this message translates to:
  /// **'You can predict this round once the earlier round is locked'**
  String get predictionNotYetPredictableMessage;

  /// Fallback error message for an untyped/unexpected client error.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get genericErrorMessage;

  /// Retry button label on a form error state.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgainButton;

  /// Banner shown when the caller already has a stored prediction for this round.
  ///
  /// In en, this message translates to:
  /// **'You have already submitted a prediction for this round. Editing and submitting again will update it.'**
  String get predictionAlreadySubmitted;

  /// Success banner after a prediction submit/amend succeeds.
  ///
  /// In en, this message translates to:
  /// **'Your prediction was saved.'**
  String get predictionSaved;

  /// Label on the prediction submit button.
  ///
  /// In en, this message translates to:
  /// **'Submit prediction'**
  String get submitPredictionButton;

  /// Tooltip/semantic label on the per-fixture double-selection star.
  ///
  /// In en, this message translates to:
  /// **'Double'**
  String get predictionDoubleLabel;

  /// Small label under a fixture that has already kicked off and can no longer be edited.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get predictionFixtureLockedLabel;

  /// Shown when every open fixture has a score but no double is selected yet.
  ///
  /// In en, this message translates to:
  /// **'Select exactly one open fixture as your double before submitting.'**
  String get predictionDoubleHint;

  /// Shown while at least one open fixture is missing a valid score.
  ///
  /// In en, this message translates to:
  /// **'Enter a score for every open fixture before submitting.'**
  String get predictionIncompleteHint;

  /// Shown instead of the form when every fixture in the round has already locked.
  ///
  /// In en, this message translates to:
  /// **'Every fixture in this round has already kicked off. There is nothing left to predict.'**
  String get predictionNoOpenFixturesMessage;

  /// No description provided for @matchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get matchesTitle;

  /// No description provided for @matchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No open matches right now.'**
  String get matchesEmpty;

  /// No description provided for @adminAuditLogTab.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get adminAuditLogTab;

  /// No description provided for @adminUsersTab.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminUsersTab;

  /// No description provided for @adminLedgerLookupTab.
  ///
  /// In en, this message translates to:
  /// **'Ledger Lookup'**
  String get adminLedgerLookupTab;

  /// No description provided for @adminAuditLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audit entries yet.'**
  String get adminAuditLogEmpty;

  /// No description provided for @adminReasonMandatoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (mandatory)'**
  String get adminReasonMandatoryLabel;

  /// No description provided for @adminSuspendButton.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get adminSuspendButton;

  /// No description provided for @adminReinstateButton.
  ///
  /// In en, this message translates to:
  /// **'Reinstate'**
  String get adminReinstateButton;

  /// No description provided for @adminUsersSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search by email'**
  String get adminUsersSearchLabel;

  /// No description provided for @adminUsersEmptyResults.
  ///
  /// In en, this message translates to:
  /// **'No matching users.'**
  String get adminUsersEmptyResults;

  /// Result line after a suspend/reinstate action.
  ///
  /// In en, this message translates to:
  /// **'{userId} is now {status}'**
  String adminSanctionResultMessage(String userId, String status);

  /// No description provided for @adminParticipantIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Participant ID'**
  String get adminParticipantIdLabel;

  /// No description provided for @adminLookUpButton.
  ///
  /// In en, this message translates to:
  /// **'Look up'**
  String get adminLookUpButton;

  /// No description provided for @adminFixturesTab.
  ///
  /// In en, this message translates to:
  /// **'Fixture Identity'**
  String get adminFixturesTab;

  /// No description provided for @adminFixtureIdOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Fixture ID (correction only — leave empty to register)'**
  String get adminFixtureIdOptionalLabel;

  /// No description provided for @adminSelectCompetitionLabel.
  ///
  /// In en, this message translates to:
  /// **'Select league (competitions)'**
  String get adminSelectCompetitionLabel;

  /// No description provided for @adminHomeTeamLabel.
  ///
  /// In en, this message translates to:
  /// **'Home team'**
  String get adminHomeTeamLabel;

  /// No description provided for @adminAwayTeamLabel.
  ///
  /// In en, this message translates to:
  /// **'Away team'**
  String get adminAwayTeamLabel;

  /// No description provided for @adminPickKickoffButton.
  ///
  /// In en, this message translates to:
  /// **'Pick kickoff time'**
  String get adminPickKickoffButton;

  /// No description provided for @adminRegisterFixtureButton.
  ///
  /// In en, this message translates to:
  /// **'Register fixture'**
  String get adminRegisterFixtureButton;

  /// No description provided for @adminCorrectFixtureButton.
  ///
  /// In en, this message translates to:
  /// **'Correct fixture'**
  String get adminCorrectFixtureButton;

  /// No description provided for @adminRoundsTab.
  ///
  /// In en, this message translates to:
  /// **'Rounds'**
  String get adminRoundsTab;

  /// No description provided for @adminResultsScoringTab.
  ///
  /// In en, this message translates to:
  /// **'Results & Scoring'**
  String get adminResultsScoringTab;

  /// No description provided for @adminOpenRoundSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Open a new round'**
  String get adminOpenRoundSectionTitle;

  /// No description provided for @adminSeasonIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Season ID'**
  String get adminSeasonIdLabel;

  /// No description provided for @adminSequenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Round sequence'**
  String get adminSequenceLabel;

  /// No description provided for @adminPickDeadlineButton.
  ///
  /// In en, this message translates to:
  /// **'Pick prediction deadline'**
  String get adminPickDeadlineButton;

  /// No description provided for @adminOpenRoundButton.
  ///
  /// In en, this message translates to:
  /// **'Open round'**
  String get adminOpenRoundButton;

  /// No description provided for @adminLockRoundButton.
  ///
  /// In en, this message translates to:
  /// **'Lock round'**
  String get adminLockRoundButton;

  /// No description provided for @adminLinkFixtureSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Link a fixture to a round'**
  String get adminLinkFixtureSectionTitle;

  /// No description provided for @adminRoundIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Round ID'**
  String get adminRoundIdLabel;

  /// No description provided for @adminFixtureIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Fixture ID'**
  String get adminFixtureIdLabel;

  /// No description provided for @adminDisplayOrderLabel.
  ///
  /// In en, this message translates to:
  /// **'Display order'**
  String get adminDisplayOrderLabel;

  /// No description provided for @adminLinkFixtureButton.
  ///
  /// In en, this message translates to:
  /// **'Link fixture to round'**
  String get adminLinkFixtureButton;

  /// No description provided for @adminScoringTab.
  ///
  /// In en, this message translates to:
  /// **'Results & Scoring'**
  String get adminScoringTab;

  /// No description provided for @adminRecordResultSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Record fixture result'**
  String get adminRecordResultSectionTitle;

  /// No description provided for @adminHomeGoalsLabel.
  ///
  /// In en, this message translates to:
  /// **'Home goals'**
  String get adminHomeGoalsLabel;

  /// No description provided for @adminAwayGoalsLabel.
  ///
  /// In en, this message translates to:
  /// **'Away goals'**
  String get adminAwayGoalsLabel;

  /// No description provided for @adminRecordResultButton.
  ///
  /// In en, this message translates to:
  /// **'Record result'**
  String get adminRecordResultButton;

  /// No description provided for @adminScoreRoundSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Score round'**
  String get adminScoreRoundSectionTitle;

  /// No description provided for @adminScoreRoundButton.
  ///
  /// In en, this message translates to:
  /// **'Score round'**
  String get adminScoreRoundButton;

  /// No description provided for @adminPostToLedgerButton.
  ///
  /// In en, this message translates to:
  /// **'Post to ledger'**
  String get adminPostToLedgerButton;

  /// No description provided for @adminPostToLedgerSuccessLabel.
  ///
  /// In en, this message translates to:
  /// **'Posted, new entries'**
  String get adminPostToLedgerSuccessLabel;

  /// No description provided for @adminRoundScoresSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Round participant scores'**
  String get adminRoundScoresSectionTitle;

  /// No description provided for @adminViewScoresButton.
  ///
  /// In en, this message translates to:
  /// **'View scores'**
  String get adminViewScoresButton;

  /// No description provided for @adminTotalPointsLabel.
  ///
  /// In en, this message translates to:
  /// **'Total points'**
  String get adminTotalPointsLabel;

  /// No description provided for @adminRoundReportSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Round report'**
  String get adminRoundReportSectionTitle;

  /// No description provided for @adminViewRoundReportButton.
  ///
  /// In en, this message translates to:
  /// **'View round report'**
  String get adminViewRoundReportButton;

  /// No description provided for @adminRoundReportRankLabel.
  ///
  /// In en, this message translates to:
  /// **'Rank'**
  String get adminRoundReportRankLabel;

  /// No description provided for @adminRoundReportShareButton.
  ///
  /// In en, this message translates to:
  /// **'Copy to share'**
  String get adminRoundReportShareButton;

  /// No description provided for @adminRoundReportCopiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Copied — share it on WhatsApp'**
  String get adminRoundReportCopiedMessage;

  /// No description provided for @adminRoundReportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No participants in this round'**
  String get adminRoundReportEmpty;

  /// No description provided for @adminRoundReportSectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No report for this round yet'**
  String get adminRoundReportSectionEmpty;

  /// No description provided for @createGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get createGroupTitle;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// No description provided for @createGroupButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createGroupButton;

  /// No description provided for @joinGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Join Group'**
  String get joinGroupTitle;

  /// No description provided for @inviteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCodeLabel;

  /// No description provided for @joinGroupButton.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinGroupButton;

  /// No description provided for @ledgerTitle.
  ///
  /// In en, this message translates to:
  /// **'My Points'**
  String get ledgerTitle;

  /// No description provided for @ledgerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No points movements yet.'**
  String get ledgerEmpty;

  /// Count of point movements shown below the balance on the ledger screen.
  ///
  /// In en, this message translates to:
  /// **'{count} movements counted'**
  String ledgerEntryCount(int count);

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have no notifications yet.'**
  String get notificationsEmpty;

  /// No description provided for @notificationRoundScored.
  ///
  /// In en, this message translates to:
  /// **'A round you predicted was scored'**
  String get notificationRoundScored;

  /// No description provided for @notificationGroupMemberJoined.
  ///
  /// In en, this message translates to:
  /// **'Someone joined your group'**
  String get notificationGroupMemberJoined;

  /// No description provided for @notificationReactionReceived.
  ///
  /// In en, this message translates to:
  /// **'You received a reaction'**
  String get notificationReactionReceived;

  /// No description provided for @notificationsMarkAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get notificationsMarkAsRead;

  /// No description provided for @adminAddMatchSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Register a match and add it to a round'**
  String get adminAddMatchSectionTitle;

  /// No description provided for @adminSelectSeasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Select season'**
  String get adminSelectSeasonLabel;

  /// No description provided for @adminSelectRoundLabel.
  ///
  /// In en, this message translates to:
  /// **'Select round'**
  String get adminSelectRoundLabel;

  /// No description provided for @adminNoSeasonsHint.
  ///
  /// In en, this message translates to:
  /// **'This competition has no seasons.'**
  String get adminNoSeasonsHint;

  /// No description provided for @adminNoRoundsHint.
  ///
  /// In en, this message translates to:
  /// **'This season has no rounds. Open a round first in the Rounds tab.'**
  String get adminNoRoundsHint;

  /// No description provided for @adminSelectFixtureLabel.
  ///
  /// In en, this message translates to:
  /// **'Select fixture'**
  String get adminSelectFixtureLabel;

  /// No description provided for @adminNoFixturesHint.
  ///
  /// In en, this message translates to:
  /// **'This round has no fixtures.'**
  String get adminNoFixturesHint;

  /// No description provided for @adminFixtureIncompleteDataLabel.
  ///
  /// In en, this message translates to:
  /// **'Fixture with incomplete data'**
  String get adminFixtureIncompleteDataLabel;

  /// No description provided for @adminRoundOptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Round {sequence} — {status}'**
  String adminRoundOptionLabel(int sequence, String status);

  /// No description provided for @adminAddMatchButton.
  ///
  /// In en, this message translates to:
  /// **'Register match and add to round'**
  String get adminAddMatchButton;

  /// No description provided for @adminAddMatchSuccess.
  ///
  /// In en, this message translates to:
  /// **'Added {home} vs {away} to round {sequence}.'**
  String adminAddMatchSuccess(String home, String away, int sequence);

  /// No description provided for @adminSelectRoundFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a round first.'**
  String get adminSelectRoundFirst;

  /// No description provided for @adminManageRoundsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage rounds'**
  String get adminManageRoundsSectionTitle;

  /// No description provided for @adminExistingRoundsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This season has no rounds yet.'**
  String get adminExistingRoundsEmpty;

  /// No description provided for @adminExistingFixturesSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Fixtures in this round'**
  String get adminExistingFixturesSectionTitle;

  /// No description provided for @adminRemoveFixtureTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove this fixture from the round'**
  String get adminRemoveFixtureTooltip;

  /// No description provided for @adminRemoveFixtureConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove fixture?'**
  String get adminRemoveFixtureConfirmTitle;

  /// No description provided for @adminRemoveFixtureConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove {home} vs {away} from this round? This cannot be undone.'**
  String adminRemoveFixtureConfirmMessage(String home, String away);

  /// No description provided for @adminRemoveFixtureConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get adminRemoveFixtureConfirmButton;

  /// No description provided for @adminRemoveFixtureCancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get adminRemoveFixtureCancelButton;

  /// No description provided for @adminRemoveFixtureSuccess.
  ///
  /// In en, this message translates to:
  /// **'Fixture removed from the round.'**
  String get adminRemoveFixtureSuccess;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
