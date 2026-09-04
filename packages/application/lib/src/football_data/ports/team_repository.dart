import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port over the Football Data team catalog (`football_data.teams`).
abstract interface class TeamRepository {
  /// Lists every known team, name-ordered.
  Future<Result<List<Team>>> listAll();
}
