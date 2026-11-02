/// Support pictures in Supabase Storage (script 199, migration 0196).
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// The private bucket the support pictures live in (migration 0196).
const String supportImagesBucket = 'support-images';

/// Where support pictures are put and read.
abstract interface class SupportImageStore {
  /// Puts [bytes] of type [mime] at [path].
  Future<Result<void>> put(String path, List<int> bytes, String mime);

  /// The bytes at [path].
  Future<Result<List<int>>> get(String path);
}

/// [SupportImageStore] over Supabase Storage's REST API, with the project's
/// secret key: the bucket is private, and only this server reads it.
final class SupabaseStorageImageStore implements SupportImageStore {
  /// Talks to [storageUri] (`https://<ref>.supabase.co/storage/v1/`).
  SupabaseStorageImageStore({
    required Uri storageUri,
    required String serviceKey,
    required http.Client httpClient,
    String bucket = supportImagesBucket,
    Duration timeout = const Duration(seconds: 15),
  }) : _storage = storageUri,
       _key = serviceKey,
       _http = httpClient,
       _bucket = bucket,
       _timeout = timeout;

  /// The store for [env], or null without `NUKHBA_SUPABASE_SERVICE_KEY` or
  /// `NUKHBA_SUPABASE_PROJECT_REF`: the pictures then stay in the database.
  static SupabaseStorageImageStore? fromEnv(
    Map<String, String> env,
    http.Client httpClient,
  ) {
    final String key = (env['NUKHBA_SUPABASE_SERVICE_KEY'] ?? '').trim();
    final String ref = (env['NUKHBA_SUPABASE_PROJECT_REF'] ?? '').trim();
    if (key.isEmpty || ref.isEmpty) {
      return null;
    }
    return SupabaseStorageImageStore(
      storageUri: Uri.parse('https://$ref.supabase.co/storage/v1/'),
      serviceKey: key,
      httpClient: httpClient,
    );
  }

  final Uri _storage;
  final String _key;
  final http.Client _http;
  final String _bucket;
  final Duration _timeout;

  Uri _object(String path) => _storage.resolve('object/$_bucket/$path');

  /// The legacy service_role key is a JWT and goes in Authorization too;
  /// a secret key (sb_secret_...) only in apikey, as the gateway expects.
  Map<String, String> get _auth => <String, String>{
    'apikey': _key,
    if (_key.startsWith('eyJ')) 'authorization': 'Bearer $_key',
  };

  @override
  Future<Result<void>> put(String path, List<int> bytes, String mime) async {
    try {
      final response = await _http
          .post(
            _object(path),
            headers: <String, String>{
              ..._auth,
              'content-type': mime,
              'cache-control': 'max-age=31536000',
              'x-upsert': 'true',
            },
            body: bytes,
          )
          .timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const Result.ok(null);
      }
      return Result.err(_refused('put', response.statusCode));
    } on Object catch (cause) {
      return Result.err(
        AppError.transient(
          'storage.unreachable',
          'Storage is unreachable',
          cause,
        ),
      );
    }
  }

  @override
  Future<Result<List<int>>> get(String path) async {
    try {
      final response = await _http
          .get(_object(path), headers: _auth)
          .timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return Result.ok(response.bodyBytes);
      }
      return Result.err(_refused('get', response.statusCode));
    } on Object catch (cause) {
      return Result.err(
        AppError.transient(
          'storage.unreachable',
          'Storage is unreachable',
          cause,
        ),
      );
    }
  }

  static AppError _refused(String what, int status) => AppError.transient(
    'storage.refused',
    'Storage refused the $what (HTTP $status)',
  );
}
