import 'package:application/src/football_data/ports/match_details.dart';
import 'package:application/src/publisher/ports/publisher_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Which picture to draw.
enum CardKind {
  /// A goal: the headline, the score, the scorer and the minute.
  goal,

  /// The final result: the score, who won and the scorers.
  finalResult,
}

/// Everything a picture shows.
final class CardSpec {
  /// Creates the spec.
  const CardSpec({
    required this.kind,
    required this.league,
    required this.headline,
    required this.homeName,
    required this.awayName,
    required this.homeBadge,
    required this.awayBadge,
    required this.score,
    this.scoringHome,
    this.scorer,
    this.minuteLabel,
    this.verdict,
    this.homeScorers = const <String>[],
    this.awayScorers = const <String>[],
    this.homeCrest,
    this.awayCrest,
  });

  /// Which picture.
  final CardKind kind;

  /// The competition's name; empty when none.
  final String league;

  /// The big words: «هدف التقدم», «النتيجة النهائية».
  final String headline;

  /// The home club.
  final String homeName;

  /// The away club.
  final String awayName;

  /// The home club's disc.
  final ClubBadge homeBadge;

  /// The away club's disc.
  final ClubBadge awayBadge;

  /// The score shown.
  final ScoreLine score;

  /// On a goal card, whether the home side scored.
  final bool? scoringHome;

  /// On a goal card, the scorer's phrase, when known.
  final String? scorer;

  /// On a goal card, the clock (`"45+2"`), when known.
  final String? minuteLabel;

  /// On a final card: «فوز الهلال», «تعادل».
  final String? verdict;

  /// On a final card, the home goals as `name|minute` pairs, in order.
  final List<String> homeScorers;

  /// On a final card, the away goals, as [homeScorers].
  final List<String> awayScorers;

  /// The PNG of the home club's official crest, drawn in place of its
  /// disc; null when the club has none on file.
  final List<int>? homeCrest;

  /// The PNG of the away club's official crest, as [homeCrest].
  final List<int>? awayCrest;

  /// This spec with the crests [home] and [away] (a side left null keeps
  /// what it had).
  CardSpec withCrests({List<int>? home, List<int>? away}) => CardSpec(
    kind: kind,
    league: league,
    headline: headline,
    homeName: homeName,
    awayName: awayName,
    homeBadge: homeBadge,
    awayBadge: awayBadge,
    score: score,
    scoringHome: scoringHome,
    scorer: scorer,
    minuteLabel: minuteLabel,
    verdict: verdict,
    homeScorers: homeScorers,
    awayScorers: awayScorers,
    homeCrest: home ?? homeCrest,
    awayCrest: away ?? awayCrest,
  );
}

/// Where the clubs' official crests come from (the PNG files bundled with
/// the app, which the server image carries too).
abstract interface class ClubCrestSource {
  /// The PNG bytes of [clubName]'s crest; null when the club has none on
  /// file or the file cannot be read. Never throws.
  Future<List<int>?> crestOf(String clubName);
}

/// Draws a [CardSpec] as a JPEG picture.
abstract interface class PublisherCardRenderer {
  /// The JPEG bytes of [spec]. Never throws.
  Future<Result<List<int>>> render(CardSpec spec);
}

/// Where the pictures are kept: a public bucket, since Instagram fetches a
/// picture by its URL.
abstract interface class PublisherCardHost {
  /// Puts JPEG [bytes] at [path].
  Future<Result<void>> put(String path, List<int> bytes);

  /// The bytes at [path].
  Future<Result<List<int>>> get(String path);

  /// The public URL of [path].
  Uri publicUrl(String path);
}

/// What a platform did with one post.
sealed class PosterOutcome {
  const PosterOutcome();
}

/// Published as [externalId].
final class PosterPublished extends PosterOutcome {
  /// Creates the outcome.
  const PosterPublished(this.externalId);

  /// The platform's id of the post.
  final String externalId;
}

/// Refused before anything was posted, worth trying again after [after]
/// (a rate limit, a server error before the post, a network that never
/// connected).
final class PosterRetry extends PosterOutcome {
  /// Creates the outcome.
  const PosterRetry(this.reason, {this.after = const Duration(minutes: 2)});

  /// Why.
  final String reason;

  /// How long to wait.
  final Duration after;
}

/// Refused for good (a bad token, a picture it will not take).
final class PosterRejected extends PosterOutcome {
  /// Creates the outcome.
  const PosterRejected(this.reason);

  /// Why.
  final String reason;
}

/// Cut after the request went out: the post may be on the platform.
final class PosterUncertain extends PosterOutcome {
  /// Creates the outcome.
  const PosterUncertain(this.reason);

  /// Why.
  final String reason;
}

/// One platform's account, as the server posts to it.
abstract interface class PlatformPoster {
  /// The platform.
  PublishPlatform get platform;

  /// Posts [text] with the picture at [imageUrl] (bytes [image]); without
  /// a picture (a correction), the words alone, where the platform takes
  /// a post with no picture.
  Future<PosterOutcome> post({
    required String text,
    List<int>? image,
    Uri? imageUrl,
  });

  /// The account's name, to show the admin it is linked; an error when the
  /// token is refused.
  Future<Result<String>> verify();

  /// Reach and reactions of the post [externalId]; null when the platform
  /// gives none.
  Future<Result<PostMetrics?>> metrics(String externalId);
}

/// The events of a match in play, from a provider that names the scorers.
abstract interface class LiveGoalDetails {
  /// The events so far of [fixture]; null when the provider has no match
  /// for it or keeps its quota. Never throws.
  Future<Result<List<MatchEvent>?>> eventsOf({
    required String fixtureId,
    required String leagueName,
    required DateTime kickoffAt,
  });
}
