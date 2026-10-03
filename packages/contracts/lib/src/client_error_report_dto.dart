/// Body of `POST /errors/report` (migration 0087): one unexpected error
/// the app caught, signed in or not.
final class ClientErrorReportDto {
  /// Creates the report.
  const ClientErrorReportDto({
    required this.source,
    required this.errorType,
    required this.message,
    required this.build,
    this.errorCode,
    this.stack,
    this.route,
    this.device,
    this.os,
    this.browser,
    this.requestId,
    this.installId,
    this.fatal = false,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ClientErrorReportDto.fromJson(Map<String, Object?> json) =>
      ClientErrorReportDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        source: (json['source'] as String?) ?? '',
        errorType: (json['error_type'] as String?) ?? '',
        message: (json['message'] as String?) ?? '',
        build: (json['build'] as String?) ?? '',
        errorCode: json['error_code'] as String?,
        stack: json['stack'] as String?,
        route: json['route'] as String?,
        device: json['device'] as String?,
        os: json['os'] as String?,
        browser: json['browser'] as String?,
        requestId: json['request_id'] as String?,
        installId: json['install_id'] as String?,
        fatal: (json['fatal'] as bool?) ?? false,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Every key the server accepts; any other key is refused.
  static const Set<String> fields = <String>{
    'schema_version',
    'source',
    'error_type',
    'message',
    'build',
    'error_code',
    'stack',
    'route',
    'device',
    'os',
    'browser',
    'request_id',
    'install_id',
    'fatal',
  };

  /// `android`, `ios` or `web`.
  final String source;

  /// The error's runtime type.
  final String errorType;

  /// What went wrong. The server removes secrets before keeping it.
  final String message;

  /// The build's short commit sha.
  final String build;

  /// The stable `AppError` code, for a failed API call.
  final String? errorCode;

  /// The stack, when there is one.
  final String? stack;

  /// Where: the API call (`GET /seasons/:id`) or what was being built.
  final String? route;

  /// The device's maker and model.
  final String? device;

  /// The operating system and version.
  final String? os;

  /// The browser, on the web.
  final String? browser;

  /// The `X-Request-Id` of the failed response, when there was one.
  final String? requestId;

  /// The app install, used only to limit how often one device reports;
  /// never stored.
  final String? installId;

  /// Whether the error broke what the player was looking at.
  final bool fatal;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map, omitting absent fields.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'source': source,
    'error_type': errorType,
    'message': message,
    'build': build,
    if (errorCode != null) 'error_code': errorCode,
    if (stack != null) 'stack': stack,
    if (route != null) 'route': route,
    if (device != null) 'device': device,
    if (os != null) 'os': os,
    if (browser != null) 'browser': browser,
    if (requestId != null) 'request_id': requestId,
    if (installId != null) 'install_id': installId,
    if (fatal) 'fatal': true,
  };
}

/// Answer to `POST /errors/report`: the problem code the error was kept
/// under, the same one the app computed and showed.
final class ClientErrorReportAckDto {
  /// Creates the answer.
  const ClientErrorReportAckDto({
    required this.problemCode,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory ClientErrorReportAckDto.fromJson(Map<String, Object?> json) =>
      ClientErrorReportAckDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        problemCode: (json['problem_code'] as String?) ?? '',
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The 4-character code.
  final String problemCode;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'problem_code': problemCode,
  };
}
