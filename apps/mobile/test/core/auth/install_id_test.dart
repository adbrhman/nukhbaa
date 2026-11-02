import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/install_id.dart';

/// Script 200: the install id names the phone on every request, so it must
/// stay one id: two first reads at once make one id, and it is kept.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final RegExp shape = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  test('two first reads at once make one id, and it is stored', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final SecureInstallIdStore store = SecureInstallIdStore();

    final List<String?> ids = await Future.wait(<Future<String?>>[
      store.read(),
      store.read(),
    ]);

    expect(ids[0], isNotNull);
    expect(ids[0], matches(shape));
    expect(ids[1], ids[0]);
    expect(await SecureInstallIdStore().read(), ids[0]);
    expect(
      await const FlutterSecureStorage().read(key: SecureInstallIdStore.key),
      ids[0],
    );
  });

  test('an id already stored is the one read', () async {
    const String stored = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SecureInstallIdStore.key: stored,
    });

    expect(await SecureInstallIdStore().read(), stored);
  });
}
