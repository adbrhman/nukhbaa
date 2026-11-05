import 'dart:async';
import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// The Meta Graph API the posters speak (`NUKHBA_META_GRAPH_VERSION`).
const String defaultGraphVersion = 'v23.0';

/// One answer of the Graph API.
final class _GraphAnswer {
  const _GraphAnswer({required this.status, required this.body});

  /// 0 when no answer came.
  final int status;
  final Map<String, Object?> body;

  bool get ok => status >= 200 && status < 300 && !body.containsKey('error');

  Map<String, Object?> get _error {
    final error = body['error'];
    return error is Map<String, Object?> ? error : const <String, Object?>{};
  }

  int? get errorCode => _error['code'] is int ? _error['code']! as int : null;

  bool get transient => _error['is_transient'] == true;

  String get message => _error['message']?.toString() ?? 'HTTP $status';
}

/// Why a call never got an answer.
enum _NoAnswer {
  /// The connection was never made: nothing was sent.
  notSent,

  /// Sent, then cut or timed out: the post may exist.
  cut,
}

/// The Graph API calls both posters share. Never throws.
final class _Graph {
  _Graph({
    required this.token,
    required this.client,
    required this.version,
    required this.timeout,
  });

  final String token;
  final http.Client client;
  final String version;
  final Duration timeout;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.https('graph.facebook.com', '/$version/$path', query);

  Future<(_GraphAnswer?, _NoAnswer?)> post(
    String path,
    Map<String, String> fields,
  ) async {
    try {
      final response = await client
          .post(
            _uri(path),
            headers: <String, String>{'authorization': 'Bearer $token'},
            body: fields,
          )
          .timeout(timeout);
      return (_answer(response), null);
    } on http.ClientException catch (error) {
      // A name that does not resolve, or a refused connection: nothing was
      // written. Anything else may have reached Meta.
      final text = error.message.toLowerCase();
      final notSent =
          text.contains('failed host lookup') ||
          text.contains('connection refused');
      return (null, notSent ? _NoAnswer.notSent : _NoAnswer.cut);
    } on TimeoutException {
      return (null, _NoAnswer.cut);
    } on Object {
      return (null, _NoAnswer.cut);
    }
  }

  Future<Result<Map<String, Object?>>> get(
    String path,
    Map<String, String> query,
  ) async {
    try {
      final response = await client
          .get(
            _uri(path, query),
            headers: <String, String>{'authorization': 'Bearer $token'},
          )
          .timeout(timeout);
      final answer = _answer(response);
      if (!answer.ok) {
        return Result.err(
          AppError.transient('publisher.graph_refused', answer.message),
        );
      }
      return Result.ok(answer.body);
    } on Object catch (error) {
      return Result.err(
        AppError.transient('publisher.graph_unreachable', 'Graph API', error),
      );
    }
  }

  static _GraphAnswer _answer(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    return _GraphAnswer(
      status: response.statusCode,
      body: decoded is Map<String, Object?>
          ? decoded
          : const <String, Object?>{},
    );
  }

  /// What a failed call means for the post.
  static PosterOutcome failure(_GraphAnswer? answer, _NoAnswer? none) {
    if (answer == null) {
      return none == _NoAnswer.notSent
          ? const PosterRetry('graph_unreachable')
          : const PosterUncertain('graph_cut');
    }
    // Rate limits (4, 17, 32, 613) and the errors Meta marks transient
    // never created anything: try again later.
    const limits = <int>{4, 17, 32, 613};
    final code = answer.errorCode;
    if (answer.status == 429 || (code != null && limits.contains(code))) {
      return PosterRetry(
        'rate_limited: ${answer.message}',
        after: const Duration(minutes: 10),
      );
    }
    if (answer.transient) {
      return PosterRetry('transient: ${answer.message}');
    }
    if (answer.status >= 500) {
      // A server error after the request arrived: it may have posted.
      return PosterUncertain('graph_${answer.status}: ${answer.message}');
    }
    return PosterRejected('graph_${answer.status}: ${answer.message}');
  }

  static int? count(Object? node, String field) {
    if (node is! Map<String, Object?>) {
      return null;
    }
    final value = node[field];
    if (value is int) {
      return value;
    }
    if (value is Map<String, Object?>) {
      final summary = value['summary'];
      if (summary is Map<String, Object?> && summary['total_count'] is int) {
        return summary['total_count']! as int;
      }
      if (value['count'] is int) {
        return value['count']! as int;
      }
    }
    return null;
  }
}

/// [PlatformPoster] for the Nukhba Facebook page: a photo post on the page,
/// the picture fetched by Facebook from its public URL.
///
/// Needs a Page access token with `pages_manage_posts` and
/// `pages_read_engagement` (`NUKHBA_META_PAGE_TOKEN`) and the page's id
/// (`NUKHBA_META_PAGE_ID`).
final class FacebookPagePoster implements PlatformPoster {
  /// Posts to page [pageId] with [token].
  FacebookPagePoster({
    required String pageId,
    required String token,
    required http.Client httpClient,
    String version = defaultGraphVersion,
    Duration timeout = const Duration(seconds: 30),
  }) : _pageId = pageId,
       _graph = _Graph(
         token: token,
         client: httpClient,
         version: version,
         timeout: timeout,
       );

  final String _pageId;
  final _Graph _graph;

  @override
  PublishPlatform get platform => PublishPlatform.facebook;

  @override
  Future<PosterOutcome> post({
    required String text,
    List<int>? image,
    Uri? imageUrl,
  }) async {
    // With no picture (a correction) the words go to the page's feed.
    final (answer, none) = imageUrl == null
        ? await _graph.post('$_pageId/feed', <String, String>{'message': text})
        : await _graph.post('$_pageId/photos', <String, String>{
            'url': imageUrl.toString(),
            'message': text,
            'published': 'true',
          });
    if (answer != null && answer.ok) {
      final id = answer.body['post_id'] ?? answer.body['id'];
      if (id != null) {
        return PosterPublished(id.toString());
      }
      return const PosterUncertain('graph_no_id');
    }
    return _Graph.failure(answer, none);
  }

  @override
  Future<Result<String>> verify() async {
    final read = await _graph.get(_pageId, <String, String>{'fields': 'name'});
    return read.map((body) => body['name']?.toString() ?? _pageId);
  }

  @override
  Future<Result<PostMetrics?>> metrics(String externalId) async {
    final read = await _graph.get(externalId, <String, String>{
      'fields':
          'reactions.summary(total_count).limit(0),'
          'comments.summary(total_count).limit(0),shares',
    });
    return read.map(
      (body) => PostMetrics(
        reactions: _Graph.count(body, 'reactions'),
        comments: _Graph.count(body, 'comments'),
        shares: _Graph.count(body, 'shares'),
        raw: body,
      ),
    );
  }
}

/// [PlatformPoster] for the Nukhba Instagram business account: a container
/// made from the picture's public URL (JPEG only), then published.
///
/// Uses the Page token (Instagram linked to the Facebook page, with
/// `instagram_basic` and `instagram_content_publish`). The account is the
/// one `NUKHBA_META_IG_USER_ID` names; without it, the one the Facebook page
/// (`NUKHBA_META_PAGE_ID`) is linked to, asked from Meta once and kept, so
/// the page and its token are all the server needs.
final class InstagramPoster implements PlatformPoster {
  /// Posts to Instagram account [igUserId], or to the account linked to
  /// Facebook page [pageId] when no id is given, with [token].
  InstagramPoster({
    required String token,
    required http.Client httpClient,
    String igUserId = '',
    String pageId = '',
    String version = defaultGraphVersion,
    Duration timeout = const Duration(seconds: 30),
    Duration containerWait = const Duration(seconds: 3),
    int containerLooks = 5,
  }) : _configuredId = igUserId.trim(),
       _pageId = pageId.trim(),
       _containerWait = containerWait,
       _containerLooks = containerLooks,
       _graph = _Graph(
         token: token,
         client: httpClient,
         version: version,
         timeout: timeout,
       );

  final String _configuredId;
  final String _pageId;
  final Duration _containerWait;
  final int _containerLooks;
  final _Graph _graph;

  /// The account the page is linked to, once Meta has said.
  String? _foundId;
  String? _foundName;

  @override
  PublishPlatform get platform => PublishPlatform.instagram;

  /// The account the Facebook page is linked to: null when it is linked
  /// to none (or no page is known), an error when Meta cannot be asked.
  Future<Result<String?>> _linkedToPage() async {
    final known = _foundId;
    if (known != null) {
      return Result.ok(known);
    }
    if (_pageId.isEmpty) {
      return const Result.ok(null);
    }
    final read = await _graph.get(_pageId, <String, String>{
      'fields': 'instagram_business_account{id,username}',
    });
    if (read is Err<Map<String, Object?>>) {
      return Result.err(read.error);
    }
    final account =
        (read as Ok<Map<String, Object?>>).value['instagram_business_account'];
    if (account is! Map<String, Object?>) {
      return const Result.ok(null);
    }
    final id = account['id']?.toString();
    if (id == null || id.isEmpty) {
      return const Result.ok(null);
    }
    _foundId = id;
    _foundName = account['username']?.toString();
    return Result.ok(id);
  }

  /// The account posts go to: the configured one, else the page's.
  Future<Result<String?>> _account() async {
    if (_configuredId.isNotEmpty) {
      return Result.ok(_configuredId);
    }
    return _linkedToPage();
  }

  @override
  Future<PosterOutcome> post({
    required String text,
    List<int>? image,
    Uri? imageUrl,
  }) async {
    if (imageUrl == null) {
      // Instagram publishes no post without a picture.
      return const PosterRejected('instagram_needs_picture');
    }
    final account = await _account();
    if (account is Err<String?>) {
      // Meta could not be asked: nothing was made, try again later.
      return PosterRetry('instagram_account: ${account.error.message}');
    }
    final igUserId = (account as Ok<String?>).value;
    if (igUserId == null) {
      return const PosterRejected('instagram_not_linked');
    }
    final (made, madeFailure) = await _graph.post(
      '$igUserId/media',
      <String, String>{'image_url': imageUrl.toString(), 'caption': text},
    );
    if (made == null || !made.ok) {
      // No container, nothing published: a cut here is safe to retry.
      final outcome = _Graph.failure(made, madeFailure);
      return outcome is PosterUncertain ? PosterRetry(outcome.reason) : outcome;
    }
    final container = made.body['id']?.toString();
    if (container == null) {
      return const PosterRetry('graph_no_container');
    }
    // A picture is usually ready at once; give it a few looks.
    var code = '';
    for (var look = 0; look < _containerLooks; look++) {
      final status = await _graph.get(container, <String, String>{
        'fields': 'status_code',
      });
      code = status is Ok<Map<String, Object?>>
          ? (status.value['status_code']?.toString() ?? '')
          : '';
      if (code == 'FINISHED') {
        break;
      }
      if (code == 'ERROR' || code == 'EXPIRED') {
        return PosterRejected('container_$code');
      }
      await Future<void>.delayed(_containerWait);
    }
    if (code == 'IN_PROGRESS') {
      // Instagram is still fetching the picture: publishing now fails with
      // 9007. Nothing was published; a new container is made later.
      return const PosterRetry(
        'container_in_progress',
        after: Duration(minutes: 1),
      );
    }
    final (published, publishFailure) = await _graph.post(
      '$igUserId/media_publish',
      <String, String>{'creation_id': container},
    );
    if (published != null && published.ok) {
      final id = published.body['id'];
      return id == null
          ? const PosterUncertain('graph_no_id')
          : PosterPublished(id.toString());
    }
    if (published != null && published.errorCode == 9007) {
      // "The media is not ready for publishing": nothing was published.
      return const PosterRetry(
        'container_not_ready',
        after: Duration(minutes: 1),
      );
    }
    return _Graph.failure(published, publishFailure);
  }

  @override
  Future<Result<String>> verify() async {
    if (_configuredId.isNotEmpty) {
      final read = await _graph.get(_configuredId, <String, String>{
        'fields': 'username',
      });
      return read.map((body) => body['username']?.toString() ?? _configuredId);
    }
    final linked = await _linkedToPage();
    if (linked is Err<String?>) {
      return Result.err(linked.error);
    }
    final id = (linked as Ok<String?>).value;
    if (id == null) {
      return const Result.err(
        AppError.validation(
          'publisher.instagram_not_linked',
          'لا حساب إنستغرام مهني مرتبط بصفحة فيسبوك، أو أن رمز الصفحة بلا صلاحية instagram_basic',
        ),
      );
    }
    return Result.ok(_foundName ?? id);
  }

  @override
  Future<Result<PostMetrics?>> metrics(String externalId) async {
    final read = await _graph.get(externalId, <String, String>{
      'fields': 'like_count,comments_count',
    });
    if (read is Err<Map<String, Object?>>) {
      return Result.err(read.error);
    }
    final body = (read as Ok<Map<String, Object?>>).value;
    int? reach;
    final insights = await _graph.get('$externalId/insights', <String, String>{
      'metric': 'reach',
    });
    if (insights case Ok<Map<String, Object?>>(:final value)) {
      final data = value['data'];
      if (data is List<Object?> && data.isNotEmpty) {
        final first = data.first;
        if (first is Map<String, Object?>) {
          final values = first['values'];
          if (values is List<Object?> && values.isNotEmpty) {
            final v = values.first;
            if (v is Map<String, Object?> && v['value'] is int) {
              reach = v['value']! as int;
            }
          }
        }
      }
    }
    return Result.ok(
      PostMetrics(
        reach: reach,
        reactions: _Graph.count(body, 'like_count'),
        comments: _Graph.count(body, 'comments_count'),
        raw: body,
      ),
    );
  }
}

/// The posters `NUKHBA_META_*` configures: Facebook with a page id and a
/// token, Instagram with the same token and either an Instagram user id
/// or, without one, the page id (the account the page is linked to). X is
/// prepared for an admin to share and has no poster.
Map<PublishPlatform, PlatformPoster> metaPostersFromEnv(
  Map<String, String> env,
  http.Client httpClient,
) {
  final token = (env['NUKHBA_META_PAGE_TOKEN'] ?? '').trim();
  if (token.isEmpty) {
    return const <PublishPlatform, PlatformPoster>{};
  }
  final version = (env['NUKHBA_META_GRAPH_VERSION'] ?? '').trim();
  final graphVersion = RegExp(r'^v\d+\.\d+$').hasMatch(version)
      ? version
      : defaultGraphVersion;
  final pageId = (env['NUKHBA_META_PAGE_ID'] ?? '').trim();
  final igUserId = (env['NUKHBA_META_IG_USER_ID'] ?? '').trim();
  return <PublishPlatform, PlatformPoster>{
    if (pageId.isNotEmpty)
      PublishPlatform.facebook: FacebookPagePoster(
        pageId: pageId,
        token: token,
        httpClient: httpClient,
        version: graphVersion,
      ),
    if (igUserId.isNotEmpty || pageId.isNotEmpty)
      PublishPlatform.instagram: InstagramPoster(
        igUserId: igUserId,
        pageId: pageId,
        token: token,
        httpClient: httpClient,
        version: graphVersion,
      ),
  };
}
