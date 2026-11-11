import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/support/conversations/[id]/predictions/index.dart'
    as peek_route;
import 'competition_route_harness.dart';

const _conversation = 'cccccccc-0000-4000-8000-000000000001';
const _participant = '44444444-4444-4444-8444-444444444444';
const _soon = 'aaaaaaaa-0000-4000-8000-000000000002';
const _played = 'aaaaaaaa-0000-4000-8000-000000000001';

final DateTime _now = DateTime.utc(2026, 11, 12, 15);

/// [kTargetUserId]'s conversation, and the answers stored in it.
final class _Chats implements SupportChatRepository {
  final List<String> replies = <String>[];

  @override
  Future<Result<SupportThread>> conversationThread({
    required SupportConversationId conversationId,
    required int? beforeId,
    required int limit,
  }) async => Result.ok(
    SupportThread(
      status: SupportConversationStatus.open,
      unread: 1,
      hasMore: false,
      messages: <SupportMessage>[
        SupportMessage(
          id: 1,
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
        playerId: const UserId(kTargetUserId),
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
    replies.add(body.value);
    return Result.ok(
      SupportMessageStored(
        conversationId: conversationId,
        playerName: 'خالد',
        message: SupportMessage(
          id: 9,
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

/// [kTargetUserId]'s predictions: one played, one not yet started.
final class _Predictions implements FixturePredictionRepository {
  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async {
    if (userId.value != kTargetUserId) {
      return const Result.ok(<FixturePredictionView>[]);
    }
    return Result.ok(<FixturePredictionView>[
      for (final (fixture, home) in [(_played, 1), (_soon, 3)])
        FixturePredictionView(
          prediction: FixturePrediction.fromStored(
            id: PredictionId(fixture),
            fixture: FixtureRef(fixture),
            participantId: const ParticipantId(_participant),
            homeGoals: home,
            awayGoals: 0,
            isDouble: fixture == _soon,
          ),
          submittedAt: _now.subtract(const Duration(days: 1)),
        ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Script 261: support reads one player's predictions of the matches not
/// yet started, from his conversation, through the real wiring.
void main() {
  late _Chats chats;
  late InMemoryAuditLogRepository audit;

  CompositionRoot root({bool wired = true}) {
    chats = _Chats();
    audit = InMemoryAuditLogRepository();
    final clock = FixedClock(_now);
    final schedules = InMemoryFixtureScheduleRepository()
      ..seed(
        FixtureSchedule.fromStored(
          fixture: const FixtureRef(_played),
          homeTeam: 'روما',
          awayTeam: 'لاتسيو',
          kickoffAt: _now.subtract(const Duration(hours: 2)),
        ),
      )
      ..seed(
        FixtureSchedule.fromStored(
          fixture: const FixtureRef(_soon),
          homeTeam: 'الهلال',
          awayTeam: 'النصر',
          kickoffAt: _now.add(const Duration(hours: 3)),
          leagueName: 'دوري روشن',
        ),
      );
    return CompositionRoot.forTesting(
      supportPeekPredictions: wired
          ? SupportPeekPredictions(
              chats: chats,
              reply: AdminReplySupport(chats: chats, clock: clock),
              predictions: _Predictions(),
              schedules: schedules,
              audit: AuditRecorder(
                auditLog: audit,
                idGenerator: ScriptedIdGenerator([kAuditEntryId]),
                clock: clock,
              ),
              clock: clock,
            )
          : null,
    );
  }

  Future<Response> send(
    CompositionRoot root,
    AuthenticatedUser principal, {
    Object? body = const {'reason': 'يقول إن توقعه لم يُحفظ'},
    HttpMethod method = HttpMethod.post,
    String id = _conversation,
  }) => peek_route.onRequest(
    wireContext(root: root, principal: principal, body: body, method: method),
    id,
  );

  test(
    'an admin reads the open predictions; audited, the player told',
    () async {
      final r = root();

      final response = await send(r, adminPrincipal());

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final lines = (body['predictions']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(lines.single['fixture_id'], _soon);
      expect(lines.single['home_goals'], 3);
      expect(lines.single['is_double'], isTrue);
      expect(lines.single['league_name'], 'دوري روشن');
      final notice = body['notice']! as Map<String, Object?>;
      expect(notice['body'], SupportPeekPredictions.noticeText);
      expect(notice['sender'], 'support');
      expect(chats.replies, [SupportPeekPredictions.noticeText]);
      final entry = audit.entries.single;
      expect(entry.action, AuditAction.supportPredictionsViewed);
      expect(entry.targetRef, kTargetUserId);
      expect(entry.reason, 'يقول إن توقعه لم يُحفظ');
    },
  );

  test('without a reason it is a 400 and nothing is read', () async {
    final r = root();

    final response = await send(r, adminPrincipal(), body: const {});

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await decodeBody(response))['code'], 'support.peek_reason_invalid');
    expect(audit.entries, isEmpty);
    expect(chats.replies, isEmpty);
  });

  test('a player is refused', () async {
    final r = root();

    final response = await send(r, userPrincipal());

    expect((await decodeBody(response))['code'], 'auth.insufficient_role');
    expect(audit.entries, isEmpty);
    expect(chats.replies, isEmpty);
  });

  test('an unknown conversation is a 409', () async {
    final r = root();

    final response = await send(
      r,
      adminPrincipal(),
      id: 'cccccccc-0000-4000-8000-0000000000ff',
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect(
      (await decodeBody(response))['code'],
      'support.conversation_not_found',
    );
  });

  test('a server without it answers 503', () async {
    final response = await send(root(wired: false), adminPrincipal());

    expect(response.statusCode, HttpStatus.serviceUnavailable);
    expect((await decodeBody(response))['code'], 'support.peek_unavailable');
  });

  test('405 on any other method', () async {
    final response = await send(
      root(),
      adminPrincipal(),
      method: HttpMethod.get,
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
