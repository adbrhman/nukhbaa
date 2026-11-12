import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Where a club crest stands (script 265, migration 0210).
enum CrestStatus {
  /// In the app's list: shown.
  active,

  /// Out of the list until the owner shows it again.
  hidden,

  /// Its file erased for good.
  deleted;

  /// The stored token.
  String get wireValue => name;

  /// The status of [raw], or null.
  static CrestStatus? tryParse(String? raw) {
    for (final CrestStatus status in values) {
      if (status.name == raw) return status;
    }
    return null;
  }
}

/// One club crest.
final class ClubCrest {
  /// Creates the line.
  const ClubCrest({
    required this.slug,
    required this.objectPath,
    required this.status,
    this.reason,
    this.complainant,
    this.changedAt,
  });

  /// The app's name for it (`arsenal`).
  final String slug;

  /// Its file in the bucket `crests` (`clubs/arsenal.1a2b3c4d.png`).
  final String objectPath;

  /// Where it stands.
  final CrestStatus status;

  /// Why it was last changed.
  final String? reason;

  /// Who complained, when someone did.
  final String? complainant;

  /// When it was last changed.
  final DateTime? changedAt;
}

/// Every club crest, and whether club crests show at all.
final class CrestList {
  /// Creates the list.
  const CrestList({required this.clubsEnabled, required this.crests});

  /// Whether club crests show at all.
  final bool clubsEnabled;

  /// Every club crest, by slug.
  final List<ClubCrest> crests;
}

/// One change, as the owner's log reads it.
final class CrestEvent {
  /// Creates the line.
  const CrestEvent({
    required this.action,
    required this.reason,
    required this.at,
    this.slug,
    this.complainant,
  });

  /// `hidden`, `shown`, `deleted`, `clubs_on` or `clubs_off`.
  final String action;

  /// The crest, or null for the switch.
  final String? slug;

  /// Why.
  final String reason;

  /// Who complained, when someone did.
  final String? complainant;

  /// When.
  final DateTime at;
}

/// Port for the club crests (script 265, migration 0210):
/// `media.club_crests`, `media.crest_settings` and `media.crest_events`.
/// Every write keeps its event in the same statement.
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class CrestCatalog {
  /// Every club crest and the switch.
  Future<Result<CrestList>> crests();

  /// The latest [limit] changes, newest first.
  Future<Result<List<CrestEvent>>> events({int limit = 50});

  /// Moves [slug] to [to] when it is in [from], keeping the event [action].
  /// `Ok(false)` when there is no such crest or it is not in [from].
  Future<Result<bool>> setStatus({
    required String slug,
    required Set<CrestStatus> from,
    required CrestStatus to,
    required String action,
    required String reason,
    required String? complainant,
    required UserId by,
  });

  /// Turns club crests on or off, keeping the event.
  Future<Result<void>> setClubsEnabled({
    required bool enabled,
    required String reason,
    required UserId by,
  });
}

/// Port: erases one crest file from the bucket `crests` for good.
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class CrestFileEraser {
  /// Erases [objectPath]; a file already gone is not an error.
  Future<Result<void>> erase(String objectPath);
}
