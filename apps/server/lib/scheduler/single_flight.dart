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
Future<void> Function(T) singleFlight<T>(Future<void> Function(T) run) {
  var running = false;
  return (T argument) async {
    if (running) {
      return;
    }
    running = true;
    try {
      await run(argument);
    } finally {
      running = false;
    }
  };
}
