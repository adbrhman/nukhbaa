import 'package:shared/shared.dart';

/// The identity of an [Announcement] — one admin broadcast's free text
/// (migration `0043_admin_announcements.sql`).
///
/// A value object (Coding Standards ADR, Section 2), canonically a UUID
/// matching the `notification.announcements` primary key. Kept a distinct id
/// type from `NotificationId` so the text aggregate and the per-recipient
/// notification row are never addressed by each other's id by mistake.
final class AnnouncementId extends EntityId {
  /// Creates an [AnnouncementId] from its canonical UUID string.
  ///
  /// Callers that receive untrusted input should use [tryParse], which
  /// validates shape and returns a typed [Result].
  const AnnouncementId(super.value);

  /// Parses an [AnnouncementId] from an untrusted [raw] string, returning a
  /// validation [AppError] when it is absent or not a canonical (hyphenated,
  /// 36-char) UUID.
  static Result<AnnouncementId> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation(
          'notification.announcement_id_empty',
          'Announcement id is required',
        ),
      );
    }
    if (!_uuid.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'notification.announcement_id_malformed',
          'Announcement id must be a UUID',
        ),
      );
    }
    return Result.ok(AnnouncementId(raw));
  }

  /// Canonical UUID form: 8-4-4-4-12 hexadecimal, case-insensitive.
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
