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
}
