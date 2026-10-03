import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';

/// Counts requests per key in fixed windows, inside this process.
///
/// The API runs as a single Northflank instance, so an in-process count is
/// the whole picture; a restart forgets it, which only ever errs towards
/// letting a request through. Nothing here needs a dependency or a table.
final class RateLimiter {
  /// Allows [limit] requests per key in every [window].
  RateLimiter({
    required this.limit,
    required this.window,
    DateTime Function()? clock,
  }) : assert(limit > 0, 'limit must be positive'),
       _clock = clock ?? DateTime.now;

  /// Requests allowed per key in one [window].
  final int limit;

  /// Length of a counting window.
  final Duration window;

  final DateTime Function() _clock;
  final Map<String, _Window> _windows = <String, _Window>{};

  /// Above this many keys, expired windows are dropped before counting, so
  /// the map stays bounded however many keys pass through it.
  static const int _pruneAbove = 10000;

  /// Counts one request for [key]. Returns `null` when it is allowed, or how
  /// long until [key]'s window resets when it is over the limit (a refused
  /// request is not counted).
  Duration? hit(String key) {
    final now = _clock();
    if (_windows.length > _pruneAbove) {
      _windows.removeWhere((_, w) => !now.isBefore(w.endsAt));
    }
    final current = _windows[key];
    if (current == null || !now.isBefore(current.endsAt)) {
      _windows[key] = _Window(now.add(window));
      return null;
    }
    if (current.count >= limit) {
      return current.endsAt.difference(now);
    }
    current.count++;
    return null;
  }
}

final class _Window {
  _Window(this.endsAt);

  final DateTime endsAt;
  int count = 1;
}

/// Writes (every method but GET and HEAD) per signed-in player.
///
/// Why: no route had any limit, so one account with a script could keep the
/// server and the database busy without end. The match card saves a score
/// 250 ms after each tap, so a fast player sends a few writes a second;
/// 600 a minute stays far above that. Admins and the service principal are
/// not counted.
final RateLimiter playerWriteLimiter = RateLimiter(
  limit: 600,
  window: const Duration(minutes: 1),
);

/// The `429` for a write over [playerWriteLimiter], or `null` when the
/// request may go on.
Response? limitPlayerWrite(
  RateLimiter limiter,
  AuthenticatedUser principal,
  HttpMethod method,
) {
  if (method == HttpMethod.get || method == HttpMethod.head) {
    return null;
  }
  if (principal.role != PlatformRole.user) {
    return null;
  }
  final wait = limiter.hit(principal.userId.value);
  return wait == null ? null : tooManyRequests(wait);
}

/// The writes that add a row every time, counted per player per hour.
///
/// Every other player write updates a row it already has (a prediction, a
/// name, a token), so it cannot grow the database; these two append. Without
/// a cap one account could fill the free Supabase plan (500 MB) with them.
enum PlayerAppend {
  /// `POST /me/frame-report`: the app sends one each time it goes to the
  /// background, so 30 an hour is generous.
  frameReport,

  /// `POST /me/push-opened`: one per notification opened; 60 an hour.
  pushOpened,
}

final RateLimiter _frameReportLimiter = RateLimiter(
  limit: 30,
  window: const Duration(hours: 1),
);

final RateLimiter _pushOpenLimiter = RateLimiter(
  limit: 60,
  window: const Duration(hours: 1),
);

/// The `429` for a [kind] append by [principal] over its hourly cap, or
/// `null` when it may be stored.
Response? limitPlayerAppend(PlayerAppend kind, AuthenticatedUser principal) {
  if (principal.role != PlatformRole.user) {
    return null;
  }
  final limiter = switch (kind) {
    PlayerAppend.frameReport => _frameReportLimiter,
    PlayerAppend.pushOpened => _pushOpenLimiter,
  };
  final wait = limiter.hit(principal.userId.value);
  return wait == null ? null : tooManyRequests(wait);
}

/// The anonymous `/auth/*` attempts that are counted, each per e-mail.
enum AuthAttempt {
  /// `POST /auth/login`: 10 tries per address in 10 minutes, so a password
  /// cannot be guessed through the API.
  login,

  /// `POST /auth/register`: 5 per address in 10 minutes.
  register,

  /// `POST /auth/password-reset/request`: 3 per address in 15 minutes, so
  /// nobody can flood someone's inbox with reset e-mails.
  passwordReset,
}

final RateLimiter _loginLimiter = RateLimiter(
  limit: 10,
  window: const Duration(minutes: 10),
);

final RateLimiter _registerLimiter = RateLimiter(
  limit: 5,
  window: const Duration(minutes: 10),
);

final RateLimiter _passwordResetLimiter = RateLimiter(
  limit: 3,
  window: const Duration(minutes: 15),
);

/// The `429` for an [attempt] on [email] over its limit, or `null`.
///
/// Counted per address rather than per IP: behind the mobile carriers' shared
/// addresses many players reach the API from one IP, and an IP limit would
/// refuse them together.
Response? limitAuthAttempt(AuthAttempt attempt, String email) {
  final limiter = switch (attempt) {
    AuthAttempt.login => _loginLimiter,
    AuthAttempt.register => _registerLimiter,
    AuthAttempt.passwordReset => _passwordResetLimiter,
  };
  final wait = limiter.hit(email.trim().toLowerCase());
  return wait == null ? null : tooManyRequests(wait);
}

/// Error reports one device may send (`POST /errors/report`, migration
/// 0087): an app stuck in a loop must not fill the log. Keyed on the
/// install id, or the player when there is none (the web build).
final RateLimiter errorReportDeviceLimiter = RateLimiter(
  limit: 30,
  window: const Duration(hours: 1),
);

/// Error reports one network address may send: the route takes reports
/// before sign-in, so the address bounds a caller that invents a new
/// install id for every request. Wide, because many players share one
/// carrier address and an outage makes every app report at once.
final RateLimiter errorReportAddressLimiter = RateLimiter(
  limit: 600,
  window: const Duration(hours: 1),
);

/// `429` when [device] or [address] has sent too many error reports; null
/// otherwise. A report with neither counts against one shared anonymous
/// key.
Response? limitErrorReport({String? device, String? address}) {
  final deviceKey = device?.trim() ?? '';
  if (deviceKey.isNotEmpty) {
    final wait = errorReportDeviceLimiter.hit(deviceKey);
    if (wait != null) {
      return tooManyRequests(wait);
    }
  }
  final addressKey = address?.trim() ?? '';
  final wait = errorReportAddressLimiter.hit(
    addressKey.isEmpty ? 'anonymous' : addressKey,
  );
  return wait == null ? null : tooManyRequests(wait);
}

/// The caller's network address: the last hop of `X-Forwarded-For` (the
/// one the platform's proxy added, which the client cannot forge), else
/// `X-Real-IP`.
String? clientAddress(Map<String, String> headers) {
  final forwarded = headers['x-forwarded-for'];
  if (forwarded != null) {
    final hops = [
      for (final hop in forwarded.split(','))
        if (hop.trim().isNotEmpty) hop.trim(),
    ];
    if (hops.isNotEmpty) {
      return hops.last;
    }
  }
  final real = headers['x-real-ip']?.trim();
  return real == null || real.isEmpty ? null : real;
}

/// `429 Too Many Requests` in the shared error envelope, with `Retry-After`.
Response tooManyRequests(Duration wait) {
  final seconds = wait.inSeconds < 1 ? 1 : wait.inSeconds;
  return Response.json(
    statusCode: HttpStatus.tooManyRequests,
    headers: {HttpHeaders.retryAfterHeader: '$seconds'},
    body: const ErrorResponseDto(
      code: 'request.rate_limited',
      message: 'طلبات كثيرة خلال وقت قصير. انتظر قليلًا ثم حاول مرة أخرى.',
    ).toJson(),
  );
}
