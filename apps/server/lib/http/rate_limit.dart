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

  /// Forgets [key]'s window, so its next request starts a fresh count.
  void reset(String key) => _windows.remove(key);

  /// How long until [key]'s window resets when [key] has used all of its
  /// [limit], or `null` while it may go on. Counts nothing: a caller that
  /// counts only what succeeded checks with this first and [hit]s after.
  Duration? blockedFor(String key) {
    final current = _windows[key];
    if (current == null) {
      return null;
    }
    final now = _clock();
    if (!now.isBefore(current.endsAt) || current.count < limit) {
      return null;
    }
    return current.endsAt.difference(now);
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
/// name, a token), so it cannot grow the database; these append. Without
/// a cap one account could fill the free Supabase plan (500 MB) with them.
enum PlayerAppend {
  /// `POST /me/frame-report`: the app sends one each time it goes to the
  /// background, so 30 an hour is generous.
  frameReport,

  /// `POST /me/push-opened`: one per notification opened; 60 an hour.
  pushOpened,

  /// `POST /me/screen-views`: the app sends one each time it goes to the
  /// background, so 30 an hour is generous.
  screenViews,

  /// `POST /duels/challenges`: each adds a challenge row, and cancelling
  /// one frees a pending seat, so the database cap alone would not bound
  /// the rows; 30 an hour.
  duelChallenge,
}

final RateLimiter _frameReportLimiter = RateLimiter(
  limit: 30,
  window: const Duration(hours: 1),
);

final RateLimiter _pushOpenLimiter = RateLimiter(
  limit: 60,
  window: const Duration(hours: 1),
);

final RateLimiter _screenViewsLimiter = RateLimiter(
  limit: 30,
  window: const Duration(hours: 1),
);

final RateLimiter _duelChallengeLimiter = RateLimiter(
  limit: 30,
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
    PlayerAppend.screenViews => _screenViewsLimiter,
    PlayerAppend.duelChallenge => _duelChallengeLimiter,
  };
  final wait = limiter.hit(principal.userId.value);
  return wait == null ? null : tooManyRequests(wait);
}

/// What one player does that rings another player's phone, counted per
/// player over 24 hours (audit M-20).
///
/// A league's name is free text and used to be the title of the invitation
/// push, so one account could send any words to anyone it found by name,
/// as often as it liked: a new league for each push, the player-write
/// limit (600 a minute) the only bound, and a private challenge cancelled
/// and sent again. Only what succeeded is counted ([countPlayerReach]), so
/// a refused attempt costs nothing; a refusal is an Arabic `409` the app
/// shows as it is, not a `429` that reads "wait a minute".
enum PlayerReach {
  /// `POST /groups`: 5 new leagues in 24 hours.
  groupCreate,

  /// `POST /groups/{id}/invitations`: 30 invitations in 24 hours, enough
  /// to bring a whole chat group into a league in one evening.
  groupInvite,

  /// A private `POST /duels/challenges`: 3 to the same player in 24 hours.
  privateChallenge,
}

final RateLimiter _groupCreateLimiter = RateLimiter(
  limit: 5,
  window: const Duration(hours: 24),
);

final RateLimiter _groupInviteLimiter = RateLimiter(
  limit: 30,
  window: const Duration(hours: 24),
);

final RateLimiter _privateChallengeLimiter = RateLimiter(
  limit: 3,
  window: const Duration(hours: 24),
);

RateLimiter _reachLimiter(PlayerReach kind) => switch (kind) {
  PlayerReach.groupCreate => _groupCreateLimiter,
  PlayerReach.groupInvite => _groupInviteLimiter,
  PlayerReach.privateChallenge => _privateChallengeLimiter,
};

// A user id is a UUID, which Postgres compares without case: an upper-case
// copy of the same id must not open a second allowance.
String _reachKey(AuthenticatedUser principal, String? target) => target == null
    ? principal.userId.value
    : '${principal.userId.value}|${target.trim().toLowerCase()}';

/// The `409` when [principal] has done [kind] (to [target], for a private
/// challenge) as often as 24 hours allow, or `null`. Counts nothing; admins
/// and the service principal are never refused.
Response? limitPlayerReach(
  PlayerReach kind,
  AuthenticatedUser principal, {
  String? target,
}) {
  if (principal.role != PlatformRole.user) {
    return null;
  }
  final wait = _reachLimiter(kind).blockedFor(_reachKey(principal, target));
  if (wait == null) {
    return null;
  }
  final String message = switch (kind) {
    PlayerReach.groupCreate =>
      'أنشأت 5 دوريات خلال 24 ساعة، وهذا هو الحد. حاول لاحقاً.',
    PlayerReach.groupInvite =>
      'أرسلت 30 دعوة خلال 24 ساعة، وهذا هو الحد. حاول لاحقاً.',
    PlayerReach.privateChallenge =>
      'تحدّيت هذا اللاعب 3 مرات خلال 24 ساعة، وهذا هو الحد. حاول لاحقاً.',
  };
  return Response.json(
    statusCode: HttpStatus.conflict,
    body: ErrorResponseDto(
      code: 'social.daily_limit',
      message: message,
    ).toJson(),
  );
}

/// Counts one [kind] that succeeded for [principal] (to [target], for a
/// private challenge). Admins and the service principal are not counted.
void countPlayerReach(
  PlayerReach kind,
  AuthenticatedUser principal, {
  String? target,
}) {
  if (principal.role != PlatformRole.user) {
    return;
  }
  _reachLimiter(kind).hit(_reachKey(principal, target));
}

/// The anonymous `/auth/*` attempts that are counted.
///
/// Each is counted per e-mail AND network address (audit M-16): counted per
/// e-mail alone, anyone who knew a rival's address could lock him out of
/// signing in, and out of a password reset, by failing on purpose. A
/// stranger's failures from his own network now spend only his own
/// allowance. A wider allowance per network address bounds one caller
/// trying many accounts; it is wide because many players reach the API
/// from one carrier address. The reset code is the exception: see
/// [passwordResetCode].
enum AuthAttempt {
  /// `POST /auth/login`: 10 tries per address in 10 minutes, so a password
  /// cannot be guessed through the API.
  login,

  /// `POST /auth/register`: 5 per address in 10 minutes.
  register,

  /// `POST /auth/password-reset/request`: 3 per address in 15 minutes, so
  /// nobody can flood someone's inbox with reset e-mails.
  passwordReset,

  /// `POST /auth/password-reset/verify`: 5 codes per e-mail in 15 minutes,
  /// counted per e-mail alone so the code of a reset e-mail cannot be
  /// guessed from many networks. Only someone already waiting for a code
  /// can be held back by it, for 15 minutes. One network address may also
  /// try 30 codes in 15 minutes, whatever the e-mails (audit C-02): every
  /// check spends this server's one GoTrue quota.
  passwordResetCode,
}

final RateLimiter _loginAddressLimiter = RateLimiter(
  limit: 100,
  window: const Duration(minutes: 10),
);

final RateLimiter _registerAddressLimiter = RateLimiter(
  limit: 30,
  window: const Duration(minutes: 10),
);

final RateLimiter _passwordResetAddressLimiter = RateLimiter(
  limit: 30,
  window: const Duration(minutes: 15),
);

final RateLimiter _passwordResetCodeAddressLimiter = RateLimiter(
  limit: 30,
  window: const Duration(minutes: 15),
);

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

final RateLimiter _passwordResetCodeLimiter = RateLimiter(
  limit: 5,
  window: const Duration(minutes: 15),
);

/// The `429` for an [attempt] on [email] from [address] over its limit, or
/// `null`. [address] is the caller's network address ([clientAddress]);
/// without one the e-mail alone is the key, as before.
Response? limitAuthAttempt(
  AuthAttempt attempt,
  String email, {
  String? address,
}) {
  final RateLimiter? perAddress = switch (attempt) {
    AuthAttempt.login => _loginAddressLimiter,
    AuthAttempt.register => _registerAddressLimiter,
    AuthAttempt.passwordReset => _passwordResetAddressLimiter,
    AuthAttempt.passwordResetCode => _passwordResetCodeAddressLimiter,
  };
  if (perAddress != null && address != null) {
    final wait = perAddress.hit(address);
    if (wait != null) return tooManyRequests(wait);
  }
  final wait = _limiterFor(attempt).hit(_authKey(attempt, email, address));
  return wait == null ? null : tooManyRequests(wait);
}

/// Forgets the failures counted for [email] from [address]: a player who
/// signs in has nothing left to answer for (audit M-16).
void forgiveAuthAttempts(
  AuthAttempt attempt,
  String email, {
  String? address,
}) => _limiterFor(attempt).reset(_authKey(attempt, email, address));

RateLimiter _limiterFor(AuthAttempt attempt) => switch (attempt) {
  AuthAttempt.login => _loginLimiter,
  AuthAttempt.register => _registerLimiter,
  AuthAttempt.passwordReset => _passwordResetLimiter,
  AuthAttempt.passwordResetCode => _passwordResetCodeLimiter,
};

String _authKey(AuthAttempt attempt, String email, String? address) {
  final String who = email.trim().toLowerCase();
  if (attempt == AuthAttempt.passwordResetCode) return who;
  return '$who|${address ?? ''}';
}

/// The anonymous `/auth/*` calls that name no account, counted per network
/// address alone (audit C-02).
///
/// Every player's sign-in, renewal and Google sign-in reach GoTrue from this
/// server's one address, so they share one GoTrue quota. These two had no
/// limit at all: one caller sending made-up refresh or Google tokens could
/// spend the quota, and then nobody could sign in or renew a session. Each
/// address now gets a share wide enough for many players behind one carrier
/// address and too small for one caller to spend the quota alone. A refused
/// call is `429`, which the app takes as "try again later", never as a
/// refused token, so nobody is signed out by it. A request with no address
/// is not counted. The real fix, each player's own GoTrue quota through IP
/// forwarding, needs the owner's Supabase settings.
enum AuthCall {
  /// `POST /auth/refresh`: 100 per address in 10 minutes, the allowance of
  /// a sign-in. A player renews only when his access token runs out.
  refresh,

  /// `POST /auth/google`: 30 per address in 10 minutes, the allowance of a
  /// sign-up (a first Google sign-in creates the account).
  google,
}

final RateLimiter _refreshAddressLimiter = RateLimiter(
  limit: 100,
  window: const Duration(minutes: 10),
);

final RateLimiter _googleAddressLimiter = RateLimiter(
  limit: 30,
  window: const Duration(minutes: 10),
);

/// The `429` for a [call] from [address] over its share, or `null`. Without
/// an address nothing is counted.
Response? limitAuthCall(AuthCall call, {String? address}) {
  if (address == null) {
    return null;
  }
  final limiter = switch (call) {
    AuthCall.refresh => _refreshAddressLimiter,
    AuthCall.google => _googleAddressLimiter,
  };
  final wait = limiter.hit(address);
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

/// Reports from nobody signed in that one network address may send, on top
/// of [errorReportAddressLimiter] (audit M-19). A script needs no account
/// to send them, and each made-up error used to be a new row; 120 an hour
/// is still more than a sign-in screen that crashes in a loop sends.
final RateLimiter anonymousErrorReportAddressLimiter = RateLimiter(
  limit: 120,
  window: const Duration(hours: 1),
);

/// `429` when [device] or [address] has sent too many error reports; null
/// otherwise. A report with neither counts against one shared anonymous
/// key. A report from nobody [signedIn] is also held to
/// [anonymousErrorReportAddressLimiter].
Response? limitErrorReport({
  String? device,
  String? address,
  bool signedIn = false,
}) {
  final deviceKey = device?.trim() ?? '';
  if (deviceKey.isNotEmpty) {
    final wait = errorReportDeviceLimiter.hit(deviceKey);
    if (wait != null) {
      return tooManyRequests(wait);
    }
  }
  final addressKey = address?.trim() ?? '';
  final String key = addressKey.isEmpty ? 'anonymous' : addressKey;
  if (!signedIn) {
    final wait = anonymousErrorReportAddressLimiter.hit(key);
    if (wait != null) {
      return tooManyRequests(wait);
    }
  }
  final wait = errorReportAddressLimiter.hit(key);
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
