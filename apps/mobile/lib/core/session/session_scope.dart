/// A root [ProviderScope] that starts over when the signed-in account leaves.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared/shared.dart';

/// How long [appReadRetry] waits before each new try of a failed read.
const List<Duration> appReadRetryDelays = <Duration>[
  Duration(seconds: 3),
  Duration(seconds: 10),
];

/// The one retry policy of every provider in the app (script 74), set on
/// the root [ProviderScope] by [SessionScope].
///
/// Riverpod's default tries a failed read again ten times within about 38
/// seconds. At the end of a match night the server was already waiting on
/// its database, and each request that timed out came back as up to eleven
/// (the error log of 2026-10-15: 389 database timeouts, 464 "the server
/// took too long" on phones and the web). Here a failure worth another try
/// -- [ErrorKind.transient]: no network, a timeout, a 503 -- is read again
/// twice, after [appReadRetryDelays]; anything else (a refusal, a bad
/// request, a provider that failed because one it reads failed) is not
/// retried, and the screen shows it with its own retry button. A provider
/// with a policy of its own (the predictions board, the admin reads) keeps
/// it.
Duration? appReadRetry(int retryCount, Object error) {
  if (retryCount >= appReadRetryDelays.length) return null;
  if (error is! AppError || error.kind != ErrorKind.transient) return null;
  return appReadRetryDelays[retryCount];
}

/// Hosts the app's root [ProviderScope] and can throw it away.
///
/// Riverpod keeps a provider's answer for as long as its container lives,
/// and many reads here are kept alive on purpose (the month feed, the
/// caller's predictions, their seasons and groups). Every one of them
/// belongs to whoever was signed in when it ran. When that account signs
/// out, [SessionScopeState.reset] replaces the whole container, so the next
/// account starts with nothing cached instead of seeing the previous
/// account's predictions. Persistent choices (theme, fingerprint unlock,
/// the stored tokens) live on the device, not in the container, and survive.
class SessionScope extends StatefulWidget {
  /// Creates the scope with the app's root [overrides].
  const SessionScope({
    super.key,
    this.overrides = const <Override>[],
    required this.child,
  });

  /// The root overrides, applied again to every fresh container.
  final List<Override> overrides;

  /// The app.
  final Widget child;

  /// The nearest scope above [context], or `null` (tests pump their own
  /// [ProviderScope] and have none).
  static SessionScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<SessionScopeState>();

  @override
  State<SessionScope> createState() => SessionScopeState();
}

/// The state behind [SessionScope].
class SessionScopeState extends State<SessionScope> {
  int _generation = 0;

  /// Discards every provider's state and rebuilds the app under a new
  /// container.
  void reset() => setState(() => _generation++);

  @override
  Widget build(BuildContext context) => ProviderScope(
    key: ValueKey<int>(_generation),
    overrides: widget.overrides,
    retry: appReadRetry,
    child: widget.child,
  );
}
