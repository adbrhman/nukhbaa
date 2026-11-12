import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One account linked to a person (script 263, migration 0209).
final class LinkedAccount {
  /// Creates the line.
  const LinkedAccount({
    required this.user,
    required this.counted,
    required this.hidden,
  });

  /// The account.
  final User user;

  /// Whether it counts on the boards: the main account and the second one.
  final bool counted;

  /// Whether it is hidden now (by the link, or by the owner before it).
  final bool hidden;
}

/// One person: the main account first, then the others.
final class LinkedPerson {
  /// Creates the person.
  const LinkedPerson({required this.main, required this.accounts});

  /// The main account's id.
  final UserId main;

  /// Every account of the person, the main one first, then the counted.
  final List<LinkedAccount> accounts;
}

/// Why a person could not be set.
enum PersonLinkRefusal {
  /// Under two accounts.
  tooFew,

  /// One account named twice.
  duplicate,

  /// An id not on file.
  unknown,

  /// An account already linked to another person.
  taken,
}

/// Port for one person's accounts (script 263, migration 0209):
/// `identity.person_links` and its two functions, which hide and show the
/// accounts in the same transaction (`identity.users.hidden_at`, 0207).
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class PersonLinkStore {
  /// Every linked person, by main account.
  Future<Result<List<LinkedPerson>>> list();

  /// Sets [main]'s person: [main] and [second] count, [others] are hidden.
  /// `Ok(null)` when set, else why not.
  Future<Result<PersonLinkRefusal?>> set({
    required UserId main,
    required UserId? second,
    required List<UserId> others,
    required UserId by,
  });

  /// Removes [main]'s person, showing again what the link hid; answers how
  /// many accounts were linked.
  Future<Result<int>> unlink(UserId main);
}
