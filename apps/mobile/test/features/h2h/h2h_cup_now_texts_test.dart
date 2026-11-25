// NK331_02
/// The cup tab's section words and pure helpers (script 331): who is in the
/// cup, the pair "your duel now" shows, the fixture it stands at, the badge of
/// a fixture being played, and a path's status line. No widget, no clock.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';

H2hCupPlayerDto _player(String id, String name, {bool me = false}) =>
    H2hCupPlayerDto(userId: id, displayName: name, groupNumber: 1, isMe: me);

final H2hCupPlayerDto _me = _player('u-me', 'سامي', me: true);
final H2hCupPlayerDto _noura = _player('u-n', 'نورة');
final H2hCupPlayerDto _omar = _player('u-o', 'عمر');
final H2hCupPlayerDto _huda = _player('u-h', 'هدى');

H2hCupBoardFixtureDto _fixture(String id, String state) =>
    H2hCupBoardFixtureDto(
      fixtureId: id,
      homeTeam: 'A',
      awayTeam: 'B',
      state: state,
      homeSide: const H2hCupBoardSideDto.hidden(),
      awaySide: const H2hCupBoardSideDto.hidden(),
    );

H2hCupBoardPairDto _pair(
  H2hCupPlayerDto home,
  H2hCupPlayerDto away, {
  List<H2hCupBoardFixtureDto> fixtures = const <H2hCupBoardFixtureDto>[],
}) => H2hCupBoardPairDto(
  slot: 1,
  home: home,
  away: away,
  decided: false,
  fixtures: fixtures,
);

H2hCupBoardStageDto _stage(
  String round,
  String phase, {
  List<H2hCupBoardPairDto> pairs = const <H2hCupBoardPairDto>[],
  H2hCupPlayerDto? bye,
}) => H2hCupBoardStageDto(
  round: round,
  cupDay: round == 'semi' ? 1 : 2,
  phase: phase,
  attempt: 1,
  pairs: pairs,
  bye: bye,
);

H2hCupBoardPathDto _path(
  int place,
  List<H2hCupBoardStageDto> stages, {
  H2hCupTitleDto? title,
}) => H2hCupBoardPathDto(place: place, stages: stages, title: title);

void main() {
  test('the section headings say what the design says', () {
    expect(h2hCupNowHeading, 'مواجهتك الآن');
    expect(h2hCupFixturesHeading, 'مباريات المواجهة');
    expect(h2hCupMyPathHeading, 'مسارك');
    expect(h2hCupOtherPathsHeading, 'بقية المسارات');
    expect(h2hCupThreePathsHeading, 'المسارات الثلاثة');
    expect(h2hCupTreeHeading, 'شجرة الأدوار');
  });

  test('only a fixture being played wears the live badge', () {
    expect(h2hCupBoardLiveBadge(_fixture('f', 'live')), 'مباشر الآن');
    for (final String state in <String>[
      'not_started',
      'finished',
      'void',
      'unknown',
    ]) {
      expect(h2hCupBoardLiveBadge(_fixture('f', state)), isNull);
    }
  });

  group('the path the caller is in', () {
    test('is found by his pair, on either side', () {
      final H2hCupBoardPathDto other = _path(1, <H2hCupBoardStageDto>[
        _stage(
          'semi',
          'live',
          pairs: <H2hCupBoardPairDto>[_pair(_noura, _omar)],
        ),
      ]);
      final H2hCupBoardPathDto mine = _path(2, <H2hCupBoardStageDto>[
        _stage('semi', 'live', pairs: <H2hCupBoardPairDto>[_pair(_huda, _me)]),
      ]);
      final H2hCupBoardDto board = H2hCupBoardDto(
        paths: <H2hCupBoardPathDto>[other, mine],
      );
      expect(h2hCupBoardMyPath(board), same(mine));
    });

    test('is found by his bye', () {
      final H2hCupBoardPathDto mine = _path(3, <H2hCupBoardStageDto>[
        _stage(
          'semi',
          'scheduled',
          bye: _me,
          pairs: <H2hCupBoardPairDto>[_pair(_noura, _omar)],
        ),
      ]);
      final H2hCupBoardDto board = H2hCupBoardDto(
        paths: <H2hCupBoardPathDto>[mine],
      );
      expect(h2hCupBoardMyPath(board), same(mine));
    });

    test('is none for a player who only watches', () {
      final H2hCupBoardDto board = H2hCupBoardDto(
        paths: <H2hCupBoardPathDto>[
          _path(1, <H2hCupBoardStageDto>[
            _stage(
              'semi',
              'live',
              pairs: <H2hCupBoardPairDto>[_pair(_noura, _omar)],
            ),
          ]),
        ],
      );
      expect(h2hCupBoardMyPath(board), isNull);
      expect(h2hCupBoardNow(board), isNull);
      expect(h2hCupBoardMyPath(const H2hCupBoardDto()), isNull);
    });
  });

  group('your duel now', () {
    test('is his pair in the first stage not decided yet', () {
      final H2hCupBoardPairDto semi = _pair(_me, _noura);
      final H2hCupBoardPairDto finalPair = _pair(_omar, _me);
      final H2hCupBoardPathDto path = _path(1, <H2hCupBoardStageDto>[
        _stage('semi', 'decided', pairs: <H2hCupBoardPairDto>[semi]),
        _stage('final', 'scheduled', pairs: <H2hCupBoardPairDto>[finalPair]),
      ]);
      final H2hCupNow? now = h2hCupBoardNow(
        H2hCupBoardDto(paths: <H2hCupBoardPathDto>[path]),
      );
      expect(now?.pair, same(finalPair));
      expect(now?.stage.round, 'final');
      expect(now?.path, same(path));
    });

    test('is the semi-final while it is being played', () {
      final H2hCupBoardPairDto semi = _pair(_me, _noura);
      final H2hCupNow? now = h2hCupBoardNow(
        H2hCupBoardDto(
          paths: <H2hCupBoardPathDto>[
            _path(1, <H2hCupBoardStageDto>[
              _stage('semi', 'live', pairs: <H2hCupBoardPairDto>[semi]),
              _stage('final', 'waiting'),
            ]),
          ],
        ),
      );
      expect(now?.pair, same(semi));
      expect(now?.stage.round, 'semi');
    });

    test('passes over a stage the path does not play', () {
      final H2hCupBoardPairDto finalPair = _pair(_me, _huda);
      final H2hCupNow? now = h2hCupBoardNow(
        H2hCupBoardDto(
          paths: <H2hCupBoardPathDto>[
            _path(3, <H2hCupBoardStageDto>[
              _stage('semi', 'skipped'),
              _stage('final', 'live', pairs: <H2hCupBoardPairDto>[finalPair]),
            ]),
          ],
        ),
      );
      expect(now?.pair, same(finalPair));
    });

    test('is none while his next stage has no pair yet', () {
      final H2hCupNow? now = h2hCupBoardNow(
        H2hCupBoardDto(
          paths: <H2hCupBoardPathDto>[
            _path(1, <H2hCupBoardStageDto>[
              _stage(
                'semi',
                'decided',
                pairs: <H2hCupBoardPairDto>[_pair(_me, _noura)],
              ),
              _stage('final', 'waiting'),
            ]),
          ],
        ),
      );
      expect(now, isNull);
    });

    test('is none for a player who is out, or whose path is over', () {
      final H2hCupNow? out = h2hCupBoardNow(
        H2hCupBoardDto(
          paths: <H2hCupBoardPathDto>[
            _path(1, <H2hCupBoardStageDto>[
              _stage(
                'semi',
                'decided',
                pairs: <H2hCupBoardPairDto>[_pair(_me, _noura)],
              ),
              _stage(
                'final',
                'scheduled',
                pairs: <H2hCupBoardPairDto>[_pair(_noura, _omar)],
              ),
            ]),
          ],
        ),
      );
      expect(out, isNull);
      final H2hCupNow? over = h2hCupBoardNow(
        H2hCupBoardDto(
          paths: <H2hCupBoardPathDto>[
            _path(1, <H2hCupBoardStageDto>[
              _stage(
                'semi',
                'decided',
                pairs: <H2hCupBoardPairDto>[_pair(_me, _noura)],
              ),
              _stage(
                'final',
                'decided',
                pairs: <H2hCupBoardPairDto>[_pair(_me, _omar)],
              ),
            ]),
          ],
        ),
      );
      expect(over, isNull);
    });
  });

  group('the fixture the duel stands at', () {
    test('is the one being played, even after one not started', () {
      final H2hCupBoardFixtureDto live = _fixture('c', 'live');
      final H2hCupBoardPairDto pair = _pair(
        _me,
        _noura,
        fixtures: <H2hCupBoardFixtureDto>[
          _fixture('a', 'finished'),
          _fixture('b', 'not_started'),
          live,
        ],
      );
      expect(h2hCupBoardCurrentFixture(pair), same(live));
    });

    test('is the first not started when none is being played', () {
      final H2hCupBoardFixtureDto next = _fixture('c', 'not_started');
      final H2hCupBoardPairDto pair = _pair(
        _me,
        _noura,
        fixtures: <H2hCupBoardFixtureDto>[
          _fixture('a', 'finished'),
          _fixture('b', 'void'),
          next,
          _fixture('d', 'not_started'),
        ],
      );
      expect(h2hCupBoardCurrentFixture(pair), same(next));
    });

    test(
      'is none when every fixture is finished or void, or there is none',
      () {
        final H2hCupBoardPairDto done = _pair(
          _me,
          _noura,
          fixtures: <H2hCupBoardFixtureDto>[
            _fixture('a', 'finished'),
            _fixture('b', 'void'),
          ],
        );
        expect(h2hCupBoardCurrentFixture(done), isNull);
        expect(h2hCupBoardCurrentFixture(_pair(_me, _noura)), isNull);
      },
    );
  });

  group('a path status line', () {
    test('names the champion once the path is decided', () {
      final List<H2hCupBoardStageDto> stages = <H2hCupBoardStageDto>[
        _stage('semi', 'decided'),
        _stage('final', 'decided'),
      ];
      expect(
        h2hCupBoardPathStatus(
          _path(
            1,
            stages,
            title: H2hCupTitleDto(how: 'final', champion: _noura),
          ),
        ),
        'بطل المسار: نورة',
      );
      expect(
        h2hCupBoardPathStatus(
          _path(
            1,
            stages,
            title: H2hCupTitleDto(how: 'final', champion: _me),
          ),
        ),
        'أنت بطل هذا المسار',
      );
      expect(
        h2hCupBoardPathStatus(
          _path(1, stages, title: const H2hCupTitleDto(how: 'vacant')),
        ),
        'اللقب شاغر في هذا المسار',
      );
    });

    test('says the stage it stands at and where that stage stands', () {
      expect(
        h2hCupBoardPathStatus(
          _path(1, <H2hCupBoardStageDto>[
            _stage('semi', 'live'),
            _stage('final', 'waiting'),
          ]),
        ),
        'نصف النهائي · جارية',
      );
      expect(
        h2hCupBoardPathStatus(
          _path(1, <H2hCupBoardStageDto>[
            _stage('semi', 'scheduled'),
            _stage('final', 'waiting'),
          ]),
        ),
        'نصف النهائي · مجدولة',
      );
      expect(
        h2hCupBoardPathStatus(
          _path(1, <H2hCupBoardStageDto>[
            _stage('semi', 'decided'),
            _stage('final', 'waiting'),
          ]),
        ),
        'النهائي · بانتظار الجدولة',
      );
    });

    test(
      'says the last stage when none is left to play, and waits when empty',
      () {
        expect(
          h2hCupBoardPathStatus(
            _path(1, <H2hCupBoardStageDto>[
              _stage('semi', 'decided'),
              _stage('final', 'decided'),
            ]),
          ),
          'النهائي · انتهت',
        );
        expect(
          h2hCupBoardPathStatus(_path(1, const <H2hCupBoardStageDto>[])),
          'بانتظار الجدولة',
        );
      },
    );
  });
}
