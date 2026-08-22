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

  /// `PUT /me/display-name` — renames the current user.
  Future<Result<MeResponseDto>> updateDisplayName(String displayName) {
    return _transport.putObject<MeResponseDto>(
      '/me/display-name',
      body: {'display_name': displayName},
      parse: MeResponseDto.fromJson,
    );
  }
}
