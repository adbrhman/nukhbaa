/// One map of the audit actions in words (audit L-14), with every token the
/// domain's `AuditAction.wireValue` has (migrations 0010, 0015, 0023, 0098).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/audit_action_labels.dart';

/// `AuditAction.values.map((a) => a.wireValue)` in the domain, which this
/// package may not import: keep the two lists in step.
const List<String> _domainTokens = <String>[
  'user_suspended',
  'user_reinstated',
  'participant_ledger_viewed',
  'fixture_result_recorded',
  'round_scored',
  'round_posted_to_ledger',
  'competition_created',
  'season_started',
  'round_opened',
  'round_locked',
  'fixture_linked_to_round',
  'round_predictions_viewed',
  'fixture_predictions_viewed',
  'user_predictions_viewed',
  'fixture_schedule_corrected',
  'user_renamed',
  'error_updated',
  'fixture_hidden',
  'fixture_shown',
  'team_added',
  'league_added',
  'fixtures_merged',
];

void main() {
  test('every action the domain has reads in words', () {
    for (final String token in _domainTokens) {
      expect(auditActionLabels[token], isNotNull, reason: token);
      expect(auditActionLabel(token), isNot('إجراء إداري'), reason: token);
    }
    expect(auditActionLabels.keys.toSet(), _domainTokens.toSet());
  });

  test('one word for one action, on the home and in the log', () {
    expect(auditActionLabel('user_suspended'), 'تعليق لاعب');
    expect(auditLogActionLabel('user_suspended'), 'تعليق لاعب');
  });

  test('an action this build predates: plain on the home, kept in the log', () {
    expect(auditActionLabel('seat_moved'), 'إجراء إداري');
    expect(auditLogActionLabel('seat_moved'), 'إجراء إداري (seat_moved)');
  });
}
