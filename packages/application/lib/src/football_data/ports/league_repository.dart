import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port over the Football Data league catalog
/// (`football_data.leagues`), the sibling of `TeamRepository`.
///
/// Read-only, like its sibling: leagues are reference data, seeded rather
/// than authored through the app, so no write surface is offered that nothing
/// would call.
///
/// Contract (Application ADR Section 2):
/// * MUST NOT throw -- every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * An empty catalog is a legitimate `Ok(<empty list>)`, never an error.
abstract interface class LeagueRepository {
  /// Lists every known league.
  Future<Result<List<League>>> listAll();
}
