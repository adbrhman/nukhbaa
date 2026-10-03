/// Wire shapes of the admin error log (`GET /admin/errors`,
/// `GET|POST /admin/errors/{id}`, migrations 0087 and 0088).
library;

String? _str(Object? v) => v is String ? v : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

DateTime _time(Object? v) =>
    (v is String ? DateTime.tryParse(v) : null)?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

List<Map<String, Object?>> _maps(Object? v) => v is List
    ? [
        for (final Object? item in v)
          if (item is Map) item.cast<String, Object?>(),
      ]
    : const <Map<String, Object?>>[];

/// One error in a list or on its page.
final class AdminErrorDto {
  /// Creates the error.
  const AdminErrorDto({
    required this.id,
    required this.problemCode,
    required this.source,
    required this.errorType,
    required this.message,
    required this.severity,
    required this.status,
    required this.firstBuild,
    required this.lastBuild,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.occurrences,
    required this.usersAffected,
    required this.reopenedCount,
    this.errorCode,
    this.locationFile,
    this.locationLine,
    this.locationSymbol,
    this.assigneeId,
    this.assigneeName,
    this.adminNotes,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminErrorDto.fromJson(Map<String, Object?> json) => AdminErrorDto(
    id: _int(json['id']),
    problemCode: _str(json['problem_code']) ?? '',
    source: _str(json['source']) ?? '',
    errorType: _str(json['error_type']) ?? '',
    errorCode: _str(json['error_code']),
    message: _str(json['message']) ?? '',
    locationFile: _str(json['location_file']),
    locationLine: json['location_line'] is num
        ? (json['location_line']! as num).toInt()
        : null,
    locationSymbol: _str(json['location_symbol']),
    severity: _str(json['severity']) ?? 'medium',
    status: _str(json['status']) ?? 'new',
    assigneeId: _str(json['assignee_id']),
    assigneeName: _str(json['assignee_name']),
    adminNotes: _str(json['admin_notes']),
    firstBuild: _str(json['first_build']) ?? '',
    lastBuild: _str(json['last_build']) ?? '',
    firstSeenAt: _time(json['first_seen_at']),
    lastSeenAt: _time(json['last_seen_at']),
    occurrences: _int(json['occurrences']),
    usersAffected: _int(json['users_affected']),
    reopenedCount: _int(json['reopened_count']),
  );

  /// The row id.
  final int id;

  /// The 4 characters a player reads out.
  final String problemCode;

  /// `server`, `android`, `ios` or `web`.
  final String source;

  /// The error's runtime type.
  final String errorType;

  /// The stable `AppError` code, when there is one.
  final String? errorCode;

  /// What went wrong.
  final String message;

  /// Where it happened.
  final String? locationFile;

  /// The line of [locationFile].
  final int? locationLine;

  /// The member running there.
  final String? locationSymbol;

  /// `critical`, `high`, `medium` or `low`.
  final String severity;

  /// `new`, `in_progress`, `fixed`, `verified` or `ignored`.
  final String status;

  /// The admin in charge.
  final String? assigneeId;

  /// Their name.
  final String? assigneeName;

  /// The admins' notes.
  final String? adminNotes;

  /// The first build that hit it.
  final String firstBuild;

  /// The latest build that hit it.
  final String lastBuild;

  /// First seen.
  final DateTime firstSeenAt;

  /// Last seen.
  final DateTime lastSeenAt;

  /// Times it happened.
  final int occurrences;

  /// Distinct players hit.
  final int usersAffected;

  /// Times it came back after a fix.
  final int reopenedCount;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'id': id,
    'problem_code': problemCode,
    'source': source,
    'error_type': errorType,
    'error_code': errorCode,
    'message': message,
    'location_file': locationFile,
    'location_line': locationLine,
    'location_symbol': locationSymbol,
    'severity': severity,
    'status': status,
    'assignee_id': assigneeId,
    'assignee_name': assigneeName,
    'admin_notes': adminNotes,
    'first_build': firstBuild,
    'last_build': lastBuild,
    'first_seen_at': firstSeenAt.toUtc().toIso8601String(),
    'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
    'occurrences': occurrences,
    'users_affected': usersAffected,
    'reopened_count': reopenedCount,
  };
}

/// An admin an error can be assigned to.
final class AdminRefDto {
  /// Creates the reference.
  const AdminRefDto({required this.id, required this.displayName});

  /// Deserializes from a JSON map.
  factory AdminRefDto.fromJson(Map<String, Object?> json) => AdminRefDto(
    id: _str(json['id']) ?? '',
    displayName: _str(json['display_name']) ?? '',
  );

  /// The account id.
  final String id;

  /// The display name.
  final String displayName;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'id': id, 'display_name': displayName};
}

/// `GET /admin/errors`: the counts of every list, one list, the admins.
final class AdminErrorListDto {
  /// Creates the page.
  const AdminErrorListDto({
    required this.all,
    required this.fresh,
    required this.recurring,
    required this.critical,
    required this.errors,
    required this.admins,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminErrorListDto.fromJson(Map<String, Object?> json) {
    final Object? counts = json['counts'];
    final Map<String, Object?> c = counts is Map
        ? counts.cast<String, Object?>()
        : const <String, Object?>{};
    return AdminErrorListDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      all: _int(c['all']),
      fresh: _int(c['new']),
      recurring: _int(c['recurring']),
      critical: _int(c['critical']),
      errors: [
        for (final m in _maps(json['errors'])) AdminErrorDto.fromJson(m),
      ],
      admins: [for (final m in _maps(json['admins'])) AdminRefDto.fromJson(m)],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Every error.
  final int all;

  /// Status `new`.
  final int fresh;

  /// Open and recurring.
  final int recurring;

  /// Open and critical.
  final int critical;

  /// The errors of the list asked for.
  final List<AdminErrorDto> errors;

  /// The admins an error can be assigned to.
  final List<AdminRefDto> admins;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'counts': {
      'all': all,
      'new': fresh,
      'recurring': recurring,
      'critical': critical,
    },
    'errors': [for (final e in errors) e.toJson()],
    'admins': [for (final a in admins) a.toJson()],
  };
}

/// One of an error's last occurrences, in full.
final class AdminErrorSampleDto {
  /// Creates the sample.
  const AdminErrorSampleDto({
    required this.occurredAt,
    required this.build,
    required this.message,
    this.requestId,
    this.userId,
    this.userName,
    this.route,
    this.device,
    this.os,
    this.browser,
    this.stack,
    this.requestInput,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminErrorSampleDto.fromJson(Map<String, Object?> json) =>
      AdminErrorSampleDto(
        occurredAt: _time(json['occurred_at']),
        build: _str(json['build']) ?? '',
        message: _str(json['message']) ?? '',
        requestId: _str(json['request_id']),
        userId: _str(json['user_id']),
        userName: _str(json['user_name']),
        route: _str(json['route']),
        device: _str(json['device']),
        os: _str(json['os']),
        browser: _str(json['browser']),
        stack: _str(json['stack']),
        requestInput: _str(json['request_input']),
      );

  /// When it happened.
  final DateTime occurredAt;

  /// The build.
  final String build;

  /// What went wrong.
  final String message;

  /// The server request.
  final String? requestId;

  /// The player.
  final String? userId;

  /// Their name.
  final String? userName;

  /// The route, screen or job.
  final String? route;

  /// The device.
  final String? device;

  /// The system.
  final String? os;

  /// The browser or HTTP client.
  final String? browser;

  /// The stack.
  final String? stack;

  /// The request's inputs, as JSON text.
  final String? requestInput;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'build': build,
    'message': message,
    'request_id': requestId,
    'user_id': userId,
    'user_name': userName,
    'route': route,
    'device': device,
    'os': os,
    'browser': browser,
    'stack': stack,
    'request_input': requestInput,
  };
}

/// How often one build hit an error.
final class AdminErrorBuildDto {
  /// Creates the row.
  const AdminErrorBuildDto({
    required this.build,
    required this.occurrences,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  /// Deserializes from a JSON map.
  factory AdminErrorBuildDto.fromJson(Map<String, Object?> json) =>
      AdminErrorBuildDto(
        build: _str(json['build']) ?? '',
        occurrences: _int(json['occurrences']),
        firstSeenAt: _time(json['first_seen_at']),
        lastSeenAt: _time(json['last_seen_at']),
      );

  /// The build.
  final String build;

  /// Times in that build.
  final int occurrences;

  /// First seen in it.
  final DateTime firstSeenAt;

  /// Last seen in it.
  final DateTime lastSeenAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'build': build,
    'occurrences': occurrences,
    'first_seen_at': firstSeenAt.toUtc().toIso8601String(),
    'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
  };
}

/// `GET|POST /admin/errors/{id}`: the error, its samples and builds.
final class AdminErrorDetailDto {
  /// Creates the page.
  const AdminErrorDetailDto({
    required this.error,
    required this.samples,
    required this.builds,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminErrorDetailDto.fromJson(Map<String, Object?> json) {
    final Object? error = json['error'];
    return AdminErrorDetailDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      error: AdminErrorDto.fromJson(
        error is Map ? error.cast<String, Object?>() : const {},
      ),
      samples: [
        for (final m in _maps(json['samples'])) AdminErrorSampleDto.fromJson(m),
      ],
      builds: [
        for (final m in _maps(json['builds'])) AdminErrorBuildDto.fromJson(m),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The error.
  final AdminErrorDto error;

  /// Its last occurrences, newest first.
  final List<AdminErrorSampleDto> samples;

  /// Its builds, most recent first.
  final List<AdminErrorBuildDto> builds;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'error': error.toJson(),
    'samples': [for (final s in samples) s.toJson()],
    'builds': [for (final b in builds) b.toJson()],
  };
}

/// Body of `POST /admin/errors/{id}`: only the keys present change. An
/// empty `assignee_id` removes the assignee; empty `notes` clear them.
final class AdminErrorUpdateDto {
  /// Creates the change.
  const AdminErrorUpdateDto({
    this.status,
    this.severity,
    this.assigneeId,
    this.notes,
  });

  /// Deserializes from a JSON map.
  factory AdminErrorUpdateDto.fromJson(Map<String, Object?> json) =>
      AdminErrorUpdateDto(
        status: _str(json['status']),
        severity: _str(json['severity']),
        assigneeId: _str(json['assignee_id']),
        notes: _str(json['notes']),
      );

  /// The new status.
  final String? status;

  /// The new severity.
  final String? severity;

  /// The new assignee; empty to remove.
  final String? assigneeId;

  /// The new notes; empty to clear.
  final String? notes;

  /// Serializes to a JSON-encodable map, omitting what does not change.
  Map<String, Object?> toJson() => {
    if (status != null) 'status': status,
    if (severity != null) 'severity': severity,
    if (assigneeId != null) 'assignee_id': assigneeId,
    if (notes != null) 'notes': notes,
  };
}

/// One build in `GET /admin/error-releases`.
final class AdminErrorReleaseDto {
  /// Creates the row.
  const AdminErrorReleaseDto({
    required this.build,
    required this.errors,
    required this.critical,
    required this.occurrences,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  /// Deserializes from a JSON map.
  factory AdminErrorReleaseDto.fromJson(Map<String, Object?> json) =>
      AdminErrorReleaseDto(
        build: _str(json['build']) ?? '',
        errors: _int(json['errors']),
        critical: _int(json['critical']),
        occurrences: _int(json['occurrences']),
        firstSeenAt: _time(json['first_seen_at']),
        lastSeenAt: _time(json['last_seen_at']),
      );

  /// The build.
  final String build;

  /// Distinct errors it hit.
  final int errors;

  /// Of which critical.
  final int critical;

  /// Occurrences in it.
  final int occurrences;

  /// Its first error.
  final DateTime firstSeenAt;

  /// Its latest error.
  final DateTime lastSeenAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'build': build,
    'errors': errors,
    'critical': critical,
    'occurrences': occurrences,
    'first_seen_at': firstSeenAt.toUtc().toIso8601String(),
    'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
  };
}

/// One file in `GET /admin/error-releases`.
final class AdminErrorFileDto {
  /// Creates the row.
  const AdminErrorFileDto({
    required this.file,
    required this.errors,
    required this.occurrences,
  });

  /// Deserializes from a JSON map.
  factory AdminErrorFileDto.fromJson(Map<String, Object?> json) =>
      AdminErrorFileDto(
        file: _str(json['file']) ?? '',
        errors: _int(json['errors']),
        occurrences: _int(json['occurrences']),
      );

  /// The file.
  final String file;

  /// Distinct errors located there.
  final int errors;

  /// Their occurrences.
  final int occurrences;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'file': file,
    'errors': errors,
    'occurrences': occurrences,
  };
}

/// `GET /admin/error-releases`: the errors of each recent build and the
/// files most errors come from.
final class AdminErrorReleasesDto {
  /// Creates the summary.
  const AdminErrorReleasesDto({
    required this.releases,
    required this.files,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminErrorReleasesDto.fromJson(Map<String, Object?> json) =>
      AdminErrorReleasesDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        releases: [
          for (final m in _maps(json['releases']))
            AdminErrorReleaseDto.fromJson(m),
        ],
        files: [
          for (final m in _maps(json['files'])) AdminErrorFileDto.fromJson(m),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The recent builds, latest error first.
  final List<AdminErrorReleaseDto> releases;

  /// The files with the most occurrences.
  final List<AdminErrorFileDto> files;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'releases': [for (final r in releases) r.toJson()],
    'files': [for (final f in files) f.toJson()],
  };
}
