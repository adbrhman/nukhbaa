import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

const String _fixture = 'cccccccc-0000-4000-8000-000000000001';
const String _team = 'dddddddd-0000-4000-8000-000000000001';
const String _post = 'eeeeeeee-0000-4000-8000-000000000001';

Map<String, Object?> _body(CapturedRequest request) =>
    jsonDecode(request.body) as Map<String, Object?>;

/// The sports publisher's admin routes (script 208, migration 0200), as the
/// panel of script 209 calls them.
void main() {
  test('GET /admin/publisher reads the whole panel', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'mode': 'dry_run',
        'settings': [
          {
            'platform': 'instagram',
            'enabled': false,
            'goals': 'all',
            'final_result': true,
            'hold_seconds': 480,
            'min_gap_seconds': 0,
            'daily_cap': 8,
          },
        ],
        'candidates': [
          {
            'fixture_id': _fixture,
            'home_name': 'الهلال',
            'away_name': 'النصر',
            'league_name': 'دوري روشن',
            'kickoff_at': '2026-11-05T17:00:00.000Z',
            'covered': true,
          },
        ],
        'posts': [
          {
            'id': _post,
            'fixture_id': _fixture,
            'match_label': 'الهلال - النصر',
            'kind': 'goal',
            'platform': 'x',
            'state': 'ready_to_share',
            'body': 'هدف!',
            'has_card': true,
            'created_at': '2026-11-05T17:20:00.000Z',
            'attempts': 0,
          },
        ],
        'badges': [
          {
            'team_id': _team,
            'team_name': 'الهلال',
            'fill': '#1978D1',
            'label': 'هلال',
          },
        ],
        'linked': ['facebook'],
      }),
      token: 'jwt-admin',
    );

    final result = await AdminApi(ctx.transport).publisherOverview();

    final PublisherOverviewDto overview =
        (result as Ok<PublisherOverviewDto>).value;
    expect(ctx.captured.single.method, 'GET');
    expect(ctx.captured.single.url.path, '/admin/publisher');
    expect(ctx.captured.single.headers['authorization'], 'Bearer jwt-admin');
    expect(overview.mode, 'dry_run');
    expect(overview.settings.single.holdSeconds, 480);
    expect(overview.candidates.single.covered, isTrue);
    expect(overview.posts.single.state, 'ready_to_share');
    expect(overview.badges.single.fill, '#1978D1');
    expect(overview.linked, <String>['facebook']);
  });

  test('a setting, a match and a badge go up by PUT', () async {
    final ctx = buildTransport((request) async {
      final String path = request.url.path;
      final Map<String, Object?> sent =
          jsonDecode(request.body) as Map<String, Object?>;
      if (path == '/admin/publisher/matches') {
        return okJson({'fixture_id': sent['fixture_id'], 'covered': false});
      }
      if (path == '/admin/publisher/badges') {
        return okJson({
          'team_id': sent['team_id'],
          'team_name': '',
          'fill': sent['fill'],
          'label': sent['label'],
        });
      }
      return okJson(sent);
    });
    final AdminApi api = AdminApi(ctx.transport);

    final setting = await api.savePublisherSetting(
      const PublisherSettingDto(
        platform: 'facebook',
        enabled: true,
        goals: 'key',
        finalResult: false,
        holdSeconds: 240,
        minGapSeconds: 600,
        dailyCap: 10,
      ),
    );
    final covered = await api.setPublisherCoverage(
      fixtureId: _fixture,
      covered: false,
    );
    final badge = await api.setPublisherBadge(
      teamId: _team,
      fill: '#FFDD00',
      label: 'النصر',
    );

    expect((setting as Ok<PublisherSettingDto>).value.goals, 'key');
    expect(covered, const Result<bool>.ok(false));
    expect((badge as Ok<PublisherBadgeDto>).value.fill, '#FFDD00');
    for (final CapturedRequest request in ctx.captured) {
      expect(request.method, 'PUT');
    }
    expect(ctx.captured[0].url.path, '/admin/publisher');
    expect(_body(ctx.captured[0]), <String, Object?>{
      'platform': 'facebook',
      'enabled': true,
      'goals': 'key',
      'final_result': false,
      'hold_seconds': 240,
      'min_gap_seconds': 600,
      'daily_cap': 10,
    });
    expect(_body(ctx.captured[1]), <String, Object?>{
      'fixture_id': _fixture,
      'covered': false,
    });
    expect(ctx.captured[2].url.path, '/admin/publisher/badges');
    expect(_body(ctx.captured[2]), <String, Object?>{
      'team_id': _team,
      'fill': '#FFDD00',
      'label': 'النصر',
    });
  });

  test('an action on a post, its picture and the account check', () async {
    final List<int> jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
    final ctx = buildTransport((request) async {
      final String path = request.url.path;
      if (path.endsWith('/card')) return http.Response.bytes(jpeg, 200);
      if (path == '/admin/publisher/accounts') {
        return okJson(const {
          'accounts': [
            {'platform': 'facebook', 'ok': true, 'detail': 'نُخبة'},
            {'platform': 'instagram', 'ok': false, 'detail': 'انتهى الرمز'},
          ],
        });
      }
      final Map<String, Object?> sent =
          jsonDecode(request.body) as Map<String, Object?>;
      return okJson({'id': _post, 'action': sent['action']});
    });
    final AdminApi api = AdminApi(ctx.transport);

    final acted = await api.actOnPublisherPost(_post, 'shared');
    final card = await api.publisherCard(_post);
    final accounts = await api.publisherAccounts();

    expect(acted, const Result<String>.ok('shared'));
    expect(ctx.captured[0].method, 'POST');
    expect(ctx.captured[0].url.path, '/admin/publisher/posts/$_post');
    expect(_body(ctx.captured[0]), <String, Object?>{'action': 'shared'});
    expect(ctx.captured[1].url.path, '/admin/publisher/posts/$_post/card');
    expect((card as Ok<Uint8List?>).value, jpeg);
    final List<PublisherAccountDto> list =
        (accounts as Ok<List<PublisherAccountDto>>).value;
    expect(list.map((a) => a.platform).toList(), <String>[
      'facebook',
      'instagram',
    ]);
    expect(list.first.ok, isTrue);
    expect(list.last.detail, 'انتهى الرمز');
  });

  test('a refusal keeps the server code and its Arabic message', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(
        409,
        'publisher.unavailable',
        'النشر الرياضي غير مفعّل على الخادم (NUKHBA_PUBLISHER).',
      ),
    );

    final result = await AdminApi(ctx.transport).publisherOverview();

    final AppError error = (result as Err<PublisherOverviewDto>).error;
    expect(error.code, 'publisher.unavailable');
    expect(error.message, contains('NUKHBA_PUBLISHER'));
  });
}
