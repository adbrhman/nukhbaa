/// The rule that keeps the second and third paths of the Elite Cup in the
/// hall of fame for 48 hours after their title (script 350).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leaderboards/cup_champions_providers.dart';

CupChampionDto _champion(int place, String? decidedAt) => CupChampionDto(
  monthStart: '2026-11-01',
  place: place,
  how: 'final',
  userId: 'u$place',
  displayName: 'p$place',
  decidedAt: decidedAt,
);

void main() {
  final DateTime now = DateTime.utc(2026, 11, 7, 12);
  String ago(Duration d) => now.subtract(d).toIso8601String();

  List<int> placesOf(List<CupChampionDto> list) => <int>[
    for (final CupChampionDto c in list) c.place,
  ];

  test('the runner-up window is two days', () {
    expect(kCupRunnerUpDays, 2);
  });

  test('path 1 always stays, however old its title or its date', () {
    final List<CupChampionDto> all = <CupChampionDto>[
      _champion(1, ago(const Duration(days: 400))),
      _champion(1, null),
      _champion(1, 'not-a-date'),
    ];
    expect(visibleCupChampions(all, now), all);
  });

  test('a runner-up stays up to 47:59 and goes at 48:00', () {
    expect(
      placesOf(
        visibleCupChampions(<CupChampionDto>[
          _champion(2, ago(const Duration(hours: 47, minutes: 59))),
        ], now),
      ),
      <int>[2],
    );
    expect(
      visibleCupChampions(<CupChampionDto>[
        _champion(2, ago(const Duration(hours: 48))),
        _champion(3, ago(const Duration(hours: 48, seconds: 1))),
      ], now),
      isEmpty,
    );
  });

  test('paths 2 and 3 follow the same rule', () {
    final List<CupChampionDto> fresh = <CupChampionDto>[
      _champion(2, ago(const Duration(hours: 1))),
      _champion(3, ago(const Duration(hours: 1))),
    ];
    expect(placesOf(visibleCupChampions(fresh, now)), <int>[2, 3]);
    final List<CupChampionDto> old = <CupChampionDto>[
      _champion(2, ago(const Duration(days: 3))),
      _champion(3, ago(const Duration(days: 3))),
    ];
    expect(visibleCupChampions(old, now), isEmpty);
  });

  test('a missing or unreadable decided_at hides a runner-up', () {
    expect(
      visibleCupChampions(<CupChampionDto>[
        _champion(2, null),
        _champion(3, ''),
        _champion(2, 'not-a-date'),
      ], now),
      isEmpty,
    );
  });

  test('a title decided in the future is shown', () {
    final String later = now.add(const Duration(hours: 3)).toIso8601String();
    expect(
      placesOf(visibleCupChampions(<CupChampionDto>[_champion(3, later)], now)),
      <int>[3],
    );
  });

  test('an instant with an offset is read as the same moment', () {
    // 2026-11-05 12:00:00 UTC is exactly 48 hours before the clock.
    expect(
      placesOf(
        visibleCupChampions(<CupChampionDto>[
          _champion(2, '2026-11-05T15:00:01+03:00'),
        ], now),
      ),
      <int>[2],
    );
    expect(
      visibleCupChampions(<CupChampionDto>[
        _champion(2, '2026-11-05T15:00:00+03:00'),
      ], now),
      isEmpty,
    );
  });

  test('the order is kept and the input list is not changed', () {
    final List<CupChampionDto> all = <CupChampionDto>[
      _champion(1, null),
      _champion(2, ago(const Duration(days: 5))),
      _champion(3, ago(const Duration(hours: 2))),
    ];
    expect(placesOf(visibleCupChampions(all, now)), <int>[1, 3]);
    expect(placesOf(all), <int>[1, 2, 3]);
    expect(visibleCupChampions(<CupChampionDto>[], now), isEmpty);
  });
}
