import 'package:infrastructure/src/db/postgres_config.dart';
import 'package:infrastructure/src/db/supabase_root_ca.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// `NUKHBA_PG_SSL` (audit NUKHBA-002, script 108): `verify-full` turns the
/// certificate check on; every other value keeps what the server did before.
void main() {
  Map<String, String> env([String? ssl]) => <String, String>{
    'NUKHBA_PG_HOST': 'aws-0-eu-central-1.pooler.supabase.com',
    'NUKHBA_PG_PORT': '5432',
    'NUKHBA_PG_DATABASE': 'postgres',
    'NUKHBA_PG_USERNAME': 'u',
    'NUKHBA_PG_PASSWORD': 'p',
    'NUKHBA_PG_SSL': ?ssl,
  };

  PostgresConfig of(Map<String, String> e) =>
      (PostgresConfig.fromEnv(e) as Ok<PostgresConfig>).value;

  test('absent or require: encrypted, any certificate (as before)', () {
    for (final e in [env(), env('require')]) {
      expect(of(e).requireSsl, isTrue);
      expect(of(e).verifyServer, isFalse);
    }
  });

  test('verify-full: encrypted and the certificate checked', () {
    expect(of(env('verify-full')).requireSsl, isTrue);
    expect(of(env('verify-full')).verifyServer, isTrue);
  });

  test('disable: neither (local only)', () {
    expect(of(env('disable')).requireSsl, isFalse);
    expect(of(env('disable')).verifyServer, isFalse);
  });

  test('the bundled Supabase root loads as the only trust anchor', () {
    expect(supabaseRootCa2021, startsWith('-----BEGIN CERTIFICATE-----\n'));
    expect(supabaseRootCa2021, endsWith('-----END CERTIFICATE-----\n'));
    expect(supabaseSecurityContext, returnsNormally);
  });
}
