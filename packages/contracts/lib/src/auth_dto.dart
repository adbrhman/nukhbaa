/// Wire shapes for the email/password authentication endpoints
/// (POST /auth/login and POST /auth/register).
///
/// These DTOs are a pure data contract shared verbatim by client and server;
/// they depend on nothing (Application ADR, Section 3). Every payload carries a
/// schema version so client and server evolve safely (API ADR, Section 4).
///
/// The access token returned here is a real Supabase JWT (issued by Supabase
/// Auth / GoTrue), which the backend's existing bearerAuth middleware verifies
/// unchanged via JWKS — no new verification path is introduced.
library;

/// Request body for POST /auth/login.
final class LoginRequestDto {
  /// Creates a login request.
  const LoginRequestDto({required this.email, required this.password});

  /// Deserializes from a JSON map.
  factory LoginRequestDto.fromJson(Map<String, dynamic> json) {
    return LoginRequestDto(
      email: json['email']! as String,
      password: json['password']! as String,
    );
  }

  /// The account email.
  final String email;

  /// The account password (never logged; forwarded to Supabase Auth only).
  final String password;

  /// Serializes to a JSON-encodable map.
  Map<String, dynamic> toJson() => {'email': email, 'password': password};

  @override
  bool operator ==(Object other) =>
      other is LoginRequestDto &&
      other.email == email &&
      other.password == password;

  @override
  int get hashCode => Object.hash(email, password);
}

/// Request body for POST /auth/register.
final class RegisterRequestDto {
  /// Creates a registration request.
  const RegisterRequestDto({required this.email, required this.password});

  /// Deserializes from a JSON map.
  factory RegisterRequestDto.fromJson(Map<String, dynamic> json) {
    return RegisterRequestDto(
      email: json['email']! as String,
      password: json['password']! as String,
    );
  }

  /// The account email.
  final String email;

  /// The chosen password (never logged; forwarded to Supabase Auth only).
  final String password;

  /// Serializes to a JSON-encodable map.
  Map<String, dynamic> toJson() => {'email': email, 'password': password};

  @override
  bool operator ==(Object other) =>
      other is RegisterRequestDto &&
      other.email == email &&
      other.password == password;

  @override
  int get hashCode => Object.hash(email, password);
}

/// Response body of POST /auth/login and POST /auth/register.
///
/// Carries the Supabase access token (a JWT the backend already knows how to
/// verify) plus the minimal identity the client needs to proceed. When
/// [accessToken] is null the account was created but requires email
/// confirmation before a session exists (Supabase "confirm email" projects);
/// the client shows a "check your email" message rather than logging in.
final class AuthResponseDto {
  /// Creates an auth response.
  const AuthResponseDto({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.email,
    this.emailConfirmationRequired = false,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory AuthResponseDto.fromJson(Map<String, dynamic> json) {
    return AuthResponseDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      userId: json['user_id'] as String?,
      email: json['email'] as String?,
      emailConfirmationRequired:
          (json['email_confirmation_required'] as bool?) ?? false,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The Supabase access token (JWT), or null when email confirmation is
  /// pending and no session was issued.
  final String? accessToken;

  /// The Supabase refresh token, or null when no session was issued.
  final String? refreshToken;

  /// The authenticated user's id (UUID string), when known.
  final String? userId;

  /// The authenticated user's email, when known.
  final String? email;

  /// Whether the account was created but a session is withheld pending email
  /// confirmation.
  final bool emailConfirmationRequired;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'email': email,
    'email_confirmation_required': emailConfirmationRequired,
  };

  @override
  bool operator ==(Object other) =>
      other is AuthResponseDto &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.userId == userId &&
      other.email == email &&
      other.emailConfirmationRequired == emailConfirmationRequired &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    accessToken,
    refreshToken,
    userId,
    email,
    emailConfirmationRequired,
    schemaVersion,
  );
}
