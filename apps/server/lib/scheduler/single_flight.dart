/// Keeps an in-process sweep from overlapping itself.
library;

/// Wraps [run] so that a call made while an earlier call is still running is
/// skipped rather than started alongside it.
///
/// Every scheduler here fires on a `Timer.periodic` and never awaits its
/// sweep, so a sweep slower than its tick -- a push that hangs, a query stuck
/// behind a lock -- used to be joined by a second one, then a third, each
/// reading the same targets before any of them had marked them done. That is
/// how one reminder reaches the same phone twice. A skipped tick costs
/// nothing: the next one runs as usual.
///
/// The flag is cleared in `finally`, so a run that throws never blocks the
/// runs after it.
///
/// Every running sweep is also known to [drainSweeps], which the server
/// awaits when it is told to stop (audit M-28).
Future<void> Function(T) singleFlight<T>(Future<void> Function(T) run) {
  var running = false;
  return (T argument) async {
    if (running || _stopping) {
      return;
    }
    running = true;
    final Future<void> sweep = run(argument);
    _inFlight.add(sweep);
    try {
      await sweep;
    } finally {
      _inFlight.remove(sweep);
      running = false;
    }
  };
}

bool _stopping = false;
final Set<Future<void>> _inFlight = <Future<void>>{};

/// Starts no sweep from now on and waits, at most [timeout], for the ones
/// already running (audit M-28).
///
/// A redeploy stops the container with SIGTERM. Cut in the middle, a sweep
/// had sent pushes it had not yet recorded as sent -- so the next process
/// sent them again -- or had claimed queued pushes it never sent. A sweep
/// that fails is not this function's concern: it never throws.
Future<void> drainSweeps({
  Duration timeout = const Duration(seconds: 20),
}) async {
  _stopping = true;
  if (_inFlight.isEmpty) {
    return;
  }
  try {
    await Future.wait<void>(
      _inFlight.toList(),
    ).timeout(timeout, onTimeout: () => const <void>[]);
  } on Object {
    // A sweep that failed has stopped all the same.
  }
}
