import 'package:application/application.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Answers a scripted table, or an error, and counts the calls.
final class _FakeStandingsSource implements LeagueStandingsSource {
  Result<List<LeagueStandingRow>> answer = const Result.ok(
    <LeagueStandingRow>[],
  );
  final List<String> calls = <String>[];

  @override
  Future<Result<List<LeagueStandingRow>>> standingsOf({
    required String leagueRef,
    required int season,
  }) async {
    calls.add('$leagueRef|$season');
    return answer;
  }
}

/// Keeps one table per league in memory.
final class _FakeStandingsStore implements LeagueStandingsStore {
  final Map<String, StoredLeagueTable> kept = {};
  int saves = 0;

  @override
  Future<Result<StoredLeagueTable?>> latest({
    required String source,
    required String leagueRef,
  }) async => Result.ok(kept['$source:$leagueRef']);

  @override
  Future<Result<void>> save({
    required String source,
    required String leagueRef,
    required List<LeagueStandingRow> rows,
    required DateTime fetchedAt,
  }) async {
    saves++;
    kept['$source:$leagueRef'] = StoredLeagueTable(
      rows: rows,
      fetchedAt: fetchedAt,
    );
    return const Result.ok(null);
  }
}

const _ref = StandingsRef(source: 'highlightly', leagueRef: '262041');
final _now = DateTime.utc(2026, 11, 2, 21, 5);
final _day = DateTime.utc(2026, 11, 4);

const _rows = [
  LeagueStandingRow(teamExternalId: 'hil', position: 1),
  LeagueStandingRow(teamExternalId: 'nas', position: 2),
  LeagueStandingRow(teamExternalId: 'gone', position: 3),
];

void main() {
  late _FakeStandingsSource source;
  late _FakeStandingsStore store;
  late FakeProviderSyncStore identities;
  late LeagueTables tables;
  late List<String> notes;

  setUp(() {
    source = _FakeStandingsSource();
    store = _FakeStandingsStore();
    identities = FakeProviderSyncStore()
      ..seed('team', 'hil', 'team-hilal')
      ..seed('team', 'nas', 'team-nassr');
    tables = LeagueTables(
      sources: {'highlightly': source},
      store: store,
      identities: identities,
    );
    notes = <String>[];
  });

  test('a season is named by the year it starts in', () {
    expect(seasonStartOf(DateTime.utc(2026, 11, 4)), 2026);
    expect(seasonStartOf(DateTime.utc(2027, 3, 1)), 2026);
    expect(seasonStartOf(DateTime.utc(2027, 7, 1)), 2027);
  });

  test(
    'no table kept: the provider is asked once and the table kept',
    () async {
      source.answer = const Result.ok(_rows);

      final table = await tables.tableOf(
        _ref,
        nowUtc: _now,
        riyadhDay: _day,
        notes: notes,
      );

      expect(source.calls, ['262041|2026']);
      expect(store.saves, 1);
      expect(table!.size, 3);
      expect(table.placeOf('team-hilal')!.position, 1);
      expect(table.placeOf('team-nassr')!.position, 2);
      // An unmapped club keeps its place in the count, not in the map.
      expect(table.places, hasLength(2));
      expect(table.placeOf('team-other'), isNull);
      expect(
        table.placeOf('team-other', outsideIsLast: true)!.inTable,
        isFalse,
      );
    },
  );

  test('a table kept less than 20 hours ago is used without asking', () async {
    store.kept[_ref.key] = StoredLeagueTable(
      rows: _rows,
      fetchedAt: _now.subtract(const Duration(hours: 19)),
    );

    final table = await tables.tableOf(
      _ref,
      nowUtc: _now,
      riyadhDay: _day,
      notes: notes,
    );

    expect(source.calls, isEmpty);
    expect(table!.placeOf('team-nassr')!.position, 2);
  });

  test('a failed read falls back to the last table kept', () async {
    store.kept[_ref.key] = StoredLeagueTable(
      rows: _rows,
      fetchedAt: _now.subtract(const Duration(days: 3)),
    );
    source.answer = const Result.err(
      AppError.transient('football_data.provider_quota', 'reserve'),
    );

    final table = await tables.tableOf(
      _ref,
      nowUtc: _now,
      riyadhDay: _day,
      notes: notes,
    );

    expect(source.calls, hasLength(1));
    expect(store.saves, 0);
    expect(table!.placeOf('team-hilal')!.position, 1);
    expect(notes.single, contains('read failed'));
  });

  test(
    'nothing read and nothing kept: no table, and the run goes on',
    () async {
      source.answer = const Result.err(
        AppError.transient('football_data.provider_http_500', 'down'),
      );

      final table = await tables.tableOf(
        _ref,
        nowUtc: _now,
        riyadhDay: _day,
        notes: notes,
      );

      expect(table, isNull);
      expect(notes.single, contains('no table kept'));
    },
  );
}
