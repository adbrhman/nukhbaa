import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:infrastructure/src/support/supabase_image_store.dart';
import 'package:shared/shared.dart';

/// The public bucket the publisher's pictures live in (migration 0200).
const String publisherCardsBucket = 'publisher-cards';

/// [PublisherCardHost] over Supabase Storage: written with the project's
/// secret key through [SupabaseStorageImageStore], read by anyone at its
/// public URL, which is how Instagram fetches a picture to post.
final class SupabaseCardHost implements PublisherCardHost {
  /// Keeps pictures through [store] for the project [projectRef].
  SupabaseCardHost({
    required SupportImageStore store,
    required String projectRef,
  }) : _store = store,
       _projectRef = projectRef;

  /// The host for [env], or null without `NUKHBA_SUPABASE_SERVICE_KEY` or
  /// `NUKHBA_SUPABASE_PROJECT_REF`.
  static SupabaseCardHost? fromEnv(
    Map<String, String> env,
    http.Client httpClient,
  ) {
    final key = (env['NUKHBA_SUPABASE_SERVICE_KEY'] ?? '').trim();
    final ref = (env['NUKHBA_SUPABASE_PROJECT_REF'] ?? '').trim();
    if (key.isEmpty || ref.isEmpty) {
      return null;
    }
    return SupabaseCardHost(
      store: SupabaseStorageImageStore(
        storageUri: Uri.parse('https://$ref.supabase.co/storage/v1/'),
        serviceKey: key,
        httpClient: httpClient,
        bucket: publisherCardsBucket,
      ),
      projectRef: ref,
    );
  }

  final SupportImageStore _store;
  final String _projectRef;

  @override
  Future<Result<void>> put(String path, List<int> bytes) =>
      _store.put(path, bytes, 'image/jpeg');

  @override
  Future<Result<List<int>>> get(String path) => _store.get(path);

  @override
  Uri publicUrl(String path) => Uri.parse(
    'https://$_projectRef.supabase.co/storage/v1/object/public/'
    '$publisherCardsBucket/$path',
  );
}
