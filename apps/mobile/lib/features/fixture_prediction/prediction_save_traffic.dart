/// Keeps prediction saves from crowding the server (script 256).
///
/// Two things happened on a day with many matches, and both end at the
/// server's eight database connections:
///
///  * every card sent its own save as soon as its 250 ms pause ended, so
///    tapping across fifteen cards put fifteen requests on the wire at once,
///    each one running several queries; the month feed, the history and the
///    scores queued behind them (`connections in use 8/8` in the error log of
///    2026-10-16, and `api_client.timeout` on the save route);
///  * every save that landed read the caller's whole history again, and every
///    card was built again with it, so fifteen saves were fifteen reads of a
///    list that only grows and three hundred card builds.
///
/// [PredictionSaveGate] lets a few saves out at a time, in the order they
/// asked. [PredictionHistoryRefresher] reads the history again at once for
/// the first save of a burst, and once more, after its window, for all the
/// others.
///
/// Hand-written (plain `Provider`, no `@riverpod`), like the files beside it.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../history/prediction_history_providers.dart';

/// Most saves on the wire at once, across every card of the app.
const int maxConcurrentPredictionSaves = 3;

/// How long the saves of one burst are gathered into a single history read.
const Duration predictionHistoryRefreshWindow = Duration(seconds: 2);

/// Lets at most [limit] jobs run at once; the others wait and start in the
/// order they asked, as places free up.
class PredictionSaveGate {
  /// Creates a gate with [limit] places.
  PredictionSaveGate({this.limit = maxConcurrentPredictionSaves})
    : assert(limit > 0, 'a gate needs at least one place');

  /// How many jobs may run at once.
  final int limit;

  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  /// Jobs running now.
  int get running => _running;

  /// Jobs waiting for a place.
  int get waiting => _waiting.length;

  /// Runs [job] once a place is free and returns what it returns. A job
  /// that throws still frees its place, and its error reaches the caller.
  Future<T> run<T>(Future<T> Function() job) async {
    if (_running < limit) {
      _running++;
    } else {
      // The place is handed over by the job that finishes: `_running`
      // stays as it is until nobody is waiting.
      final Completer<void> turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    try {
      return await job();
    } finally {
      if (_waiting.isEmpty) {
        _running--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}

/// The one gate of the app's prediction saves.
final predictionSaveGateProvider = Provider<PredictionSaveGate>(
  (ref) => PredictionSaveGate(),
);

/// Reads the caller's history again after saves, without one read per save.
///
/// The first [request] of a burst calls [refresh] at once, as every save did
/// before. Requests made while the [window] it opened is still running are
/// gathered: when the window closes they make one more [refresh], which
/// opens a window of its own.
class PredictionHistoryRefresher {
  /// Creates a refresher that calls [refresh]; [alive] says whether the
  /// owner still stands (a sign-out replaces the whole container).
  PredictionHistoryRefresher({
    required this.refresh,
    this.alive = _always,
    this.window = predictionHistoryRefreshWindow,
  });

  /// Reads the history again.
  final void Function() refresh;

  /// Whether [refresh] may still be called.
  final bool Function() alive;

  /// How long a burst is gathered.
  final Duration window;

  static bool _always() => true;

  Timer? _open;
  bool _again = false;

  /// Asks for the history to be read again.
  void request() {
    if (!alive()) return;
    if (_open != null) {
      _again = true;
      return;
    }
    refresh();
    _open = Timer(window, _close);
  }

  void _close() {
    _open = null;
    if (!_again) return;
    _again = false;
    request();
  }

  /// Stops the pending window; nothing is read after it.
  void dispose() {
    _open?.cancel();
    _open = null;
    _again = false;
  }
}

/// The one refresher of the app's history reads.
final predictionHistoryRefresherProvider = Provider<PredictionHistoryRefresher>(
  (ref) {
    final PredictionHistoryRefresher refresher = PredictionHistoryRefresher(
      refresh: () => ref.invalidate(myFixturePredictionsProvider),
      alive: () => ref.mounted,
    );
    ref.onDispose(refresher.dispose);
    return refresher;
  },
);
