import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/bounded_body.dart';
import 'package:server/http/champion_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /admin/champions/{seasonId}/photos/{userId}` -- sets or replaces the
/// celebration picture of a crowned champion (migration 0077). Admin only.
///
/// The body is the image bytes, named by `Content-Type`, exactly like
/// `POST /me/avatar`; the same rules apply (512 KB, JPEG / PNG / WEBP). A
/// transparent PNG lets the app lay the picture over the leaderboard.
/// Answers the month's champions; a player who is not a champion of the
/// month is `409 champion.not_found`.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String userId,
) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final mime = context.request.headers[HttpHeaders.contentTypeHeader]
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

  final List<int>? bytes;
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

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminSetChampionPhoto(
    principal: principal,
    seasonId: id,
    userId: userId,
    bytes: bytes,
    mime: mime,
  );

  return switch (result) {
    Ok<List<MonthChampion>>(:final value) => Response.json(
      body: monthChampionsToDto(value).toJson(),
    ),
    Err<List<MonthChampion>>(:final error) => errorResponse(error),
  };
}
