import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/draw_h2h_month.dart';
import 'package:application/src/gamification/ports/h2h_draw_source.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: an admin starts the hidden pilot month (migration 0100).
///
/// The pilot is the month open now, drawn from the users in the pilot (flag
/// `h2h_pilot`, variant `pilot`), and marked `is_pilot`: only its members see
/// it, and its results never decide a division -- the first public month is
/// seeded as if it had not happened. Allowed only before the league opens
/// (`H2hLeaguePolicy.firstMonth`), and only once per month.
///
/// Never throws; returns a typed [Result] with the number of seats drawn.
final class StartH2hPilot {
  /// Creates the use-case over its collaborators.
  const StartH2hPilot({
    required H2hLeagueStore leagues,
    required H2hDrawSource source,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _leagues = leagues,
       _source = source,
       _ids = idGenerator,
       _clock = clock;

  final H2hLeagueStore _leagues;
  final H2hDrawSource _source;
  final IdGenerator _ids;
  final Clock _clock;

  /// Draws the pilot month for [principal], an admin.
  Future<Result<int>> call({required AuthenticatedUser principal}) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final month = H2hLeaguePolicy.monthStartOf(riyadhDayOf(_clock.nowUtc()));
    if (!month.isBefore(H2hLeaguePolicy.firstMonth)) {
      return const Result.err(
        AppError.invariant(
          'h2h.pilot_after_launch',
          'The pilot runs only before the league opens to everyone',
        ),
      );
    }

    final drawnResult = await _leagues.monthOf(month);
    if (drawnResult is Err<H2hMonthInfo?>) {
      return Result.err(drawnResult.error);
    }
    if ((drawnResult as Ok<H2hMonthInfo?>).value != null) {
      return const Result.err(
        AppError.invariant(
          'h2h.pilot_already_drawn',
          'This month was already drawn',
        ),
      );
    }

    final orderResult = await _source.pilotOrder(
      H2hLeaguePolicy.previousMonthOf(month),
    );
    if (orderResult is Err<List<UserId>>) {
      return Result.err(orderResult.error);
    }
    final order = (orderResult as Ok<List<UserId>>).value;
    if (order.length < 2) {
      return const Result.err(
        AppError.validation(
          'h2h.pilot_too_small',
          'Assign at least two users to the h2h_pilot flag first',
        ),
      );
    }

    return DrawH2hMonth.drawInto(
      leagues: _leagues,
      ids: _ids,
      monthStart: month,
      isPilot: true,
      order: order,
    );
  }
}
