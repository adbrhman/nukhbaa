import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
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
  final isProd = Platform.environment['NUKHBA_ENV'] == 'production';
  return isProd
      ? const ['https://adbrhman.github.io']
      : const ['https://adbrhman.github.io', 'http://localhost:*'];
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

  return (context) async {
    final origin = context.request.headers['origin'];
    final corsHeaders = <String, Object>{
      if (_originAllowed(origin, allowed))
        'Access-Control-Allow-Origin': origin!,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Max-Age': '86400',
      'Vary': 'Origin',
    };

    if (context.request.method == HttpMethod.options) {
      return Response(
        statusCode: 204,
        headers: {...corsHeaders, ...securityHeaders},
      );
    }

    Response response;
    try {
      response = await withCompositionRoot(context);
    } on Object catch (error, stackTrace) {
      // Anything that escapes a handler used to be answered by the framework
      // with a bare 500 carrying none of the headers below -- so the web
      // build saw an opaque CORS failure rather than the error, and the
      // container log, which is the only observability this deployment has,
      // said nothing at all. Same envelope as every other error response.
      // ignore: avoid_print
      print('[middleware] unhandled failure: $error\n$stackTrace');
      response = Response.json(
        statusCode: HttpStatus.internalServerError,
        body: const ErrorResponseDto(
          code: 'server.unexpected',
          message: 'Unexpected server error',
        ).toJson(),
      );
    }
    return response.copyWith(
      headers: {...response.headers, ...corsHeaders, ...securityHeaders},
    );
  };
}
