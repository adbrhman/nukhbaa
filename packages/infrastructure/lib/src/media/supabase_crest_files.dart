import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:infrastructure/src/support/supabase_image_store.dart';
import 'package:shared/shared.dart';

/// The public bucket the club crests are read from (migration 0210).
const String crestsBucket = 'crests';

/// The bucket's public address for the project [ref]: a crest's URL is
/// this followed by its object path.
String crestsPublicBase(String ref) =>
    'https://$ref.supabase.co/storage/v1/object/public/$crestsBucket/';

/// [CrestFileEraser] over Supabase Storage (script 265): the support
/// pictures' REST client on the bucket `crests`, with the project's secret
/// key, which only this server holds.
final class SupabaseCrestFiles implements CrestFileEraser {
  /// Creates the eraser over [_store].
  const SupabaseCrestFiles(this._store);

  /// The eraser for [env], or null without `NUKHBA_SUPABASE_SERVICE_KEY` or
  /// `NUKHBA_SUPABASE_PROJECT_REF`.
  static SupabaseCrestFiles? fromEnv(
    Map<String, String> env,
    http.Client httpClient,
  ) {
    final String key = (env['NUKHBA_SUPABASE_SERVICE_KEY'] ?? '').trim();
    final String ref = (env['NUKHBA_SUPABASE_PROJECT_REF'] ?? '').trim();
    if (key.isEmpty || ref.isEmpty) return null;
    return SupabaseCrestFiles(
      SupabaseStorageImageStore(
        storageUri: Uri.parse('https://$ref.supabase.co/storage/v1/'),
        serviceKey: key,
        httpClient: httpClient,
        bucket: crestsBucket,
      ),
    );
  }

  final SupabaseStorageImageStore _store;

  @override
  Future<Result<void>> erase(String objectPath) =>
      _store.erase(<String>[objectPath]);
}
