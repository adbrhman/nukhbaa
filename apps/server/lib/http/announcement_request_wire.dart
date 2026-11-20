import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

// NK290_06
/// [request] on the wire (script 290).
AnnouncementRequestDto announcementRequestWire(AnnouncementRequest request) =>
    AnnouncementRequestDto(
      id: request.id.value,
      authorName: request.authorName,
      title: request.title,
      body: request.body,
      status: request.status.wire,
      createdAt: request.createdAt,
      decidedAt: request.decidedAt,
      recipients: request.recipients,
    );

/// [requests] on the wire, in their order.
AnnouncementRequestsDto announcementRequestsWire(
  List<AnnouncementRequest> requests,
) => AnnouncementRequestsDto(
  requests: <AnnouncementRequestDto>[
    for (final AnnouncementRequest request in requests)
      announcementRequestWire(request),
  ],
);
