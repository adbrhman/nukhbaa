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

  /// `PUT /me/display-name` — renames the current user.
  Future<Result<MeResponseDto>> updateDisplayName(String displayName) {
    return _transport.putObject<MeResponseDto>(
      '/me/display-name',
      body: {'display_name': displayName},
      parse: MeResponseDto.fromJson,
    );
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
}
