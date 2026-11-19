import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// [state] on the wire, as the owner seat [reader] sees it (script 289):
/// who last changed it is `you`, `other` (the other owner seat) or `sql`
/// (the SQL editor, no seat); none before any change.
// NK289_04
OwnerSwitchDto ownerSwitchWire(OwnerSwitchState state, UserId reader) {
  final UserId? by = state.changedBy;
  return OwnerSwitchDto(
    key: state.which.key,
    isOn: state.isOn,
    reason: state.reason,
    changedBy: by == null
        ? (state.reason == null ? null : OwnerSwitchDto.bySqlEditor)
        : (by == reader ? OwnerSwitchDto.byYou : OwnerSwitchDto.byOtherOwner),
    changedAt: state.changedAt,
  );
}
