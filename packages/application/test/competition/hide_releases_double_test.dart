/// Hiding a fixture frees its doubles, and the players who doubled it are
/// told (script 89, migration 0172), through the admin command that hides:
/// [AdminSetFixturesHidden] with its [NotifyDoubleReleased].
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart' show InMemoryAuditLogRepository;
import '../notification/fakes.dart' show InMemoryNotificationRepository;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _admin = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

const _today = 'ffffffff-0000-4000-8000-0000000000f1';
const _past = 'ffffffff-0000-4000-8000-0000000000f2';
const _test = 'ffffffff-0000-4000-8000-0000000000f3';

// Participants and the users behind them.
const _doubler = 'aaaaaaaa-0000-4000-8000-0000000000a1';
const _single = 'aaaaaaaa-0000-4000-8000-0000000000a2';
const _noDevice = 'aaaaaaaa-0000-4000-8000-0000000000a3';
const _asleep = 'aaaaaaaa-0000-4000-8000-0000000000a4';
const _doublerUser = 'bbbbbbbb-0000-4000-8000-0000000000b1';
const _singleUser = 'bbbbbbbb-0000-4000-8000-0000000000b2';
const _asleepUser = 'bbbbbbbb-0000-4000-8000-0000000000b4';

// 18:00 in Riyadh on 15 October; the match of the day kicks off at 21:00.
final _now = DateTime.utc(2026, 10, 15, 15);
final _todayKickoff = DateTime.utc(2026, 10, 15, 18);
final _pastKickoff = DateTime.utc(2026, 10, 13, 18);

FixtureSchedule _schedule(
  String id,
  DateTime kickoffAt, {
  bool isTest = false,
}) => FixtureSchedule.fromStored(
  fixture: FixtureRef(id),
  homeTeam: 'الأهلي',
  awayTeam: 'النصر',
  kickoffAt: kickoffAt,
  isTest: isTest,
);

FixturePrediction _prediction(
  String fixtureId,
  String participant,
  DateTime kickoffAt, {
  required bool isDouble,
}) =>
    (FixturePrediction.submit(
              id: PredictionId(
                'cccccccc-0000-4000-8000-${participant.substring(24)}',
              ),
              fixture: FixtureRef(fixtureId),
              participantId: ParticipantId(participant),
              lock:
                  (FixtureLock.at(
                            kickoffAt: kickoffAt,
                            nowUtc: kickoffAt.subtract(const Duration(days: 1)),
                          )
                          as Ok<FixtureLock>)
                      .value,
              homeGoals: 1,
              awayGoals: 0,
              isDouble: isDouble,
            )
            as Ok<FixturePrediction>)
        .value;

void main() {
  late _Store store;
  late InMemoryNotificationRepository notifications;
  late _Sender sender;
  late AdminSetFixturesHidden command;

  setUp(() {
    store = _Store();
    notifications = InMemoryNotificationRepository();
    sender = _Sender();
    final schedules = FakeFixtureScheduleRepository()
      ..seed(_schedule(_today, _todayKickoff))
      ..seed(_schedule(_past, _pastKickoff))
      ..seed(_schedule(_test, _todayKickoff, isTest: true));
    final predictions = FakeFixturePredictionRepository();
    for (final (String fixture, String participant, bool isDouble)
        in <(String, String, bool)>[
          (_today, _doubler, true),
          (_today, _single, false),
          (_today, _noDevice, true),
          (_today, _asleep, true),
        ]) {
      predictions.seedPrediction(
        _prediction(fixture, participant, _todayKickoff, isDouble: isDouble),
        _now,
      );
    }
    predictions
      ..seedPrediction(
        _prediction(_past, _doubler, _pastKickoff, isDouble: true),
        _now,
      )
      ..seedPrediction(
        _prediction(_test, _doubler, _todayKickoff, isDouble: true),
        _now,
      );

    command = AdminSetFixturesHidden(
      store: store,
      auditRecorder: AuditRecorder(
        auditLog: InMemoryAuditLogRepository(),
        idGenerator: FakeIdGenerator(['99999991-9999-4999-8999-999999999999']),
        clock: FixedClock(_now),
      ),
      notifyDoubleReleased: NotifyDoubleReleased(
        schedules: schedules,
        predictions: predictions,
        targets: _Targets(),
        sender: sender,
        create: CreateNotification(
          notifications: notifications,
          idGenerator: FakeIdGenerator([
            '77777771-7777-4777-8777-777777777777',
            '77777772-7777-4777-8777-777777777777',
            '77777773-7777-4777-8777-777777777777',
          ]),
          clock: FixedClock(_now),
        ),
        clock: FixedClock(_now),
      ),
    );
  });

  Future<void> hide(List<String> ids, {bool hidden = true}) async {
    final result = await command(
      principal: adminPrincipal(_admin),
      fixtureIds: ids,
      hidden: hidden,
    );
    expect(result, isA<Ok<List<FixtureRef>>>());
  }

  test('the players who doubled a match hidden today are told', () async {
    await hide([_today, _past, _test]);

    // An inbox row for each doubler with a device; the one in the quiet
    // hours too, whose phone stays silent.
    expect(notifications.countFor(_doublerUser), 1);
    expect(notifications.countFor(_asleepUser), 1);
    expect(notifications.countFor(_singleUser), 0);

    expect(sender.sends, hasLength(1));
    final send = sender.sends.single;
    expect(send.tokens, ['doubler-phone']);
    expect(send.title, NotifyDoubleReleased.title);
    expect(send.body, contains('الأهلي - النصر'));
    expect(send.link, PushLink.fixtures);
  });

  test('a day already over and a test match say nothing', () async {
    await hide([_past, _test]);

    expect(notifications.countFor(_doublerUser), 0);
    expect(sender.sends, isEmpty);
  });

  test('hiding the same match again says nothing new', () async {
    await hide([_today]);
    await hide([_today], hidden: false);
    await hide([_today]);

    expect(notifications.countFor(_doublerUser), 1);
    expect(sender.sends, hasLength(1));
  });

  test('showing a match says nothing', () async {
    store.hidden.add(_today);

    await hide([_today], hidden: false);

    expect(notifications.countFor(_doublerUser), 0);
    expect(sender.sends, isEmpty);
  });
}

/// The visibility column as a set of hidden ids.
final class _Store implements FixtureVisibilityStore {
  final Set<String> hidden = {};

  @override
  Future<Result<List<FixtureRef>>> setHidden(
    List<FixtureRef> fixtures, {
    required bool hidden,
  }) async {
    final changed = <FixtureRef>[];
    for (final f in fixtures) {
      if (this.hidden.contains(f.value) == hidden) continue;
      if (hidden) {
        this.hidden.add(f.value);
      } else {
        this.hidden.remove(f.value);
      }
      changed.add(f);
    }
    return Result.ok(changed);
  }
}

/// The players' devices: the doubler's phone, a single's phone, and a
/// doubler whose clock reads 23:30 (quiet hours). The third doubler has no
/// device, so is no target at all.
final class _Targets implements ScoreAnnouncementRepository {
  static final Map<String, ScoreNoticeTarget> _byParticipant = {
    _doubler: const ScoreNoticeTarget(
      participantId: ParticipantId(_doubler),
      userId: UserId(_doublerUser),
      tokens: ['doubler-phone'],
      utcOffsetMinutes: 180,
    ),
    _single: const ScoreNoticeTarget(
      participantId: ParticipantId(_single),
      userId: UserId(_singleUser),
      tokens: ['single-phone'],
      utcOffsetMinutes: 180,
    ),
    _asleep: const ScoreNoticeTarget(
      participantId: ParticipantId(_asleep),
      userId: UserId(_asleepUser),
      tokens: ['asleep-phone'],
      utcOffsetMinutes: 510,
    ),
  };

  @override
  Future<Result<List<ScoreNoticeTarget>>> targetsForParticipants(
    List<ParticipantId> participantIds,
  ) async => Result.ok([
    for (final id in participantIds)
      if (_byParticipant[id.value] case final ScoreNoticeTarget target) target,
  ]);

  @override
  Future<Result<String?>> matchLabel(FixtureRef fixture) =>
      throw StateError('the label comes from the schedule');

  @override
  Future<Result<int>> withdrawExactNotices({
    required FixtureRef fixture,
    required List<ParticipantId> keep,
  }) => throw StateError('nothing is withdrawn');
}

typedef _Send = ({
  List<String> tokens,
  String title,
  String body,
  String? link,
});

final class _Sender implements PushSender {
  final List<_Send> sends = <_Send>[];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    sends.add((tokens: tokens, title: title, body: body, link: link));
    return const Result.ok(<String>[]);
  }
}
