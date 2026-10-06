import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/round_id.dart';
import 'package:domain/src/group/group_id.dart';
import 'package:domain/src/identity/user_id.dart';
import 'package:domain/src/notification/announcement_id.dart';
import 'package:domain/src/notification/notification_kind.dart';
import 'package:domain/src/social/duel_challenge_id.dart';

/// The bounded, **kind-discriminated reference payload** of a [Notification]
/// (Notifications decision #1/#3): the type-specific ids a client needs to
/// render the notification and deep-link into the platform, plus a
/// deterministic [dedupeRef] that keys the idempotency constraint.
///
/// Discriminated by [NotificationKind]:
/// * `roundScored` — [roundId] set; group/actor null.
/// * `groupMemberJoined` — [groupId] + [actorUserId] (the joiner) set; round
///   null.
/// * `reactionReceived` — [groupId] + [roundId] + [actorUserId] (the reactor)
///   set.
///
/// The named factories validate that exactly the right references are present
/// for the kind (an aggregate reasons about its own shape). [dedupeRef] is a
/// stable string derived purely from the subject, so re-triggering the SAME
/// event produces the SAME ref (a replay dedupes on `(recipientId, kind,
/// dedupeRef)`) while a DISTINCT event produces a distinct ref.
///
/// Carries **NO points field** (Axiom 5 — Notifications is never a second
/// points source) and **NO free-text / open-graph edge** (decision #1;
/// ADR-001). Pure, immutable, value-comparable.
final class NotificationSubject {
  const NotificationSubject._({
    required this.kind,
    this.roundId,
    this.groupId,
    this.actorUserId,
    this.fixture,
    this.announcementId,
    this.duelChallengeId,
  });

  /// Rehydrates a subject from already-trusted stored fields (used by the
  /// infrastructure mapper). Performs no cross-field validation beyond typing —
  /// callers building a *new* subject from a domain event must use the named
  /// factories.
  const NotificationSubject.fromStored({
    required this.kind,
    this.roundId,
    this.groupId,
    this.actorUserId,
    this.fixture,
    this.announcementId,
    this.duelChallengeId,
  });

  /// The subject of a `roundScored` notification — the scored [roundId].
  static NotificationSubject roundScored({required RoundId roundId}) =>
      NotificationSubject._(
        kind: NotificationKind.roundScored,
        roundId: roundId,
      );

  /// The subject of a `groupMemberJoined` notification — the [groupId] and the
  /// joining [actorUserId].
  static NotificationSubject groupMemberJoined({
    required GroupId groupId,
    required UserId actorUserId,
  }) => NotificationSubject._(
    kind: NotificationKind.groupMemberJoined,
    groupId: groupId,
    actorUserId: actorUserId,
  );

  /// The subject of a `reactionReceived` notification — the [groupId], the
  /// target [roundId], and the reacting [actorUserId].
  static NotificationSubject reactionReceived({
    required GroupId groupId,
    required RoundId roundId,
    required UserId actorUserId,
  }) => NotificationSubject._(
    kind: NotificationKind.reactionReceived,
    groupId: groupId,
    roundId: roundId,
    actorUserId: actorUserId,
  );

  /// The subject of a `fixtureScored` notification — the scored [fixture]
  /// (docs/project-context.md, Axiom 4 Amendment; the per-fixture sibling of
  /// [roundScored]).
  static NotificationSubject fixtureScored({required FixtureRef fixture}) =>
      NotificationSubject._(
        kind: NotificationKind.fixtureScored,
        fixture: fixture,
      );

  /// The subject of an `adminAnnouncement` notification -- the
  /// [announcementId] whose row carries the admin's text (migration 0043).
  static NotificationSubject adminAnnouncement({
    required AnnouncementId announcementId,
  }) => NotificationSubject._(
    kind: NotificationKind.adminAnnouncement,
    announcementId: announcementId,
  );

  /// The subject of a `duelChallenged` notification -- the private
  /// challenge and its challenger (migration 0092). One per challenge.
  static NotificationSubject duelChallenged({
    required DuelChallengeId challengeId,
    required UserId actorUserId,
  }) => NotificationSubject._(
    kind: NotificationKind.duelChallenged,
    duelChallengeId: challengeId,
    actorUserId: actorUserId,
  );

  /// The subject of a `duelAccepted` notification -- the challenge and the
  /// player who accepted it (migration 0092). One per acceptance.
  static NotificationSubject duelAccepted({
    required DuelChallengeId challengeId,
    required UserId actorUserId,
  }) => NotificationSubject._(
    kind: NotificationKind.duelAccepted,
    duelChallengeId: challengeId,
    actorUserId: actorUserId,
  );

  /// The subject of a `predictionReaction` notification -- the fixture and
  /// the player who reacted to the recipient's prediction for it (migration
  /// 0094). One per reacting player per fixture: a changed reaction, or one
  /// taken back and given again, is the same event.
  static NotificationSubject predictionReaction({
    required FixtureRef fixture,
    required UserId actorUserId,
  }) => NotificationSubject._(
    kind: NotificationKind.predictionReaction,
    fixture: fixture,
    actorUserId: actorUserId,
  );

  /// The kind this subject belongs to (matches the owning notification's kind).
  final NotificationKind kind;

  /// The round involved (`roundScored`, `reactionReceived`); else null.
  final RoundId? roundId;

  /// The group involved (`groupMemberJoined`, `reactionReceived`); else null.
  final GroupId? groupId;

  /// The acting user (`groupMemberJoined` = the joiner, `reactionReceived` =
  /// the reactor); else null.
  final UserId? actorUserId;

  /// The fixture involved (`fixtureScored`); else null (Axiom 4 Amendment).
  final FixtureRef? fixture;

  /// The announcement involved (`adminAnnouncement`); else null.
  final AnnouncementId? announcementId;

  /// The duel challenge involved (`duelChallenged`, `duelAccepted`); else
  /// null (migration 0092).
  final DuelChallengeId? duelChallengeId;

  /// A deterministic string that identifies the originating event, keying the
  /// `(recipientId, kind, subjectRef)` idempotency constraint so a replayed
  /// trigger dedupes and a distinct event does not. Built purely from the
  /// subject references — no clock, no random component — so it is stable
  /// across replays.
  String get dedupeRef => switch (kind) {
    NotificationKind.roundScored => 'round:${roundId!.value}',
    NotificationKind.groupMemberJoined =>
      'group_join:${groupId!.value}:${actorUserId!.value}',
    NotificationKind.fixtureScored => 'fixture:${fixture!.value}',
    NotificationKind.adminAnnouncement =>
      'announcement:${announcementId!.value}',
    NotificationKind.reactionReceived =>
      'reaction:${groupId!.value}:${roundId!.value}:${actorUserId!.value}',
    NotificationKind.duelChallenged =>
      'duel_challenged:${duelChallengeId!.value}',
    NotificationKind.duelAccepted =>
      'duel_accepted:${duelChallengeId!.value}:${actorUserId!.value}',
    NotificationKind.predictionReaction =>
      'prediction_reaction:${fixture!.value}:${actorUserId!.value}',
  };

  @override
  bool operator ==(Object other) =>
      other is NotificationSubject &&
      other.kind == kind &&
      other.roundId == roundId &&
      other.groupId == groupId &&
      other.actorUserId == actorUserId &&
      other.fixture == fixture &&
      other.announcementId == announcementId &&
      other.duelChallengeId == duelChallengeId;

  @override
  int get hashCode => Object.hash(
    kind,
    roundId,
    groupId,
    actorUserId,
    fixture,
    announcementId,
    duelChallengeId,
  );

  @override
  String toString() => 'NotificationSubject(${kind.wireValue}, $dedupeRef)';
}
