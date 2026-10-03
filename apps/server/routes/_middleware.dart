import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_capture.dart';
import 'package:server/http/request_scope.dart';
import 'package:server/http/security_headers.dart';

List<String> _allowedOrigins() {
  final raw = Platform.environment['NUKHBA_CORS_ALLOWED_ORIGINS'];
  if (raw != null && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList();
  }
  // Every host the web build is served from: the domain, its www form,
  // the Northflank mirror (github.io is blocked in Yemen) and GitHub
  // Pages. Only GitHub Pages was listed, so the build at nukhbaa.app
  // depended on NUKHBA_CORS_ALLOWED_ORIGINS being set by hand.
  const deployed = [
    'https://nukhbaa.app',
    'https://www.nukhbaa.app',
    'https://p01--nukhbaa-web--42bcqlpqwp8m.code.run',
    'https://adbrhman.github.io',
  ];
  final isProd = Platform.environment['NUKHBA_ENV'] == 'production';
  return isProd ? deployed : const [...deployed, 'http://localhost:*'];
}

bool _matchesPortWildcard(String origin, String prefix) {
  if (!origin.startsWith(prefix)) return false;
  final rest = origin.substring(prefix.length);
  return rest.isNotEmpty && int.tryParse(rest) != null;
}

bool _originAllowed(String? origin, List<String> allowed) {
  if (origin == null) return false;
  for (final pattern in allowed) {
    if (pattern.endsWith(':*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      if (_matchesPortWildcard(origin, prefix)) return true;
    } else if (pattern == origin) {
      return true;
    }
  }
  return false;
}

Handler middleware(Handler handler) {
  final allowed = _allowedOrigins();

  final withCompositionRoot = handler.use(
    provider<Future<CompositionRoot>>((_) => CompositionRoot.instance()),
  );

  // Every request gets an id (X-Request-Id) and every 5xx -- an escaped
  // exception included -- is kept in the error log (migration 0087). The
  // composition root is looked up only when there is something to keep.
  final captured = captureServerErrors(
    withCompositionRoot,
    recorder: () async => (await CompositionRoot.instance()).recordError,
  );

  return (context) async {
    final origin = context.request.headers['origin'];
    final corsHeaders = <String, Object>{
      if (_originAllowed(origin, allowed))
        'Access-Control-Allow-Origin': origin!,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Max-Age': '86400',
      'Access-Control-Expose-Headers': requestIdHeader,
      'Vary': 'Origin',
    };

    if (context.request.method == HttpMethod.options) {
      return Response(
        statusCode: 204,
        headers: {...corsHeaders, ...securityHeaders},
      );
    }

    // captureServerErrors answers an escaped exception with the uniform
    // `server.unexpected` envelope, so the CORS headers below reach it too.
    final response = await captured(context);
    return response.copyWith(
      headers: {...response.headers, ...corsHeaders, ...securityHeaders},
    );
  };
}
