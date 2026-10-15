/// [SessionScope] gives every provider of the app one retry policy
/// ([appReadRetry], script 74): a transient failure is read again twice,
/// after 3 and then 10 seconds, anything else not at all -- instead of
/// Riverpod's default of ten more tries in about 38 seconds, which turned
/// one slow request into eleven on an overloaded server.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/session/session_scope.dart';
import 'package:shared/shared.dart';

/// Pumps the app's root scope over one provider that always fails with
/// [error]; returns how many times the provider has run so far.
Future<int Function()> _pumpFailing(WidgetTester tester, AppError error) async {
  int runs = 0;
  final FutureProvider<int> failing = FutureProvider<int>((ref) async {
    runs++;
    throw error;
  });
  await tester.pumpWidget(
    SessionScope(
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(failing);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return () => runs;
}

void main() {
  group('appReadRetry', () {
    test('a transient failure: after 3 s, after 10 s, then no more', () {
      const AppError slow = AppError.transient('api_client.timeout', 'slow');

      expect(appReadRetry(0, slow), const Duration(seconds: 3));
      expect(appReadRetry(1, slow), const Duration(seconds: 10));
      expect(appReadRetry(2, slow), isNull);
    });

    test('a refusal, a bad request or another error is not retried', () {
      expect(
        appReadRetry(0, const AppError.validation('x.bad', 'bad')),
        isNull,
      );
      expect(
        appReadRetry(0, const AppError.authorization('x.denied', 'no')),
        isNull,
      );
      expect(
        appReadRetry(0, const AppError.invariant('x.late', 'late')),
        isNull,
      );
      expect(appReadRetry(0, StateError('boom')), isNull);
    });
  });

  testWidgets('in the app scope a transient failure runs three times in all', (
    tester,
  ) async {
    final int Function() runs = await _pumpFailing(
      tester,
      const AppError.transient('api_client.timeout', 'slow'),
    );
    expect(runs(), 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(runs(), 2);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(runs(), 3);

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(runs(), 3, reason: "Riverpod's default would have run it 11 times");
  });

  testWidgets('in the app scope a refusal runs once', (tester) async {
    final int Function() runs = await _pumpFailing(
      tester,
      const AppError.authorization('auth.denied', 'no'),
    );

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(runs(), 1);
  });
}
