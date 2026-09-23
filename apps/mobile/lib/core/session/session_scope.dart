/// A root [ProviderScope] that starts over when the signed-in account leaves.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

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
    child: widget.child,
  );
}
