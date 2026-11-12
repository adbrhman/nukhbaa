import 'package:application/src/admin/ports/account_name_directory.dart';
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
///
/// With [names] (script 263), the push also names the accounts whose name
/// shares the new one's first and last part ([accountsLike]): maybe one
/// person behind several accounts. A failed read of the names leaves that
/// out, never the push.
final class NotifyNewUserRegistered {
  const NotifyNewUserRegistered({
    required AdminPushTargetReader targets,
    required PushSender sender,
    AccountNameDirectory? names,
  }) : _targets = targets,
       _sender = sender,
       _names = names;

  final AdminPushTargetReader _targets;
  final PushSender _sender;
  final AccountNameDirectory? _names;

  static const String title =
      '\u0645\u0633\u062a\u062e\u062f\u0645 \u062c\u062f\u064a\u062f';
  static const String body =
      '\u062a\u0645 \u062a\u0633\u062c\u064a\u0644 \u0645\u0633\u062a\u062e\u062f\u0645 \u062c\u062f\u064a\u062f \u0641\u064a \u062a\u0637\u0628\u064a\u0642 \u0646\u062e\u0628\u0629.';

  /// The push of script 202: the player's name and e-mail, so an admin
  /// knows who joined before opening anything; without a name, the line
  /// [body].
  ///
  /// [similar] (script 263) adds "يشبه: «X»، «Y»".
  static String bodyFor({
    String? displayName,
    String? email,
    List<String> similar = const <String>[],
  }) {
    final String name = (displayName ?? '').trim();
    if (name.isEmpty) {
      return body;
    }
    final String mail = (email ?? '').trim();
    final String who = mail.isEmpty ? '«$name»' : '«$name» · $mail';
    if (similar.isEmpty) {
      return who;
    }
    return '$who · يشبه: ${similar.map((String s) => '«$s»').join('، ')}';
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
      body: bodyFor(
        displayName: displayName,
        email: email,
        similar: await _similar(displayName, email),
      ),
      link: PushLink.newPlayers,
    );
    return switch (sent) {
      Ok<List<String>>() => const Result.ok(null),
      Err<List<String>>(:final error) => Result.err(error),
    };
  }

  /// The names that share [displayName]'s first and last part, the new
  /// account ([email]) left out; empty when unknown.
  Future<List<String>> _similar(String? displayName, String? email) async {
    final AccountNameDirectory? names = _names;
    final String name = (displayName ?? '').trim();
    if (names == null || name.isEmpty) {
      return const <String>[];
    }
    final Result<List<AccountName>> all = await names.all();
    if (all is! Ok<List<AccountName>>) {
      return const <String>[];
    }
    return <String>[
      for (final AccountName other in accountsLike(
        all.value,
        name: name,
        exceptEmail: email,
        limit: 2,
      ))
        other.displayName,
    ];
  }
}
