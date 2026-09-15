/// A one-bit "the month feed is out of date" signal.
///
/// Saving a prediction changes the server-computed win shares that ride along
/// with `GET /feed/current-month-fixtures`, so the card used to invalidate the
/// whole feed after every single save: predicting twenty matches meant twenty
/// full-month reads over a phone network, on top of twenty history reads.
///
/// The card now only raises this flag. `CurrentMonthFixturesScreen` lowers it
/// on its own minute tick (and on pull-to-refresh), so the shares are at most
/// a minute stale and twenty saves cost one feed read instead of twenty.
///
/// Hand-written (plain `Notifier` + `NotifierProvider`, no `@riverpod`) for the
/// same reason as `fixture_prediction_controller.dart`: no build_runner output
/// is needed for it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the flag. `true` means a prediction was saved since the last feed
/// refresh.
class FeedRefreshSignal extends Notifier<bool> {
  @override
  bool build() => false;

  /// Raised by any successful prediction save.
  void request() {
    if (!state) state = true;
  }

  /// Lowered by whoever actually refreshes the feed.
  void consume() {
    if (state) state = false;
  }
}

/// The provider exposing [FeedRefreshSignal].
final feedRefreshSignalProvider = NotifierProvider<FeedRefreshSignal, bool>(
  FeedRefreshSignal.new,
);
