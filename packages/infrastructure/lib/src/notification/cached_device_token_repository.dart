import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// Skips the device-token write a phone repeats on every start when nothing
/// changed (script 101).
///
/// The app registers its push token each time it opens, so a burst of
/// players opening it at once (17 October 2026, 20:31) put one write per
/// player on the database beside every read, on a server with 0.2 vCPU. A
/// token this repository registered for the same player and platform is
/// answered without the database for [ttl].
///
/// Only phone tokens (`android`, `ios`) are held: a `web` registration
/// depends on whether the player also has the app, which other writes
/// change, so it always goes to [_inner]. The entry is keyed by the token,
/// so the same phone signed in as another player is written (and
/// reassigned) at once; a sign-out through [remove] drops it, so the next
/// registration is written again. A token the senders find dead is deleted
/// elsewhere, but a dead token is replaced by a new one on the phone, which
/// this cache has never seen; the [ttl] bounds any other case.
final class CachedDeviceTokenRepository implements DeviceTokenRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedDeviceTokenRepository(
    this._inner, {
    this.ttl = const Duration(hours: 6),
    int maxEntries = 4096,
    DateTime Function() now = DateTime.now,
  }) : _bound = TtlCache<String, _Binding>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  /// How long a registration is answered from memory.
  final Duration ttl;

  final DeviceTokenRepository _inner;
  final TtlCache<String, _Binding> _bound;

  static const Set<String> _phonePlatforms = {'android', 'ios'};

  @override
  Future<Result<void>> upsert({
    required UserId userId,
    required String token,
    required String platform,
  }) async {
    final bool phone = _phonePlatforms.contains(platform);
    if (phone) {
      final _Binding? held = _bound.read(token);
      if (held != null &&
          held.userId == userId.value &&
          held.platform == platform) {
        return const Result.ok(null);
      }
    }
    final int startedAt = _bound.generation;
    final Result<void> result = await _inner.upsert(
      userId: userId,
      token: token,
      platform: platform,
    );
    if (phone && result is Ok<void>) {
      _bound.write(
        token,
        _Binding(userId.value, platform),
        startedAt: startedAt,
      );
    }
    return result;
  }

  @override
  Future<Result<void>> remove({required UserId userId, required String token}) {
    _bound.remove(token);
    return _inner.remove(userId: userId, token: token);
  }
}

/// The player and platform a token was last registered for.
final class _Binding {
  const _Binding(this.userId, this.platform);

  final String userId;
  final String platform;
}
