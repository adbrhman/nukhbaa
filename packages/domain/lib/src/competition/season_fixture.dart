import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/season_id.dart';
import 'package:shared/shared.dart';

/// The many-to-many link between a [CompetitionSeason] and a fixture,
/// replacing the round-mediated `RoundFixture` link (docs/project-context.md,
/// Axiom 4 Amendment: there is no round to mediate through anymore).
///
/// This link is the *only* place the Competition context names a fixture
/// (Axiom 3: Football Data owns fixtures with no competition awareness). A
/// [displayOrder] fixes the presentation order of fixtures within a season's
/// feed.
///
/// Pure and immutable; value-comparable by its natural key `(seasonId,
/// fixture)` plus order.
final class SeasonFixture {
  const SeasonFixture._({
    required this.seasonId,
    required this.fixture,
    required this.displayOrder,
  });

  /// Rehydrates a link from already-trusted stored fields.
  const SeasonFixture.fromStored({
    required this.seasonId,
    required this.fixture,
    required this.displayOrder,
  });

  /// Creates a new season<->fixture link from validated inputs.
  /// [displayOrder] must be a non-negative ordinal.
  static Result<SeasonFixture> create({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required int displayOrder,
  }) {
    if (displayOrder < 0) {
      return const Result.err(
        AppError.validation(
          'competition.season_fixture_order_invalid',
          'Display order must be a non-negative ordinal',
        ),
      );
    }
    return Result.ok(
      SeasonFixture._(
        seasonId: seasonId,
        fixture: fixture,
        displayOrder: displayOrder,
      ),
    );
  }

  /// The owning season.
  final SeasonId seasonId;

  /// The referenced fixture (owned by Football Data; referenced by id only).
  final FixtureRef fixture;

  /// The 0-based presentation order of this fixture within its season feed.
  final int displayOrder;

  @override
  bool operator ==(Object other) =>
      other is SeasonFixture &&
      other.seasonId == seasonId &&
      other.fixture == fixture &&
      other.displayOrder == displayOrder;

  @override
  int get hashCode => Object.hash(seasonId, fixture, displayOrder);

  @override
  String toString() =>
      'SeasonFixture(season: ${seasonId.value}, fixture: ${fixture.value}, '
      'order: $displayOrder)';
}
