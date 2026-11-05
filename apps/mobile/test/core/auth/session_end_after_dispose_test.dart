import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/token_store.dart';
import 'package:mobile/core/providers.dart';

/// KTBH, 6MU5, TT7Q (Android, UnmountedRefException): a session-ending
/// `401` that reaches `apiTransport` after its container was replaced.
void main() {
  // The Ref of a live provider, the way `apiTransport` holds its own.
  final Provider<Ref> refOf = Provider<Ref>((Ref ref) => ref);

  test('a session that ends in a live container forgets the token and '
      'signals the expiry', () async {
    final InMemoryTokenStore store = InMemoryTokenStore('token');
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final Ref ref = container.read(refOf);

    await endSessionOf(ref, store);

    expect(await store.read(), isNull);
    expect(container.read(sessionExpiryProvider), 1);
  });

  test('a 401 that lands after the container was replaced throws nothing '
      'and leaves the next account\'s token alone', () async {
    final InMemoryTokenStore store = InMemoryTokenStore('new-token');
    final ProviderContainer container = ProviderContainer();
    final Ref ref = container.read(refOf);
    container.dispose();

    await expectLater(endSessionOf(ref, store), completes);

    expect(await store.read(), 'new-token');
  });
}
