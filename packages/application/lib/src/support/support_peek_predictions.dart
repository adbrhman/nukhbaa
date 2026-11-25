import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One prediction of a match not yet started, as support reads it.
final class SupportPeekedPrediction {
  /// Creates the line.
  const SupportPeekedPrediction({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
    this.leagueName,
  });

  /// The match.
  final FixtureRef fixture;

  /// Its home side.
  final String homeTeam;

  /// Its away side.
  final String awayTeam;

  /// Its kickoff, UTC.
  final DateTime kickoffAt;

  /// The predicted home goals.
  final int homeGoals;

  /// The predicted away goals.
  final int awayGoals;

  /// Whether the player made it his day's double.
  final bool isDouble;

  /// Its league's name, when it has one.
  final String? leagueName;
}

/// What the owner read: the predictions, and nothing else.
final class SupportPredictionsPeek {
  /// Creates the reading.
  const SupportPredictionsPeek({required this.predictions});

  /// The player's predictions of the matches not yet started, by kickoff.
  final List<SupportPeekedPrediction> predictions;
}

/// The one reading of a prediction before its kickoff, by anyone
/// (decided by the owner on 2026-11-11, script 261): the admins play like
/// any player, so neither the match's predictions nor a player's history
/// show a match that has not started. From a player's own support
/// conversation the owner may read that player's predictions of the matches
/// not yet started, to answer him (a prediction he says was not saved, a
/// double he says moved).
///
/// The reading is silent (decided 2026-11-25, scripts 325-327): it tells
/// nobody and keeps no trace. No message goes into the player's
/// conversation, no push rings his phone, no audit row is written, and the
/// player need not have written to support first. A reason is still
/// required ([reasonMaxLength] characters at most); it is checked and not
/// stored.
///
/// Owner only (either seat, [OwnerNotices.isOwner]; decided 2026-11-25,
/// script 325): any other admin is refused `auth.insufficient_role` before
/// anything is read. Never throws; returns a typed [Result].
final class SupportPeekPredictions {
  /// Creates the use-case over its collaborators.
  const SupportPeekPredictions({
    required SupportChatRepository chats,
    required OwnerNotices owners,
    required FixturePredictionRepository predictions,
    required FixtureScheduleRepository schedules,
    required Clock clock,
  }) : _chats = chats,
       _owners = owners,
       _predictions = predictions,
       _schedules = schedules,
       _clock = clock;

  final SupportChatRepository _chats;
  final OwnerNotices _owners;
  final FixturePredictionRepository _predictions;
  final FixtureScheduleRepository _schedules;
  final Clock _clock;

  /// The longest reason kept.
  static const int reasonMaxLength = 200;

  /// A blank or too long reason.
  static const AppError reasonInvalid = AppError.validation(
    'support.peek_reason_invalid',
    'اكتب سبب الاطلاع (200 حرف على الأكثر).',
  );

  /// Not an owner seat: refused as any non-admin is.
  static const AppError ownerOnly = AppError.authorization(
    'auth.insufficient_role',
    'Requires the owner',
  );

  /// Reads the open predictions of [conversationId]'s player for
  /// [principal], who must be an owner, for [reason]; writes nothing.
  Future<Result<SupportPredictionsPeek>> call({
    required AuthenticatedUser principal,
    required String conversationId,
    required String? reason,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    // NK325_01
    final seat = await _owners.isOwner(principal.userId);
    if (seat is Err<bool>) return Result.err(seat.error);
    if (!(seat as Ok<bool>).value) return const Result.err(ownerOnly);
    final id = SupportConversationId.tryParse(conversationId);
    if (id is Err<SupportConversationId>) return Result.err(id.error);
    final why = (reason ?? '').trim();
    if (why.isEmpty || why.length > reasonMaxLength) {
      return const Result.err(reasonInvalid);
    }

    final conversation = (id as Ok<SupportConversationId>).value;
    final summary = await _chats.conversation(conversation);
    if (summary is Err<SupportConversationSummary>) {
      return Result.err(summary.error);
    }
    final player = (summary as Ok<SupportConversationSummary>).value.playerId;

    // NK327_01
    final open = await _openPredictions(player);
    if (open is Err<List<SupportPeekedPrediction>>) {
      return Result.err(open.error);
    }
    return Result.ok(
      SupportPredictionsPeek(
        predictions: (open as Ok<List<SupportPeekedPrediction>>).value,
      ),
    );
  }

  Future<Result<List<SupportPeekedPrediction>>> _openPredictions(
    UserId player,
  ) async {
    final listed = await _predictions.listByUser(player);
    if (listed is Err<List<FixturePredictionView>>) {
      return Result.err(listed.error);
    }
    final views = (listed as Ok<List<FixturePredictionView>>).value;
    if (views.isEmpty) return const Result.ok(<SupportPeekedPrediction>[]);
    final found = await _schedules.findByFixtures(
      <FixtureRef>{
        for (final view in views) view.prediction.fixture,
      }.toList(growable: false),
    );
    if (found is Err<List<FixtureSchedule>>) return Result.err(found.error);
    final byFixture = <String, FixtureSchedule>{
      for (final schedule in (found as Ok<List<FixtureSchedule>>).value)
        schedule.fixture.value: schedule,
    };
    final now = _clock.nowUtc();
    final lines =
        <SupportPeekedPrediction>[
          for (final view in views)
            if (byFixture[view.prediction.fixture.value] case final schedule?)
              if (now.isBefore(schedule.kickoffAt.toUtc()))
                SupportPeekedPrediction(
                  fixture: view.prediction.fixture,
                  homeTeam: schedule.homeTeam,
                  awayTeam: schedule.awayTeam,
                  kickoffAt: schedule.kickoffAt.toUtc(),
                  homeGoals: view.prediction.homeGoals,
                  awayGoals: view.prediction.awayGoals,
                  isDouble: view.prediction.isDouble,
                  leagueName: schedule.leagueName,
                ),
        ]..sort((a, b) {
          final byKickoff = a.kickoffAt.compareTo(b.kickoffAt);
          return byKickoff != 0
              ? byKickoff
              : a.fixture.value.compareTo(b.fixture.value);
        });
    return Result.ok(lines);
  }
}
