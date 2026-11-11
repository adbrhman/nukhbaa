import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart'
    show InMemoryAuditLogRepository, auditRecorderOver, FakeClock;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';

/// Script 261: support reads one player's predictions of the matches not
/// yet started, from his conversation -- the one reading of a prediction
/// before its kickoff. A reason is required, the reading is audited and
/// the player is told in the conversation; nothing else is shown.

const String _conversation = 'cccccccc-0000-4000-8000-000000000001';
const String _player = '22222222-2222-4222-8222-222222222222';
const String _participant = '44444444-4444-4444-8444-444444444444';
const String _played = 'aaaaaaaa-0000-4000-8000-000000000001';
const String _soon = 'aaaaaaaa-0000-4000-8000-000000000002';
const String _later = 'aaaaaaaa-0000-4000-8000-000000000003';

const AuthenticatedUser _admin = AuthenticatedUser(
  userId: UserId('11111111-1111-4111-8111-111111111111'),
  role: PlatformRole.admin,
);

final DateTime _now = DateTime.utc(2026, 11, 12, 15);

/// The conversation of [_player], and the support answers stored in it.
final class _Chats implements SupportChatRepository {
  final List<String> replies = <String>[];
  bool replyFails = false;

  /// Whether the player wrote in the conversation.
  bool playerWrote = true;

  @override
  Future<Result<SupportThread>> conversationThread({
    required SupportConversationId conversationId,
    required int? beforeId,
    required int limit,
  }) async => Result.ok(
    SupportThread(
      status: SupportConversationStatus.open,
      unread: 0,
      hasMore: false,
      messages: <SupportMessage>[
        SupportMessage(
          id: 1,
          senderRole: SupportSenderRole.support,
          body: 'أهلاً',
          createdAt: _now.subtract(const Duration(hours: 2)),
        ),
        if (playerWrote)
          SupportMessage(
            id: 2,
            senderRole: SupportSenderRole.player,
            body: 'توقعي لم يُحفظ',
            createdAt: _now.subtract(const Duration(hours: 1)),
          ),
      ],
    ),
  );

  @override
  Future<Result<SupportConversationSummary>> conversation(
    SupportConversationId conversationId,
  ) async {
    if (conversationId.value != _conversation) {
      return const Result.err(SupportConversationId.notFound);
    }
    return Result.ok(
      SupportConversationSummary(
        id: conversationId,
        playerId: const UserId(_player),
        playerName: 'خالد',
        status: SupportConversationStatus.open,
        lastMessageAt: _now,
        lastMessagePreview: 'توقعي لم يُحفظ',
        lastSenderRole: SupportSenderRole.player,
        supportUnread: 1,
        playerUnread: 0,
      ),
    );
  }

  @override
  Future<Result<SupportMessageStored>> addSupportReply({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportMessageBody body,
    required DateTime at,
  }) async {
    if (replyFails) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    replies.add(body.value);
    return Result.ok(
      SupportMessageStored(
        conversationId: conversationId,
        playerName: 'خالد',
        message: SupportMessage(
          id: replies.length,
          senderRole: SupportSenderRole.support,
          body: body.value,
          createdAt: at,
        ),
        unreadBefore: 0,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

({SupportPeekPredictions peek, _Chats chats, InMemoryAuditLogRepository audit})
_harness() {
  final chats = _Chats();
  final audit = InMemoryAuditLogRepository();
  final predictions = FakeFixturePredictionRepository()
    ..seedParticipantOwner(
      const ParticipantId(_participant),
      const UserId(_player),
    );
  final schedules = FakeFixtureScheduleRepository();
  for (final (fixture, kickoff, home, doubled) in [
    (_played, _now.subtract(const Duration(hours: 1)), 1, false),
    (_later, _now.add(const Duration(days: 1)), 0, false),
    (_soon, _now.add(const Duration(minutes: 30)), 2, true),
  ]) {
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: FixtureRef(fixture),
        homeTeam: 'الهلال $home',
        awayTeam: 'النصر',
        kickoffAt: kickoff,
        leagueName: 'دوري روشن',
      ),
    );
    predictions.seedPrediction(
      FixturePrediction.fromStored(
        id: PredictionId(fixture),
        fixture: FixtureRef(fixture),
        participantId: const ParticipantId(_participant),
        homeGoals: home,
        awayGoals: 1,
        isDouble: doubled,
      ),
      _now.subtract(const Duration(days: 1)),
    );
  }
  final clock = FakeClock(_now);
  return (
    peek: SupportPeekPredictions(
      chats: chats,
      reply: AdminReplySupport(chats: chats, clock: clock),
      predictions: predictions,
      schedules: schedules,
      audit: auditRecorderOver(audit, now: _now),
      clock: clock,
    ),
    chats: chats,
    audit: audit,
  );
}

void main() {
  test('reads the open predictions only, by kickoff, audits and tells the '
      'player', () async {
    final h = _harness();

    final result = await h.peek(
      principal: _admin,
      conversationId: _conversation,
      reason: '  يقول إن توقعه لم يُحفظ  ',
    );

    final peek = (result as Ok<SupportPredictionsPeek>).value;
    expect(
      [for (final p in peek.predictions) p.fixture.value],
      [_soon, _later],
    );
    expect(peek.predictions.first.homeGoals, 2);
    expect(peek.predictions.first.isDouble, isTrue);
    expect(peek.predictions.first.leagueName, 'دوري روشن');

    final row = h.audit.rows.single;
    expect(row.action, AuditAction.supportPredictionsViewed);
    expect(row.targetRef, _player);
    expect(row.reason, 'يقول إن توقعه لم يُحفظ');
    expect(row.actorId, _admin.userId);

    expect(h.chats.replies, [SupportPeekPredictions.noticeText]);
    expect(peek.notice.message.body, SupportPeekPredictions.noticeText);
  });

  test('a player is refused before anything is read', () async {
    final h = _harness();

    final result = await h.peek(
      principal: const AuthenticatedUser(
        userId: UserId(_player),
        role: PlatformRole.user,
      ),
      conversationId: _conversation,
      reason: 'x',
    );

    expect(
      (result as Err<SupportPredictionsPeek>).error.code,
      'auth.insufficient_role',
    );
    expect(h.audit.rows, isEmpty);
    expect(h.chats.replies, isEmpty);
  });

  for (final reason in <String?>[null, '', '   ', 'س' * 201]) {
    test('the reason ${reason == null ? 'null' : '"${reason.length}"'} is '
        'refused, nothing read', () async {
      final h = _harness();

      final result = await h.peek(
        principal: _admin,
        conversationId: _conversation,
        reason: reason,
      );

      final error = (result as Err<SupportPredictionsPeek>).error;
      expect(error.code, 'support.peek_reason_invalid');
      expect(error.kind, ErrorKind.validation);
      expect(h.audit.rows, isEmpty);
      expect(h.chats.replies, isEmpty);
    });
  }

  test('an unknown conversation is refused', () async {
    final h = _harness();

    final result = await h.peek(
      principal: _admin,
      conversationId: 'cccccccc-0000-4000-8000-0000000000ff',
      reason: 'سبب',
    );

    expect(
      (result as Err<SupportPredictionsPeek>).error.code,
      'support.conversation_not_found',
    );
    expect(h.audit.rows, isEmpty);
    expect(h.chats.replies, isEmpty);
  });

  test('before the player writes, nothing is read', () async {
    final h = _harness();
    h.chats.playerWrote = false;

    final result = await h.peek(
      principal: _admin,
      conversationId: _conversation,
      reason: 'سبب',
    );

    expect(
      (result as Err<SupportPredictionsPeek>).error.code,
      'support.peek_needs_player_message',
    );
    expect(h.audit.rows, isEmpty);
    expect(h.chats.replies, isEmpty);
  });

  test('when the player cannot be told, nothing is shown', () async {
    final h = _harness();
    h.chats.replyFails = true;

    final result = await h.peek(
      principal: _admin,
      conversationId: _conversation,
      reason: 'سبب',
    );

    expect((result as Err<SupportPredictionsPeek>).error.code, 'db.down');
  });
}
