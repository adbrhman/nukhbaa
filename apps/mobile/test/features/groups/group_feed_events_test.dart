/// Audit L-03: the group feed no longer repeats the round model's scored
/// rounds; the members who joined stay.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/groups/group_feed_screen.dart';

void main() {
  test('round_scored is left out, member_joined stays', () {
    const GroupActivityFeedDto feed = GroupActivityFeedDto(
      groupId: 'g-1',
      events: <ActivityEventDto>[
        ActivityEventDto(
          type: 'member_joined',
          groupId: 'g-1',
          occurredAt: '2026-10-02T09:00:00.000Z',
        ),
        ActivityEventDto(
          type: 'round_scored',
          groupId: 'g-1',
          occurredAt: '2026-08-01T09:00:00.000Z',
        ),
      ],
    );

    expect(visibleFeedEvents(feed).map((e) => e.type), <String>[
      'member_joined',
    ]);
  });
}
