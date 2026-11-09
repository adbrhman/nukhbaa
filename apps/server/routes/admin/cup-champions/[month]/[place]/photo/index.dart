import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/bounded_body.dart';
import 'package:server/http/cup_champion_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /admin/cup-champions/{monthStart}/{place}/photo` -- sets or replaces
/// the picture of the champion of one path of the Elite Cup (migration
/// 0204); `DELETE` removes it. Admin only.
///
/// The body of the `POST` is the image bytes, named by `Content-Type`,
/// exactly like `POST /me/avatar`; the same rules apply (512 KB, JPEG / PNG /
/// WEBP). Both answer the champions of the cup as they stand after the
/// change. A path without a champion is `409 cup.champion_not_found`; a
/// month that is not a first day, or a path outside 1 to 3, is
/// `400 cup.target_invalid`.
Future<Response> onRequest(
  RequestContext context,
  String month,
  String place,
) async {
  final method = context.request.method;
  if (method != HttpMethod.post && method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  String? mime;
  List<int>? bytes;
  if (method == HttpMethod.post) {
    mime = context.request.headers[HttpHeaders.contentTypeHeader]
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (mime == null || mime.isEmpty) {
      return errorResponse(
        const AppError.validation(
          'identity.avatar_mime_missing',
          'يجب تحديد نوع الصورة في ترويسة Content-Type',
        ),
      );
    }
    try {
      bytes = await readBoundedBytes(context.request, User.maxAvatarBytes);
    } on Object {
      return errorResponse(
        const AppError.validation(
          'identity.avatar_unreadable',
          'تعذّرت قراءة بيانات الصورة',
        ),
      );
    }
    // Never more than the size limit is read: a larger upload is refused
    // before the rest of it is buffered.
    if (bytes == null) {
      return errorResponse(avatarTooLarge(mime));
    }
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final cup = root.cupChampions;
  if (cup == null) {
    return errorResponse(
      const AppError.transient(
        'cup.unavailable',
        'The cup champions are unavailable',
      ),
    );
  }
  final result = method == HttpMethod.post
      ? await cup.setPhoto(
          principal: principal,
          monthStart: month,
          place: place,
          bytes: bytes!,
          mime: mime!,
        )
      : await cup.removePhoto(
          principal: principal,
          monthStart: month,
          place: place,
        );

  return switch (result) {
    Ok<List<CupChampion>>(:final value) => Response.json(
      body: cupChampionsToDto(value).toJson(),
    ),
    Err<List<CupChampion>>(:final error) => errorResponse(error),
  };
}
