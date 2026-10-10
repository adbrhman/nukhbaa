import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

/// The groups `AddH2hGroups` opened, on the wire
/// (`POST /admin/h2h/extra-groups`).
Map<String, Object?> h2hGroupsAddedToJson(H2hGroupsAdded added) =>
    H2hGroupsAddedDto(
      monthStart: _isoDay(added.monthStart),
      groups: [
        for (final g in added.groups)
          H2hAddedGroupDto(
            leagueId: g.leagueId.value,
            division: g.group.division.level,
            groupIndex: g.group.groupIndex,
            seats: g.group.seats.length,
          ),
      ],
      seats: added.seats,
      waiting: added.waiting,
    ).toJson();

String _isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
