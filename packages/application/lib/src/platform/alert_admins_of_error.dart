/// Use-case: tell the admins about an error worth their attention
/// (migration 0089).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/notification/ports/admin_push_target_reader.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:application/src/platform/ports/error_alert_repository.dart';
import 'package:application/src/platform/ports/error_log_repository.dart';
import 'package:shared/shared.dart';

/// Pushes one alert to every active admin when an occurrence makes an error
/// worth their attention: a new critical error, a new error in a fresh
/// release, more than 20 an hour, or a fixed error that came back
/// (`ops.claim_error_alert`). The database claims the alert first, so one
/// error alerts at most once an hour however many reports arrive together.
///
/// The push carries the problem code, where it came from and the redacted
/// message -- never a stack or a request.
///
/// Never throws; returns the reason it alerted for, or null.
final class AlertAdminsOfError {
  /// Creates the use-case over its collaborators.
  const AlertAdminsOfError({
    required ErrorAlertRepository alerts,
    required AdminPushTargetReader targets,
    required PushSender sender,
    required Clock clock,
  }) : _alerts = alerts,
       _targets = targets,
       _sender = sender,
       _clock = clock;

  final ErrorAlertRepository _alerts;
  final AdminPushTargetReader _targets;
  final PushSender _sender;
  final Clock _clock;

  /// The push title for each reason.
  static String titleFor(String reason) => switch (reason) {
    'reopened' => 'سجل الأخطاء: عاد خطأ بعد إصلاحه',
    'new_critical' => 'سجل الأخطاء: خطأ حرج جديد',
    'new_in_release' => 'سجل الأخطاء: خطأ جديد في إصدار جديد',
    'hourly_spike' => 'سجل الأخطاء: خطأ يتكرر بكثرة',
    _ => 'سجل الأخطاء',
  };

  /// Alerts about [recorded], one occurrence of [occurrence]'s error.
  Future<Result<String?>> call({
    required RecordedError recorded,
    required ErrorOccurrence occurrence,
  }) async {
    final claimed = await _alerts.claim(
      groupId: recorded.groupId,
      isNew: recorded.isNew,
      reopened: recorded.reopened,
      at: _clock.nowUtc(),
    );
    if (claimed is Err<String?>) {
      return Result.err(claimed.error);
    }
    final String? reason = (claimed as Ok<String?>).value;
    if (reason == null) {
      return const Result.ok(null);
    }
    final targets = await _targets.tokensForActiveAdmins();
    if (targets is Err<List<String>>) {
      return Result.err(targets.error);
    }
    final List<String> tokens = (targets as Ok<List<String>>).value;
    if (tokens.isEmpty) {
      return Result.ok(reason);
    }
    final String message = occurrence.message.length > 90
        ? '${occurrence.message.substring(0, 90)}…'
        : occurrence.message;
    final sent = await _sender.send(
      tokens: tokens,
      title: titleFor(reason),
      body:
          '${occurrence.problemCode} · ${occurrence.source} · '
          '${recorded.occurrences} مرة\n$message',
    );
    return switch (sent) {
      Ok<List<String>>() => Result.ok(reason),
      Err<List<String>>(:final error) => Result.err(error),
    };
  }
}
