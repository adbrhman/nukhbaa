import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

const Set<HttpMethod> _writes = <HttpMethod>{
  HttpMethod.post,
  HttpMethod.put,
  HttpMethod.patch,
  HttpMethod.delete,
};

/// The paths an admin changes the platform on.
const List<String> _adminPrefixes = <String>[
  '/admin',
  '/fixtures',
  '/competitions',
  '/teams',
  '/leagues',
  '/crests',
  '/champions',
  '/cup-champions',
  '/months',
  '/users',
];

// NK300_05
/// Whether a write on [path] is an admin's change the owners see (script
/// 300): the admin paths, `/seasons` but a player's own prediction, its
/// reaction and joining a season; never `/me`, `/groups` or the
/// notifications, which are an admin's own play, nor a conversation marked
/// read.
bool isAdminActivityPath(String path) {
  if (path.endsWith('/read')) return false;
  for (final String prefix in _adminPrefixes) {
    if (path == prefix || path.startsWith('$prefix/')) return true;
  }
  if (path.startsWith('/seasons/')) {
    return !path.endsWith('/prediction') &&
        !path.contains('/predictions/') &&
        !path.endsWith('/participants');
  }
  return false;
}

/// Keeps in [log] the change [principal] made, when he is an admin and the
/// write on [path] was answered below `400` (script 300, migration 0224).
/// Nothing is refused here; a failure to keep it is printed and the answer
/// goes out as it was.
Future<void> keepAdminActivity({
  required AdminActivityLog log,
  required AuthenticatedUser principal,
  required HttpMethod method,
  required String path,
  required int status,
}) async {
  if (principal.role != PlatformRole.admin ||
      !_writes.contains(method) ||
      status >= 400 ||
      !isAdminActivityPath(path)) {
    return;
  }
  final Result<void> kept = await log.record(
    actor: principal.userId,
    method: method.value,
    path: path,
    status: status,
  );
  if (kept case Err<void>(:final error)) {
    // ignore: avoid_print
    print('[admin-activity] not kept: ${error.code} ${error.message}');
  }
}
