import 'package:application/application.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _Finder implements UnscoredResultFinder {
  _Finder(this._answer);

  final Result<List<String>> _answer;
  DateTime? from;
  DateTime? before;
  int? limit;

  @override
  Future<Result<List<String>>> fixturesWithUnscoredPredictions({
    required DateTime recordedFrom,
    required DateTime recordedBefore,
    required int limit,
  }) async {
    from = recordedFrom;
    before = recordedBefore;
    this.limit = limit;
    return _answer;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 3, 12);

  group('RescoreUnscoredResults', () {
    test(
      'scores every fixture the finder reports, inside the window',
      () async {
        final finder = _Finder(const Result.ok(<String>['f1', 'f2']));
        final scored = <String>[];
        final sweep = RescoreUnscoredResults(
          finder: finder,
          rescore: ({required String fixtureId}) async {
            scored.add(fixtureId);
            return const Result.ok(null);
          },
        );

        final result = await sweep(now: now);

        expect((result as Ok<int>).value, 2);
        expect(scored, <String>['f1', 'f2']);
        expect(finder.from, now.subtract(const Duration(days: 3)));
        expect(finder.before, now.subtract(const Duration(minutes: 10)));
        expect(finder.limit, 10);
      },
    );

    test(
      'one failing fixture does not stop the others, and is reported',
      () async {
        final scored = <String>[];
        final sweep = RescoreUnscoredResults(
          finder: _Finder(const Result.ok(<String>['bad', 'good'])),
          rescore: ({required String fixtureId}) async {
            if (fixtureId == 'bad') {
              return const Result.err(
                AppError.transient('db.query_failed', 'Database query failed'),
              );
            }
            scored.add(fixtureId);
            return const Result.ok(null);
          },
        );

        final result = await sweep(now: now);

        expect(scored, <String>['good']);
        expect((result as Err<int>).error.code, 'db.query_failed');
      },
    );

    test('nothing to finish scores nothing', () async {
      var calls = 0;
      final sweep = RescoreUnscoredResults(
        finder: _Finder(const Result.ok(<String>[])),
        rescore: ({required String fixtureId}) async {
          calls++;
          return const Result.ok(null);
        },
      );

      final result = await sweep(now: now);

      expect((result as Ok<int>).value, 0);
      expect(calls, 0);
    });

    test('a failed read is returned and scores nothing', () async {
      var calls = 0;
      final sweep = RescoreUnscoredResults(
        finder: _Finder(
          const Result.err(AppError.transient('db.query_timeout', 'timeout')),
        ),
        rescore: ({required String fixtureId}) async {
          calls++;
          return const Result.ok(null);
        },
      );

      final result = await sweep(now: now);

      expect((result as Err<int>).error.code, 'db.query_timeout');
      expect(calls, 0);
    });
  });
}
