library;

/// Stable UI-facing status for a match, independent of whatever raw string
/// or shape the backend happens to send.
///
/// No widget should ever branch on a raw backend value directly — an
/// adapter layer (introduced alongside the fixture/match domain model)
/// is responsible for mapping backend data onto this enum, converting any
/// unrecognized or null value to [unknown] rather than letting it reach
/// the UI. This file only defines the contract; nothing constructs or
/// consumes it yet.
enum UiMatchStatus { upcoming, live, finished, postponed, cancelled, unknown }

/// Stable UI-facing status for the current user's prediction on a match.
enum UiPredictionStatus { none, saved, locked, calculated }

/// Which prediction input a match supports, as decided by the backend —
/// never assumed by the UI.
enum UiPredictionMode { exactScore, outcome, unsupported }
