import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/http/bounded_body.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// Reads a support picture's bytes and content type from [request]
/// (migration 0188): the raw bytes, as `POST /me/avatar` reads them, never
/// more than [SupportImage.maxBytes]. A refusal is the response to send.
Future<Result<(List<int>, String?)>> readSupportImage(Request request) async {
  final String? mime = request.headers[HttpHeaders.contentTypeHeader];
  final List<int>? bytes;
  try {
    bytes = await readBoundedBytes(request, SupportImage.maxBytes);
  } on Object {
    return const Result.err(
      AppError.validation('support.image_unreadable', 'تعذّرت قراءة الصورة.'),
    );
  }
  if (bytes == null) return const Result.err(SupportImage.tooLarge);
  return Result.ok((bytes, mime));
}

/// A picture as the body of a `GET`, or `404` when there is none to read.
Response supportImageResponse(Result<SupportImage?> result) => switch (result) {
  Err<SupportImage?>(:final error) => errorResponse(error),
  Ok<SupportImage?>(:final value) =>
    value == null
        ? Response(statusCode: HttpStatus.notFound)
        : Response.bytes(
            body: value.bytes,
            headers: <String, String>{
              HttpHeaders.contentTypeHeader: value.mime,
              // A message's picture never changes.
              HttpHeaders.cacheControlHeader:
                  'private, max-age=31536000, immutable',
            },
          ),
};
