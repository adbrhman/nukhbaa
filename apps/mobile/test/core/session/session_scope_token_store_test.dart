/// Audit L-02: the error reporter and the session must read one token
/// store. `main` hands the same instance to both, through the root
/// overrides of [SessionScope]; this checks that the overridden store is
/// the one every fresh container reads after a sign-out, so a token
/// written by the session is the token the reporter sends.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/token_store.dart';
import 'package:mobile/core/providers.dart';
import 'package:mobile/core/session/session_scope.dart';

void main() {
  testWidgets('every container after a reset reads the one store', (
    tester,
  ) async {
    final InMemoryTokenStore store = InMemoryTokenStore();
    final List<TokenStore> seen = <TokenStore>[];
    final GlobalKey<SessionScopeState> scope = GlobalKey<SessionScopeState>();

    await tester.pumpWidget(
      SessionScope(
        key: scope,
        overrides: [tokenStoreProvider.overrideWithValue(store)],
        child: Consumer(
          builder: (context, ref, _) {
            seen.add(ref.watch(tokenStoreProvider));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await store.write('first');

    scope.currentState!.reset();
    await tester.pump();

    expect(seen.length, greaterThanOrEqualTo(2));
    expect(seen.every((s) => identical(s, store)), isTrue);
    // What the session writes is what a reporter reading [store] sends.
    await seen.last.write('renewed');
    expect(await store.read(), 'renewed');
  });
}
