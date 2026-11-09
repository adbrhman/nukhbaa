/// Maps the champions of the Elite Cup (migrations 0190 and 0204) to their
/// wire shapes. The picture URLs are built here, at the HTTP edge, the one
/// layer that owns the route shapes.
library;

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:server/http/avatar_url.dart';

/// The server-relative URL of the picture of a champion of the cup. The `v`
/// parameter is the picture's time in epoch milliseconds: a replaced picture
/// is a new URL, so no device keeps the old one from its cache.
String cupChampionPhotoUrlOf({
  required String monthStart,
  required int place,
  required DateTime updatedAt,
}) =>
    '/cup-champions/$monthStart/$place/photo'
    '?v=${updatedAt.toUtc().millisecondsSinceEpoch}';

/// One champion of the cup on the wire.
CupChampionDto cupChampionToDto(CupChampion champion) {
  final DateTime? photoAt = champion.photoUpdatedAt;
  final DateTime? avatarAt = champion.avatarUpdatedAt;
  return CupChampionDto(
    monthStart: champion.monthStart,
    place: champion.place,
    how: champion.how,
    userId: champion.userId.value,
    displayName: champion.displayName,
    photoUrl: photoAt == null
        ? null
        : cupChampionPhotoUrlOf(
            monthStart: champion.monthStart,
            place: champion.place,
            updatedAt: photoAt,
          ),
    avatarUrl: avatarAt == null
        ? null
        : avatarUrlOf(userId: champion.userId, updatedAt: avatarAt),
  );
}

/// The champions of the cup on the wire.
CupChampionsDto cupChampionsToDto(List<CupChampion> champions) =>
    CupChampionsDto(
      champions: [
        for (final CupChampion champion in champions)
          cupChampionToDto(champion),
      ],
    );
