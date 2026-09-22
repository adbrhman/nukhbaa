/// Use-case: record a tap on a push (plan P3-8).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/ports/push_open_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Records that the caller opened a push, by its [PushLink], for the open
/// rate the funnel view reports (0069).
///
/// Only a known link is kept: a made-up one would be noise in the funnel,
/// and refusing it costs the app nothing -- it never waits on the answer.
///
/// Never throws; returns a typed [Result].
final class RecordPushOpen {
  /// Creates the use-case over its collaborators.
  const RecordPushOpen({
    required PushOpenRepository opens,
    required Clock clock,
  }) : _opens = opens,
       _clock = clock;

  final PushOpenRepository _opens;
  final Clock _clock;

  /// The links a push can carry.
  static const Set<String> knownLinks = <String>{
    PushLink.fixtures,
    PushLink.league,
    PushLink.inbox,
  };

  /// Records [principal]'s tap on a push carrying [link].
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required String link,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    if (!knownLinks.contains(link)) {
      return const Result.err(
        AppError.validation('notification.unknown_link', 'Unknown push link'),
      );
    }
    return _opens.record(
      userId: principal.userId,
      link: link,
      openedAt: _clock.nowUtc(),
    );
  }
}
