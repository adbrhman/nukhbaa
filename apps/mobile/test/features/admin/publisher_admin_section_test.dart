/// «النشر الرياضي الذكي» (script 209), through the real
/// [PublisherAdminSection], its providers, the real `AdminApi` and
/// `ApiTransport`, against a fake of the server's `/admin/publisher` routes
/// (script 208), in the real dark theme and in Arabic: picking matches,
/// each platform's setting (asked first while the server posts for real),
/// the account check, club colours, the log (an uncertain post warned
/// before a retry, an X post shared then marked shared, a picture's
/// preview) and the performance. Also every tab on a 360px phone at text
/// x2.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_publisher_providers.dart';
import 'package:mobile/features/admin/screens/sections/publisher_admin_section.dart';
import 'package:mobile/features/admin/screens/sections/publisher_admin_tabs.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

import '../../support/auth_harness.dart';
import '../support/support_fake_server.dart';

const String _m1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const String _m2 = 'aaaaaaaa-0000-4000-8000-000000000002';
const String _hilal = 'bbbbbbbb-0000-4000-8000-000000000001';
const String _nassr = 'bbbbbbbb-0000-4000-8000-000000000002';
const String _ittihad = 'bbbbbbbb-0000-4000-8000-000000000003';
const String _ahli = 'bbbbbbbb-0000-4000-8000-000000000004';
const String _fbGoal = 'cccccccc-0000-4000-8000-000000000001';
const String _igFinal = 'cccccccc-0000-4000-8000-000000000002';
const String _xGoal = 'cccccccc-0000-4000-8000-000000000003';
const String _uncertain = 'cccccccc-0000-4000-8000-000000000004';
const String _failed = 'cccccccc-0000-4000-8000-000000000005';
const String _fbFinal = 'cccccccc-0000-4000-8000-000000000006';

Map<String, Object?> _post(
  String id,
  String platform,
  String kind,
  String state, {
  String body = 'هدف للهلال! 1-0',
  bool card = true,
  String? error,
  int attempts = 0,
  int? reach,
  int? reactions,
  int? comments,
  int? shares,
}) => <String, Object?>{
  'id': id,
  'fixture_id': _m1,
  'match_label': 'الهلال - النصر',
  'kind': kind,
  'platform': platform,
  'state': state,
  'body': body,
  'has_card': card,
  'created_at': '2026-11-05T17:20:00.000Z',
  'published_at': state == 'published' ? '2026-11-05T17:21:00.000Z' : null,
  'attempts': attempts,
  'error': error,
  'reach': reach,
  'reactions': reactions,
  'comments': comments,
  'shares': shares,
};

/// The server's publisher routes over one state, changed by the calls.
final class _FakePublisher {
  String mode = 'dry_run';
  bool off = false;
  List<String> linked = <String>['facebook'];
  final List<Map<String, Object?>> settings = <Map<String, Object?>>[
    <String, Object?>{
      'platform': 'facebook',
      'enabled': false,
      'goals': 'all',
      'final_result': true,
      'hold_seconds': 180,
      'min_gap_seconds': 0,
      'daily_cap': 12,
    },
    <String, Object?>{
      'platform': 'instagram',
      'enabled': false,
      'goals': 'all',
      'final_result': true,
      'hold_seconds': 480,
      'min_gap_seconds': 0,
      'daily_cap': 8,
    },
    <String, Object?>{
      'platform': 'x',
      'enabled': false,
      'goals': 'all',
      'final_result': true,
      'hold_seconds': 180,
      'min_gap_seconds': 0,
      'daily_cap': 20,
    },
  ];
  final Map<String, bool> covered = <String, bool>{_m1: true, _m2: false};
  final List<Map<String, Object?>> posts = <Map<String, Object?>>[
    _post(
      _fbGoal,
      'facebook',
      'goal',
      'published',
      reach: 900,
      reactions: 30,
      comments: 4,
      shares: 2,
    ),
    _post(
      _igFinal,
      'instagram',
      'final',
      'published',
      body: 'انتهت: الهلال 2-1 النصر',
      reach: 2000,
      reactions: 50,
      comments: 1,
    ),
    _post(_xGoal, 'x', 'goal', 'ready_to_share'),
    _post(
      _uncertain,
      'facebook',
      'goal',
      'uncertain',
      error: 'انقطع الاتصال بعد الإرسال',
      attempts: 1,
    ),
    _post(
      _failed,
      'instagram',
      'goal',
      'failed',
      error: 'Media fetch failed',
      attempts: 5,
    ),
    _post(
      _fbFinal,
      'facebook',
      'final',
      'published',
      body: 'انتهت: الهلال 2-1 النصر',
      card: false,
    ),
  ];
  final List<Map<String, Object?>> badges = <Map<String, Object?>>[
    <String, Object?>{
      'team_id': _hilal,
      'team_name': 'الهلال',
      'fill': '#1978D1',
      'label': 'هلال',
    },
  ];
  static const Map<String, String> teams = <String, String>{
    _hilal: 'الهلال',
    _nassr: 'النصر',
    _ittihad: 'الاتحاد',
    _ahli: 'الأهلي',
  };
  final List<http.Request> requests = <http.Request>[];

  http.Response _json(Object body, [int code = 200]) => http.Response(
    jsonEncode(body),
    code,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  List<http.Request> sent(String method, String path) => <http.Request>[
    for (final http.Request r in requests)
      if (r.method == method && r.url.path == path) r,
  ];

  Map<String, Object?> bodyOf(http.Request r) =>
      jsonDecode(r.body) as Map<String, Object?>;

  Map<String, Object?> _overview() => <String, Object?>{
    'mode': mode,
    'settings': settings,
    'candidates': <Object?>[
      <String, Object?>{
        'fixture_id': _m1,
        'home_name': 'الهلال',
        'away_name': 'النصر',
        'league_name': 'دوري روشن',
        'kickoff_at': '2026-11-05T17:00:00.000Z',
        'covered': covered[_m1],
      },
      <String, Object?>{
        'fixture_id': _m2,
        'home_name': 'الاتحاد',
        'away_name': 'الأهلي',
        'league_name': 'دوري روشن',
        'kickoff_at': '2026-11-05T19:00:00.000Z',
        'covered': covered[_m2],
      },
    ],
    'posts': posts,
    'badges': badges,
    'linked': linked,
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    final List<String> parts = request.url.pathSegments;
    if (path == '/teams') {
      return _json(<Object?>[
        for (final MapEntry<String, String> team in teams.entries)
          <String, Object?>{
            'schema_version': 1,
            'id': team.key,
            'name': team.value,
            'short_name': null,
            'crest_url': null,
            'league_id': null,
          },
      ]);
    }
    if (path == '/admin/publisher') {
      if (off) {
        return errorEnvelope(
          409,
          'publisher.unavailable',
          'النشر الرياضي غير مفعّل على الخادم (NUKHBA_PUBLISHER).',
        );
      }
      if (request.method == 'PUT') {
        final Map<String, Object?> body = bodyOf(request);
        final int at = settings.indexWhere(
          (Map<String, Object?> s) => s['platform'] == body['platform'],
        );
        settings[at] = body;
        return _json(body);
      }
      return _json(_overview());
    }
    if (path == '/admin/publisher/matches') {
      final Map<String, Object?> body = bodyOf(request);
      covered[body['fixture_id']! as String] = body['covered']! as bool;
      return _json(body);
    }
    if (path == '/admin/publisher/badges') {
      final Map<String, Object?> body = bodyOf(request);
      final String teamId = body['team_id']! as String;
      badges
        ..removeWhere((Map<String, Object?> b) => b['team_id'] == teamId)
        ..add(<String, Object?>{
          'team_id': teamId,
          'team_name': teams[teamId],
          'fill': body['fill'],
          'label': body['label'],
        });
      return _json(<String, Object?>{...body, 'team_name': ''});
    }
    if (path == '/admin/publisher/accounts/probe') {
      return _json(<String, Object?>{
        'platform': 'instagram',
        'ok': true,
        'detail': 'الحصة 3/100',
      });
    }
    if (path == '/admin/publisher/accounts') {
      return _json(<String, Object?>{
        'accounts': <Object?>[
          <String, Object?>{
            'platform': 'facebook',
            'ok': true,
            'detail': 'صفحة نُخبة',
          },
        ],
      });
    }
    if (parts.length >= 4 && parts[2] == 'posts') {
      final String id = parts[3];
      if (parts.length == 5 && parts[4] == 'card') {
        return http.Response.bytes(FakeSupportServer.png, 200);
      }
      final String action = bodyOf(request)['action']! as String;
      final Map<String, Object?> post = posts.firstWhere(
        (Map<String, Object?> p) => p['id'] == id,
      );
      post['state'] = switch (action) {
        'retry' => 'queued',
        'cancel' => 'cancelled',
        _ => 'shared',
      };
      return _json(<String, Object?>{'id': id, 'action': action});
    }
    return okMe(sampleUser);
  }
}

Future<List<ShareParams>> _pump(
  WidgetTester tester,
  _FakePublisher server, {
  PublisherTab tab = PublisherTab.matches,
  double textScale = 1,
  Size size = const Size(1080, 2400),
  double ratio = 1,
}) async {
  final AuthHarness harness = buildAuthHarness(server.handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final List<ShareParams> shared = <ShareParams>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...harness.overrides,
        publisherShareSheetProvider.overrideWithValue((
          ShareParams params,
        ) async {
          shared.add(params);
          return null;
        }),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: PublisherAdminSection(initialTab: tab)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shared;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

/// The state tag of post [id] reads [label].
void _expectState(String id, String label) {
  expect(
    find.descendant(
      of: find.byKey(Key('admin.publisher.post.$id.state')),
      matching: find.text(label),
    ),
    findsOneWidget,
  );
}

void main() {
  testWidgets('the server switched off says what to set, not an error', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher()..off = true;
    await _pump(tester, server);

    expect(
      find.byKey(const Key('admin.publisher.unavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('NUKHBA_PUBLISHER على dry_run'), findsOneWidget);

    server.off = false;
    await _tap(tester, const Key('admin.publisher.reload'));
    expect(
      find.byKey(const Key('admin.publisher.mode.dry_run')),
      findsOneWidget,
    );
  });

  testWidgets('matches: picked ones counted, one more picked by its switch', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher();
    await _pump(tester, server);

    expect(find.text('اخترت 1 من 2'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('admin.publisher.cover.$_m1')))
          .value,
      isTrue,
    );

    await _tap(tester, const Key('admin.publisher.cover.$_m2'));

    final http.Request put = server
        .sent('PUT', '/admin/publisher/matches')
        .single;
    expect(server.bodyOf(put), <String, Object?>{
      'fixture_id': _m2,
      'covered': true,
    });
    expect(find.text('اخترت 2 من 2'), findsOneWidget);
    expect(find.text('تُغطّى الآن: الاتحاد - الأهلي'), findsOneWidget);

    await _tap(tester, const Key('admin.publisher.cover.$_m1'));
    await _tap(tester, const Key('admin.publisher.matches.covered'));
    expect(find.byKey(const Key('admin.publisher.match.$_m1')), findsNothing);
    expect(find.byKey(const Key('admin.publisher.match.$_m2')), findsOneWidget);
  });

  testWidgets('settings: a draft saved by its button; going live asks first', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher()..mode = 'on';
    await _pump(tester, server, tab: PublisherTab.settings);

    expect(find.byKey(const Key('admin.publisher.mode.on')), findsOneWidget);
    expect(
      _text(tester, const Key('admin.publisher.hold.instagram.value')),
      '8 دقيقة',
    );
    expect(
      _text(tester, const Key('admin.publisher.cap.x.value')),
      '20 في اليوم',
    );
    // Instagram holds no account on the server: it says so.
    expect(
      find.byKey(const Key('admin.publisher.notLinked.instagram')),
      findsOneWidget,
    );

    await _tap(tester, const Key('admin.publisher.enabled.facebook'));
    await _tap(tester, const Key('admin.publisher.hold.facebook.more'));
    await _tap(tester, const Key('admin.publisher.goals.facebook.key'));
    await _tap(tester, const Key('admin.publisher.gap.facebook.more'));
    await _tap(tester, const Key('admin.publisher.cap.facebook.less'));
    expect(
      _text(tester, const Key('admin.publisher.hold.facebook.value')),
      '4 دقيقة',
    );

    await _tap(tester, const Key('admin.publisher.save.facebook'));
    expect(find.text('تشغيل فيسبوك؟'), findsOneWidget);
    await _tap(tester, const Key('admin.publisher.confirm.cancel'));
    expect(server.sent('PUT', '/admin/publisher'), isEmpty);

    await _tap(tester, const Key('admin.publisher.save.facebook'));
    await _tap(tester, const Key('admin.publisher.confirm.ok'));

    expect(
      server.bodyOf(server.sent('PUT', '/admin/publisher').single),
      <String, Object?>{
        'platform': 'facebook',
        'enabled': true,
        'goals': 'key',
        'final_result': true,
        'hold_seconds': 240,
        'min_gap_seconds': 60,
        'daily_cap': 11,
      },
    );
    expect(find.text('حُفظت إعدادات فيسبوك'), findsOneWidget);

    // X is only prepared, never posted: switched on without a question.
    await _tap(tester, const Key('admin.publisher.enabled.x'));
    await _tap(tester, const Key('admin.publisher.save.x'));
    expect(find.text('تشغيل X؟'), findsNothing);
    expect(server.sent('PUT', '/admin/publisher'), hasLength(2));
    expect(server.settings.last['enabled'], isTrue);
  });

  testWidgets('accounts: linked or not, and the check names the account', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher();
    await _pump(tester, server, tab: PublisherTab.accounts);

    expect(
      _text(tester, const Key('admin.publisher.account.facebook.status')),
      'مربوط',
    );
    expect(
      _text(tester, const Key('admin.publisher.account.instagram.status')),
      'غير مربوط',
    );
    expect(
      find.text(
        'يحتاج على الخادم: NUKHBA_META_IG_USER_ID, NUKHBA_META_PAGE_TOKEN',
      ),
      findsOneWidget,
    );
    expect(
      _text(tester, const Key('admin.publisher.account.x.status')),
      'مشاركة يدوية من هاتفك، بلا حساب على الخادم.',
    );

    await _tap(tester, const Key('admin.publisher.accounts.test'));

    expect(server.sent('GET', '/admin/publisher/accounts'), hasLength(1));
    expect(
      _text(tester, const Key('admin.publisher.account.facebook.check')),
      'يعمل: صفحة نُخبة',
    );
  });

  testWidgets('accounts: the Instagram check posts nothing and shows why', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher()
      ..linked = <String>['facebook', 'instagram'];
    await _pump(tester, server, tab: PublisherTab.accounts);

    await _tap(tester, const Key('admin.publisher.accounts.probe'));

    expect(
      server.sent('POST', '/admin/publisher/accounts/probe'),
      hasLength(1),
    );
    expect(
      _text(tester, const Key('admin.publisher.account.instagram.probe')),
      'النشر جاهز: الحصة 3/100',
    );
  });

  testWidgets('club colours: a picked match club, a checked colour, saved', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher();
    await _pump(tester, server, tab: PublisherTab.badges);

    // Al Nassr plays a picked match and has no colour: offered first.
    expect(
      find.byKey(const Key('admin.publisher.badge.pick.$_nassr')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.publisher.badge.pick.$_hilal')),
      findsNothing,
    );
    await _tap(tester, const Key('admin.publisher.badge.pick.$_nassr'));
    expect(_text(tester, const Key('admin.publisher.badge.team')), 'النصر');

    await tester.enterText(
      find.byKey(const Key('admin.publisher.badge.colour')),
      'FFDD00',
    );
    await _tap(tester, const Key('admin.publisher.badge.save'));
    expect(find.text('اللون يُكتب هكذا: #1978D1'), findsOneWidget);
    expect(server.sent('PUT', '/admin/publisher/badges'), isEmpty);

    await _tap(tester, const Key('admin.publisher.badge.swatch.3'));
    await _tap(tester, const Key('admin.publisher.badge.save'));

    expect(
      server.bodyOf(server.sent('PUT', '/admin/publisher/badges').single),
      <String, Object?>{'team_id': _nassr, 'fill': '#FFDD00', 'label': null},
    );
    expect(find.text('حُفظت شارة النصر'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.publisher.badge.$_nassr')),
      findsOneWidget,
    );

    // A club set is edited with its colour and words; any club is found.
    await _tap(tester, const Key('admin.publisher.badge.edit.$_hilal'));
    final TextField colour = tester.widget<TextField>(
      find.byKey(const Key('admin.publisher.badge.colour')),
    );
    expect(colour.controller!.text, '#1978D1');
    await _tap(tester, const Key('admin.publisher.badge.clear'));
    await tester.enterText(
      find.byKey(const Key('admin.publisher.badge.search')),
      'اتح',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('admin.publisher.badge.pick.$_ittihad')),
      findsOneWidget,
    );
  });

  test('a disc writes navy on a light colour and white on a dark one', () {
    const Color navy = Color(0xFF071426);
    expect(publisherInkOn(publisherColourOf('#FFDD00')), navy);
    expect(
      publisherInkOn(publisherColourOf('#D71920')),
      const Color(0xFFFFFFFF),
    );
    expect(publisherColourOf('red'), navy);
    expect(publisherShortLabel('الهلال'), 'هلال');
    expect(publisherShortLabel('النصر'), 'النصر');
    expect(publisherShortLabel('ريال مدريد'), 'ريال مدريد');
  });

  testWidgets('log: an uncertain post is retried only after the warning', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher();
    await _pump(tester, server, tab: PublisherTab.log);

    expect(
      find.byKey(const Key('admin.publisher.post.$_uncertain.uncertain')),
      findsOneWidget,
    );
    expect(find.text('الخطأ: Media fetch failed'), findsOneWidget);
    // A published post is not retried; a queued or prepared one is the
    // only kind that may be cancelled.
    expect(
      find.byKey(const Key('admin.publisher.post.$_fbGoal.retry')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('admin.publisher.post.$_xGoal.cancel')),
      findsOneWidget,
    );

    await _tap(tester, const Key('admin.publisher.post.$_uncertain.retry'));
    expect(find.text('قد يكون منشوراً بالفعل'), findsOneWidget);
    expect(find.textContaining('إلى فيسبوك'), findsOneWidget);
    await _tap(tester, const Key('admin.publisher.confirm.cancel'));
    expect(server.sent('POST', '/admin/publisher/posts/$_uncertain'), isEmpty);

    await _tap(tester, const Key('admin.publisher.post.$_uncertain.retry'));
    await _tap(tester, const Key('admin.publisher.confirm.ok'));

    expect(
      server.bodyOf(
        server.sent('POST', '/admin/publisher/posts/$_uncertain').single,
      ),
      <String, Object?>{'action': 'retry'},
    );
    expect(find.text('عاد المنشور إلى الطابور'), findsOneWidget);
    _expectState(_uncertain, 'في الطابور');
  });

  testWidgets('log: an X post is shared with its picture, then marked', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher();
    final List<ShareParams> shared = await _pump(
      tester,
      server,
      tab: PublisherTab.log,
    );

    await _tap(tester, const Key('admin.publisher.post.$_xGoal.share'));

    final ShareParams params = shared.single;
    expect(params.text, 'هدف للهلال! 1-0');
    expect(params.files!.single.mimeType, 'image/jpeg');
    expect(
      await params.files!.single.readAsBytes(),
      Uint8List.fromList(FakeSupportServer.png),
    );
    expect(
      server.sent('GET', '/admin/publisher/posts/$_xGoal/card'),
      hasLength(1),
    );

    await _tap(tester, const Key('admin.publisher.post.$_xGoal.shared'));

    expect(
      server.bodyOf(
        server.sent('POST', '/admin/publisher/posts/$_xGoal').single,
      ),
      <String, Object?>{'action': 'shared'},
    );
    _expectState(_xGoal, 'تمت مشاركته');
    expect(
      find.byKey(const Key('admin.publisher.post.$_xGoal.share')),
      findsNothing,
    );
  });

  testWidgets('log: a picture is previewed; the filter keeps what needs you', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher();
    await _pump(tester, server, tab: PublisherTab.log);

    // A post with no picture offers no preview.
    expect(
      find.byKey(const Key('admin.publisher.post.$_fbFinal.preview')),
      findsNothing,
    );
    await _tap(tester, const Key('admin.publisher.post.$_xGoal.preview'));
    expect(
      find.byKey(const Key('admin.publisher.preview.image')),
      findsOneWidget,
    );
    await _tap(tester, const Key('admin.publisher.preview.close'));
    expect(find.byKey(const Key('admin.publisher.preview')), findsNothing);

    await _tap(tester, const Key('admin.publisher.log.filter.attention'));
    expect(
      find.byKey(const Key('admin.publisher.post.$_xGoal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.publisher.post.$_uncertain')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.publisher.post.$_failed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.publisher.post.$_fbGoal')),
      findsNothing,
    );
  });

  testWidgets('performance: each platform summed, the most engaging first', (
    tester,
  ) async {
    final _FakePublisher server = _FakePublisher();
    await _pump(tester, server, tab: PublisherTab.performance);

    final Finder facebook = find.byKey(
      const Key('admin.publisher.performance.facebook'),
    );
    expect(
      find.descendant(of: facebook, matching: find.text('المنشورات: 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facebook, matching: find.text('30')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: facebook,
        matching: find.text('لم يُقرأ تفاعلها بعد: 1'),
      ),
      findsOneWidget,
    );
    final double instagramTop = tester
        .getTopLeft(find.byKey(const Key('admin.publisher.top.$_igFinal')))
        .dy;
    final double facebookTop = tester
        .getTopLeft(find.byKey(const Key('admin.publisher.top.$_fbGoal')))
        .dy;
    expect(instagramTop, lessThan(facebookTop));
    expect(
      find.byKey(const Key('admin.publisher.top.$_fbFinal')),
      findsNothing,
    );
  });

  testWidgets('every tab fits a 360px phone at text x2', (tester) async {
    final _FakePublisher server = _FakePublisher()..mode = 'on';
    await _pump(
      tester,
      server,
      textScale: 2,
      size: const Size(1080, 2340),
      ratio: 3,
    );
    expect(tester.takeException(), isNull);

    for (final PublisherTab tab in PublisherTab.values) {
      await _tap(tester, Key('admin.publisher.tab.${tab.name}'));
      expect(tester.takeException(), isNull, reason: tab.name);
    }

    // The log's last post is built and reachable at that size.
    await _tap(tester, const Key('admin.publisher.tab.log'));
    await tester.ensureVisible(
      find.byKey(const Key('admin.publisher.post.$_fbFinal')),
    );
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.publisher.post.$_uncertain.retry'));
    expect(find.text('قد يكون منشوراً بالفعل'), findsOneWidget);
    await _tap(tester, const Key('admin.publisher.confirm.cancel'));

    // The log scrolled the header chips out of the lazy list; back to the top.
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('admin.publisher.list')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.publisher.tab.badges'));
    await _tap(tester, const Key('admin.publisher.badge.pick.$_nassr'));
    await tester.ensureVisible(
      find.byKey(const Key('admin.publisher.badge.save')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
