import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

const _copy = 'fde6264d-0000-4000-8000-000000000001';
const _kept = 'a2e41db8-0000-4000-8000-000000000001';

/// The copies of a match and the merge, from the admin panel (script 95).
void main() {
  test('GET /admin/fixtures/{id}/copies reads the rows', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'copies': [
          {
            'fixture_id': _copy,
            'home_team': 'سالزبورغ',
            'away_team': 'ميلان',
            'kickoff_at': '2026-10-15T19:00:00.000Z',
            'hidden': true,
            'predictions': 3,
            'doubles': 0,
            'has_result': false,
            'linked': false,
            'is_self': true,
          },
          {
            'fixture_id': _kept,
            'home_team': 'سالزبورغ',
            'away_team': 'ميلان',
            'kickoff_at': '2026-10-15T19:00:00.000Z',
            'hidden': false,
            'predictions': 41,
            'doubles': 6,
            'has_result': true,
            'linked': true,
            'is_self': false,
          },
        ],
      }),
    );

    final result = await AdminApi(ctx.transport).fixtureCopies(_copy);

    final List<FixtureCopyDto> copies =
        (result as Ok<FixtureCopiesDto>).value.copies;
    expect(copies, hasLength(2));
    expect(copies.first.isSelf, isTrue);
    expect(copies.last.predictions, 41);
    expect(copies.last.hidden, isFalse);
    final req = ctx.captured.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/admin/fixtures/$_copy/copies');
  });

  test('POST /admin/fixtures/{id}/merge sends the copy kept and apply, and '
      'reads the report', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'moved': 3,
        'doubles_moved': 0,
        'doubles_dropped': 0,
        'both_predicted': 1,
        'late': 0,
        'not_participant': 0,
        'link_moved': false,
        'kept_has_result': true,
        'applied': true,
        'rescored': true,
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).mergeFixture(duplicateId: _copy, keptId: _kept, apply: true);

    final FixtureMergeReportDto report =
        (result as Ok<FixtureMergeReportDto>).value;
    expect(report.moved, 3);
    expect(report.rescored, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/admin/fixtures/$_copy/merge');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    expect(body['into'], _kept);
    expect(body['apply'], isTrue);
  });

  test('a refusal comes back as its code and message', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(
        409,
        'competition.fixture_merge_refused',
        'دُمجت هذه النسخة من قبل.',
      ),
    );

    final result = await AdminApi(
      ctx.transport,
    ).mergeFixture(duplicateId: _copy, keptId: _kept, apply: false);

    final AppError error = (result as Err<FixtureMergeReportDto>).error;
    expect(error.code, 'competition.fixture_merge_refused');
    expect(error.message, 'دُمجت هذه النسخة من قبل.');
  });
}
