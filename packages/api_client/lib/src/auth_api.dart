import 'dart:typed_data';

import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

final class AuthApi {
  const AuthApi(this._transport);
  final ApiTransport _transport;

  Future<Result<AuthResponseDto>> login({
    required String email,
    required String password,
  }) {
    return _transport.postObject<AuthResponseDto>(
      '/auth/login',
      body: LoginRequestDto(email: email, password: password).toJson(),
      parse: AuthResponseDto.fromJson,
    );
  }

  Future<Result<AuthResponseDto>> register({
    required String displayName,
    required String email,
    required String password,
  }) {
    return _transport.postObject<AuthResponseDto>(
      '/auth/register',
      body: RegisterRequestDto(
        displayName: displayName,
        email: email,
        password: password,
      ).toJson(),
      parse: AuthResponseDto.fromJson,
    );
  }

  /// Renews a session from its [refreshToken] via `POST /auth/refresh`.
  Future<Result<AuthResponseDto>> refresh({required String refreshToken}) {
    return _transport.postObject<AuthResponseDto>(
      '/auth/refresh',
      body: RefreshSessionRequestDto(refreshToken: refreshToken).toJson(),
      parse: AuthResponseDto.fromJson,
    );
  }

  /// Exchanges a Google [idToken] for a session via `POST /auth/google`.
  Future<Result<AuthResponseDto>> signInWithGoogle({required String idToken}) {
    return _transport.postObject<AuthResponseDto>(
      '/auth/google',
      body: GoogleSignInRequestDto(idToken: idToken).toJson(),
      parse: AuthResponseDto.fromJson,
    );
  }

  Future<Result<PasswordResetResponseDto>> requestPasswordReset({
    required String email,
  }) {
    return _transport.postObject<PasswordResetResponseDto>(
      '/auth/password-reset/request',
      body: PasswordResetRequestDto(email: email).toJson(),
      parse: PasswordResetResponseDto.fromJson,
    );
  }

  Future<Result<PasswordResetResponseDto>> updatePassword({
    required String recoveryToken,
    required String password,
  }) {
    return _transport.postObjectWithBearerToken<PasswordResetResponseDto>(
      '/auth/password-reset/update',
      bearerToken: recoveryToken,
      body: UpdatePasswordRequestDto(password: password).toJson(),
      parse: PasswordResetResponseDto.fromJson,
    );
  }

  Future<Result<MeResponseDto>> me() {
    return _transport.getObject<MeResponseDto>(
      '/me',
      parse: MeResponseDto.fromJson,
    );
  }

  /// `POST /me/avatar` — sets or replaces the caller's profile picture.
  ///
  /// Returns the same `MeResponseDto` as [me], so the caller refreshes its
  /// whole identity -- `avatar_url` included -- from this one response rather
  /// than making a second call to discover what changed.
  Future<Result<MeResponseDto>> setAvatar({
    required List<int> bytes,
    required String contentType,
  }) {
    return _transport.postBytes(
      '/me/avatar',
      bytes: bytes,
      contentType: contentType,
      parse: MeResponseDto.fromJson,
    );
  }

  /// `PUT /me/display-name` — the one-time choice of a display name, for
  /// an account that never chose one.
  Future<Result<MeResponseDto>> chooseDisplayName({
    required String displayName,
  }) {
    return _transport.putObject<MeResponseDto>(
      '/me/display-name',
      body: DisplayNameRequestDto(displayName: displayName).toJson(),
      parse: MeResponseDto.fromJson,
    );
  }

  /// `GET /users/{id}/avatar` — the stored picture's bytes, for any user.
  ///
  /// [avatarPath] is the server-relative URL the server already built and put
  /// on the DTO (`avatar_url`), passed back verbatim rather than rebuilt
  /// here: the route shape is the server's to own, and the `?v=` version in
  /// it is what makes a replaced picture a different resource.
  ///
  /// `Ok(null)` when the user has no picture — the caller draws their initial.
  Future<Result<Uint8List?>> avatarBytes(String avatarPath) {
    return _transport.getBytes(avatarPath);
  }

  /// `DELETE /me/avatar` — removes the caller's picture, if any.
  Future<Result<MeResponseDto>> removeAvatar() {
    return _transport.deleteObject('/me/avatar', parse: MeResponseDto.fromJson);
  }

  /// `POST /me/device-token` — registers this device's FCM token for push
  /// delivery. Safe to call on every app start and on every token refresh:
  /// the server upserts by token, so a repeat is a re-confirmation rather
  /// than a duplicate.
  Future<Result<DeviceTokenAckDto>> registerDeviceToken({
    required String token,
    required String platform,
  }) {
    return _transport.postObject<DeviceTokenAckDto>(
      '/me/device-token',
      body: DeviceTokenRegistrationRequestDto(
        token: token,
        platform: platform,
      ).toJson(),
      parse: DeviceTokenAckDto.fromJson,
    );
  }

  /// `POST /me/time-zone` — reports this device's current offset from UTC, so
  /// a later notification can respect the reader's own clock.
  ///
  /// Safe to call on every app start, and meant to be: an offset carries no
  /// daylight-saving rule, so the freshest reading is the only correct one.
  /// Unlike [registerDeviceToken] this is not Android-only — it is just as
  /// true on the web build.
  Future<Result<TimeZoneAckDto>> reportTimeZoneOffset({
    required int offsetMinutes,
  }) {
    return _transport.postObject<TimeZoneAckDto>(
      '/me/time-zone',
      body: TimeZoneReportRequestDto(utcOffsetMinutes: offsetMinutes).toJson(),
      parse: TimeZoneAckDto.fromJson,
    );
  }

  /// `GET /me/streak` — the caller's run of completed match days.
  ///
  /// Counted server-side on every call, so there is nothing to cache here
  /// and nothing that can drift from the record.
  Future<Result<MyStreakDto>> myStreak() {
    return _transport.getObject<MyStreakDto>(
      '/me/streak',
      parse: MyStreakDto.fromJson,
    );
  }

  /// `POST /me/push-opened` -- the caller tapped a push carrying [link]
  /// (plan P3-8). Fire-and-forget from the app: the answer is never waited
  /// on by anything the user sees.
  Future<Result<PushOpenedAckDto>> reportPushOpened({required String link}) {
    return _transport.postObject<PushOpenedAckDto>(
      '/me/push-opened',
      body: <String, Object?>{'link': link},
      parse: PushOpenedAckDto.fromJson,
    );
  }

  /// `POST /me/frame-report` -- one app session's frame counts (migration
  /// 0070). Fire-and-forget from the app: nothing the user sees waits on it.
  Future<Result<FrameReportAckDto>> reportFrames(FrameReportDto report) {
    return _transport.postObject<FrameReportAckDto>(
      '/me/frame-report',
      body: report.toJson(),
      parse: FrameReportAckDto.fromJson,
    );
  }

  /// `GET /me/insights` -- accuracy, patterns and last week's recap (plan
  /// P4-4), computed server-side on every call.
  Future<Result<InsightsDto>> myInsights() {
    return _transport.getObject<InsightsDto>(
      '/me/insights',
      parse: InsightsDto.fromJson,
    );
  }

  /// `GET /me/daily-challenge` -- how much of today's match day the caller
  /// has covered.
  ///
  /// Counts only: the day's fixtures already arrive with the season feed,
  /// so a card that draws "2 of 3" never fetches them twice. The day is the
  /// server's Riyadh day, never re-derived here.
  Future<Result<MyDailyChallengeDto>> myDailyChallenge() {
    return _transport.getObject<MyDailyChallengeDto>(
      '/me/daily-challenge',
      parse: MyDailyChallengeDto.fromJson,
    );
  }

  /// `GET /me/weekly-league` -- the caller's group in the Riyadh weekly
  /// league that is open now, ranked.
  ///
  /// Computed on every call from the same points the monthly board reads;
  /// nothing weekly is cached here, so there is nothing to invalidate.
  Future<Result<MyWeeklyLeagueDto>> myWeeklyLeague() {
    return _transport.getObject<MyWeeklyLeagueDto>(
      '/me/weekly-league',
      parse: MyWeeklyLeagueDto.fromJson,
    );
  }

  /// `GET /me/badges` -- every catalog badge with the caller's progress and
  /// the moment each held badge was granted.
  ///
  /// Read-only: badges are granted by the server on its own schedule, and
  /// nothing the client sends can grant one.
  Future<Result<MyBadgesDto>> myBadges() {
    return _transport.getObject<MyBadgesDto>(
      '/me/badges',
      parse: MyBadgesDto.fromJson,
    );
  }

  /// `GET /me/notification-preferences` -- the caller's notification
  /// switches; a caller who never changed anything reads the defaults,
  /// all on.
  Future<Result<NotificationPreferencesDto>> myNotificationPreferences() {
    return _transport.getObject<NotificationPreferencesDto>(
      '/me/notification-preferences',
      parse: NotificationPreferencesDto.fromJson,
    );
  }

  /// `PUT /me/notification-preferences` -- stores the caller's switches and
  /// answers what the server stored, which is what the page then shows.
  ///
  /// Only the switches given are sent; the server keeps the others as
  /// stored.
  Future<Result<NotificationPreferencesDto>> updateNotificationPreferences({
    bool? predictionReminder,
    bool? preMatch,
    bool? streakSaver,
    bool? overtaken,
  }) {
    return _transport.putObject<NotificationPreferencesDto>(
      '/me/notification-preferences',
      body: <String, Object?>{
        'schema_version': NotificationPreferencesDto.currentSchemaVersion,
        if (predictionReminder != null)
          'prediction_reminder': predictionReminder,
        if (preMatch != null) 'pre_match': preMatch,
        if (streakSaver != null) 'streak_saver': streakSaver,
        if (overtaken != null) 'overtaken': overtaken,
      },
      parse: NotificationPreferencesDto.fromJson,
    );
  }

  /// `GET /me/favorite-teams` -- the ids of the teams the caller follows.
  Future<Result<FavoriteTeamsDto>> myFavoriteTeams() {
    return _transport.getObject<FavoriteTeamsDto>(
      '/me/favorite-teams',
      parse: FavoriteTeamsDto.fromJson,
    );
  }

  /// `PUT /me/favorite-teams` -- replaces the whole set (at most three) and
  /// answers what the server stored, which is what the page then shows.
  Future<Result<FavoriteTeamsDto>> updateFavoriteTeams({
    required List<String> teamIds,
  }) {
    return _transport.putObject<FavoriteTeamsDto>(
      '/me/favorite-teams',
      body: FavoriteTeamsDto(teamIds: teamIds).toJson(),
      parse: FavoriteTeamsDto.fromJson,
    );
  }
}
