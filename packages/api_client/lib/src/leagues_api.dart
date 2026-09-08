import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Read client for the Football Data league catalog.
///
/// The sibling of `TeamsApi`, and deliberately shaped identically: a fixture
/// names its league by id, and this is how a client turns that id into a name
/// without hardcoding one.
final class LeaguesApi {
  /// Creates the leagues client over the shared [ApiTransport].
  const LeaguesApi(this._transport);

  final ApiTransport _transport;

  /// `GET /leagues` -- the full league catalog.
  ///
  /// An empty catalog is a legitimate `Ok(<empty list>)`, never an error.
  Future<Result<List<LeagueDto>>> listLeagues() {
    return _transport.getList<LeagueDto>(
      '/leagues',
      parseElement: LeagueDto.fromJson,
    );
  }
}
