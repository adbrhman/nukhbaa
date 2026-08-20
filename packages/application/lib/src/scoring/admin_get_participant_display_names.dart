import 'package:application/src/identity/authorization.dart';
import 'package:application/src/ledger/ports/participant_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class AdminGetParticipantDisplayNames {
  const AdminGetParticipantDisplayNames({
    required ParticipantReader participantReader,
  }) : _participants = participantReader;

  final ParticipantReader _participants;

  Future<Result<Map<String, String>>> call({
    required AuthenticatedUser principal,
    required List<String> participantIds,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final ids = <ParticipantId>[];
    for (final raw in participantIds) {
      final idResult = ParticipantId.tryParse(raw);
      if (idResult is Err<ParticipantId>) return Result.err(idResult.error);
      ids.add((idResult as Ok<ParticipantId>).value);
    }
    return _participants.findDisplayNames(ids);
  }
}
