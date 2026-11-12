import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One account's name, as the close-name check reads it (script 263).
final class AccountName {
  /// Creates the line.
  const AccountName({required this.id, required this.displayName, this.email});

  /// The account.
  final UserId id;

  /// Its display name.
  final String displayName;

  /// Its e-mail, when it has one.
  final String? email;
}

/// Port: every account's name (script 263), for the close-name check of a
/// new account ([accountsLike]). A few hundred short lines, read when an
/// account registers and when an admin opens the new players.
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class AccountNameDirectory {
  /// Every account with a display name.
  Future<Result<List<AccountName>>> all();
}

/// The accounts of [accounts] whose name shares [name]'s person key
/// ([User.personKey]: its first and last part, whatever the spelling),
/// leaving out the account [except] and the e-mail [exceptEmail] (the new
/// account itself), at most [limit], in their order. Empty when [name] has
/// no key.
List<AccountName> accountsLike(
  List<AccountName> accounts, {
  required String name,
  UserId? except,
  String? exceptEmail,
  int limit = 3,
}) {
  final String? key = User.personKey(name);
  if (key == null) {
    return const <AccountName>[];
  }
  final String mail = (exceptEmail ?? '').trim().toLowerCase();
  final List<AccountName> found = <AccountName>[];
  for (final AccountName account in accounts) {
    if (found.length >= limit) {
      break;
    }
    if (account.id == except) {
      continue;
    }
    if (mail.isNotEmpty && (account.email ?? '').trim().toLowerCase() == mail) {
      continue;
    }
    if (User.personKey(account.displayName) == key) {
      found.add(account);
    }
  }
  return found;
}
