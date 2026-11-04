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
/// `instagram_basic` and `instagram_content_publish`) and the account's id
/// (`NUKHBA_META_IG_USER_ID`).
final class InstagramPoster implements PlatformPoster {
  /// Posts to Instagram account [igUserId] with [token].
  InstagramPoster({
    required String igUserId,
    required String token,
    required http.Client httpClient,
    String version = defaultGraphVersion,
    Duration timeout = const Duration(seconds: 30),
    Duration containerWait = const Duration(seconds: 3),
  }) : _igUserId = igUserId,
       _containerWait = containerWait,
       _graph = _Graph(
         token: token,
         client: httpClient,
         version: version,
         timeout: timeout,
       );

  final String _igUserId;
  final Duration _containerWait;
  final _Graph _graph;

  @override
  PublishPlatform get platform => PublishPlatform.instagram;

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
    final (made, madeFailure) = await _graph.post(
      '$_igUserId/media',
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
    for (var look = 0; look < 3; look++) {
      final status = await _graph.get(container, <String, String>{
        'fields': 'status_code',
      });
      final code = status is Ok<Map<String, Object?>>
          ? status.value['status_code']?.toString()
          : null;
      if (code == 'FINISHED') {
        break;
      }
      if (code == 'ERROR' || code == 'EXPIRED') {
        return PosterRejected('container_$code');
      }
      await Future<void>.delayed(_containerWait);
    }
    final (published, publishFailure) = await _graph.post(
      '$_igUserId/media_publish',
      <String, String>{'creation_id': container},
    );
    if (published != null && published.ok) {
      final id = published.body['id'];
      return id == null
          ? const PosterUncertain('graph_no_id')
          : PosterPublished(id.toString());
    }
    return _Graph.failure(published, publishFailure);
  }

  @override
  Future<Result<String>> verify() async {
    final read = await _graph.get(_igUserId, <String, String>{
      'fields': 'username',
    });
    return read.map((body) => body['username']?.toString() ?? _igUserId);
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
/// token, Instagram with an Instagram user id and the same token. X is
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
    if (igUserId.isNotEmpty)
      PublishPlatform.instagram: InstagramPoster(
        igUserId: igUserId,
        token: token,
        httpClient: httpClient,
        version: graphVersion,
      ),
  };
}
