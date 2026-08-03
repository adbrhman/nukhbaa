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
}
