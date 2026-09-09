import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: every monthly contest season, newest first.
///
/// The contest is the calendar month, but until now no read could say
/// which months exist: [ListCompetitionSeasons] answers one competition at
/// a time, and the caller would have to know which of the nine
/// competitions is the monthly one. This flattens that away -- the months
/// themselves, whichever competition happens to own them.
///
/// Visible to any authenticated user (`PlatformRole.user`), matching every
/// other browse read. The admin form is the first caller, but a month list
/// is not privileged information: it is the shape of the contest itself.
///
/// Never throws; returns a typed [Result].
final class ListMonthlySeasons {
  /// Creates the use-case over its repository port.
  const ListMonthlySeasons({required CompetitionRepository repository})
    : _repository = repository;

  final CompetitionRepository _repository;

  /// Returns the monthly seasons visible to [principal].
  Future<Result<List<CompetitionSeason>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _repository.listMonthlySeasons();
  }
}
