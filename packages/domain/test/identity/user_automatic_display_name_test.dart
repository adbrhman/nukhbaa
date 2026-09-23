import 'package:domain/domain.dart';
import 'package:test/test.dart';

User _user({String? email, required String displayName}) => User(
  id: const UserId('aaaaaaaa-0000-0000-0000-000000000001'),
  email: email,
  role: PlatformRole.user,
  status: UserStatus.active,
  displayName: displayName,
);

void main() {
  group('User.hasAutomaticDisplayName', () {
    test('the email local part the database assigned is automatic', () {
      final user = _user(
        email: 'n72914939@gmail.com',
        displayName: 'n72914939',
      );
      expect(user.automaticDisplayName, 'n72914939');
      expect(user.hasAutomaticDisplayName, isTrue);
    });

    test('without an email the database assigns Player', () {
      final user = _user(displayName: 'Player');
      expect(user.automaticDisplayName, 'Player');
      expect(user.hasAutomaticDisplayName, isTrue);
    });

    test('a chosen name is not automatic', () {
      final user = _user(email: 'n72914939@gmail.com', displayName: 'Ali');
      expect(user.hasAutomaticDisplayName, isFalse);
    });
  });
}
