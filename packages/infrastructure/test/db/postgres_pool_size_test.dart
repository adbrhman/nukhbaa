import 'package:infrastructure/src/db/postgres_config.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The pool size comes from `NUKHBA_PG_POOL_SIZE` (batch 156), so it can be
/// raised on the host without a release; anything unreadable keeps the
/// default, and a value out of bounds is held to them.
void main() {
  Map<String, String> env([String? pool]) => <String, String>{
    'NUKHBA_PG_HOST': 'db.example',
    'NUKHBA_PG_PORT': '6543',
    'NUKHBA_PG_DATABASE': 'postgres',
    'NUKHBA_PG_USERNAME': 'u',
    'NUKHBA_PG_PASSWORD': 'p',
    'NUKHBA_PG_POOL_SIZE': ?pool,
  };

  int poolOf(Map<String, String> e) =>
      (PostgresConfig.fromEnv(e) as Ok<PostgresConfig>).value.poolSize;

  test('absent or unreadable: the default 8', () {
    expect(poolOf(env()), 8);
    expect(poolOf(env('lots')), 8);
  });

  test('set: used, within 2..40', () {
    expect(poolOf(env('14')), 14);
    expect(poolOf(env(' 20 ')), 20);
    expect(poolOf(env('1')), 2);
    expect(poolOf(env('500')), 40);
  });
}
