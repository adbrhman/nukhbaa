import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

/// [ErrorGroupView] -> [AdminErrorDto].
AdminErrorDto errorGroupToDto(ErrorGroupView g) => AdminErrorDto(
  id: g.id,
  problemCode: g.problemCode,
  source: g.source,
  errorType: g.errorType,
  errorCode: g.errorCode,
  message: g.message,
  locationFile: g.locationFile,
  locationLine: g.locationLine,
  locationSymbol: g.locationSymbol,
  severity: g.severity,
  status: g.status,
  assigneeId: g.assigneeId,
  assigneeName: g.assigneeName,
  adminNotes: g.adminNotes,
  firstBuild: g.firstBuild,
  lastBuild: g.lastBuild,
  firstSeenAt: g.firstSeenAt,
  lastSeenAt: g.lastSeenAt,
  occurrences: g.occurrences,
  usersAffected: g.usersAffected,
  reopenedCount: g.reopenedCount,
);

/// [AdminErrorList] -> [AdminErrorListDto].
AdminErrorListDto errorListToDto(AdminErrorList page) => AdminErrorListDto(
  all: page.counts.all,
  fresh: page.counts.fresh,
  recurring: page.counts.recurring,
  critical: page.counts.critical,
  errors: [for (final g in page.errors) errorGroupToDto(g)],
  admins: [
    for (final a in page.admins)
      AdminRefDto(id: a.id, displayName: a.displayName),
  ],
);

/// [ErrorGroupDetail] -> [AdminErrorDetailDto].
AdminErrorDetailDto errorDetailToDto(ErrorGroupDetail d) => AdminErrorDetailDto(
  error: errorGroupToDto(d.group),
  samples: [
    for (final s in d.samples)
      AdminErrorSampleDto(
        occurredAt: s.occurredAt,
        build: s.build,
        message: s.message,
        requestId: s.requestId,
        userId: s.userId,
        userName: s.userName,
        route: s.route,
        device: s.device,
        os: s.os,
        browser: s.browser,
        stack: s.stack,
        requestInput: s.requestInputJson,
      ),
  ],
  builds: [
    for (final b in d.builds)
      AdminErrorBuildDto(
        build: b.build,
        occurrences: b.occurrences,
        firstSeenAt: b.firstSeenAt,
        lastSeenAt: b.lastSeenAt,
      ),
  ],
);
