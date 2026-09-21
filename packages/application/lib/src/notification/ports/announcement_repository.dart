import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One user an announcement is about to reach, together with the devices that
/// can also be rung.
///
/// [tokens] MAY be empty: a user with no registered device still gets the
/// in-app notification — they simply see it the next time they open the app.
/// This is the difference from `ScoreNoticeTarget`/`ReminderTarget`, whose
/// whole purpose is a push and which therefore skip device-less users.
final class AnnouncementRecipient {
  /// Creates a recipient.
  const AnnouncementRecipient({
    required this.userId,
    required this.tokens,
    this.utcOffsetMinutes,
  });

  /// The user who receives the notification.
  final UserId userId;

  /// Their registered FCM tokens; empty when they have no device on file.
  final List<String> tokens;

  /// Minutes the user's clock is ahead of UTC, as the app last reported it,
  /// or null if it never did. Read by `QuietHours` (P3-2) and nothing else.
  final int? utcOffsetMinutes;
}

/// Persistence port for admin announcements (migration 0043).
///
/// Backed by `PostgresAnnouncementRepository`. Speaks in the domain
/// [Announcement] aggregate and typed ids, never rows or SQL.
///
/// General contract (Application ADR §2): MUST NOT throw — every outcome is a
/// typed [Result]; MUST map infrastructure failures to [ErrorKind.transient].
/// Tier-3 throughout: a failure here is confined to the announcement
/// use-case and never reaches a Tier-1 core operation.
abstract interface class AnnouncementRepository {
  /// Persists a newly published [announcement]. The id is generated
  /// server-side, so a conflict is a genuine failure, not an idempotent skip.
  Future<Result<void>> save(Announcement announcement);

  /// Reads the announcements named by [ids], in any order; unknown ids are
  /// simply absent from the result (never an error), so a notification whose
  /// announcement was deleted degrades to a bare row rather than a failed
  /// inbox read. An empty [ids] resolves to an empty list without a query.
  Future<Result<List<Announcement>>> findByIds(List<AnnouncementId> ids);

  /// Every **active** user who should receive a broadcast, with their device
  /// tokens (possibly empty). Suspended users are excluded — a sanctioned
  /// account is not part of the audience.
  Future<Result<List<AnnouncementRecipient>>> audience();
}
