import 'package:application/src/notification/ports/admin_push_target_reader.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Tier-3 post-registration effect: alert active platform administrators that
/// a new account was created.
///
/// The recipient set is resolved server-side from the admin role, never from
/// the request. Push failure is returned as a typed result so the registration
/// route can keep signup successful and best-effort.
final class NotifyNewUserRegistered {
  const NotifyNewUserRegistered({
    required AdminPushTargetReader targets,
    required PushSender sender,
  }) : _targets = targets,
       _sender = sender;

  final AdminPushTargetReader _targets;
  final PushSender _sender;

  static const String title =
      '\u0645\u0633\u062a\u062e\u062f\u0645 \u062c\u062f\u064a\u062f';
  static const String body =
      '\u062a\u0645 \u062a\u0633\u062c\u064a\u0644 \u0645\u0633\u062a\u062e\u062f\u0645 \u062c\u062f\u064a\u062f \u0641\u064a \u062a\u0637\u0628\u064a\u0642 \u0646\u062e\u0628\u0629.';

  /// The push of script 202: the player's name and e-mail, so an admin
  /// knows who joined before opening anything; without a name, the line
  /// [body].
  static String bodyFor({String? displayName, String? email}) {
    final String name = (displayName ?? '').trim();
    if (name.isEmpty) {
      return body;
    }
    final String mail = (email ?? '').trim();
    return mail.isEmpty ? '«$name»' : '«$name» · $mail';
  }

  /// Alerts the admins that [displayName] ([email]) registered; a tap
  /// opens the list of new players ([PushLink.newPlayers]).
  Future<Result<void>> call({String? displayName, String? email}) async {
    final targetsResult = await _targets.tokensForActiveAdmins();
    if (targetsResult is Err<List<String>>) {
      return Result.err(targetsResult.error);
    }
    final tokens = (targetsResult as Ok<List<String>>).value;
    if (tokens.isEmpty) {
      return const Result.ok(null);
    }

    final sent = await _sender.send(
      tokens: tokens,
      title: title,
      body: bodyFor(displayName: displayName, email: email),
      link: PushLink.newPlayers,
    );
    return switch (sent) {
      Ok<List<String>>() => const Result.ok(null),
      Err<List<String>>(:final error) => Result.err(error),
    };
  }
}
