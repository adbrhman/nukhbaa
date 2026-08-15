/// Shared display helper for round lifecycle status tokens.
///
/// Extracted out of the (now-removed) browse chain so screens that still
/// need it (e.g. the prediction screen) depend on a small, purpose-built
/// file instead of a deleted browse screen.
library;

import '../../l10n/app_localizations.dart';

/// Humanises a round lifecycle status token.
String roundStatusLabel(AppLocalizations l10n, String token) => switch (token) {
  'open' => l10n.roundStatusOpen,
  'locked' => l10n.roundStatusLocked,
  'scored' => l10n.roundStatusScored,
  _ => token,
};
