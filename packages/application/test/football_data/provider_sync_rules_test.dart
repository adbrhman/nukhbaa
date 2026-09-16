import 'package:application/application.dart';
import 'package:test/test.dart';

void main() {
  test('sync mode parses leniently and defaults to off', () {
    expect(ProviderSyncMode.parse('shadow'), ProviderSyncMode.shadow);
    expect(ProviderSyncMode.parse(' ON '), ProviderSyncMode.on);
    expect(ProviderSyncMode.parse(null), ProviderSyncMode.off);
    expect(ProviderSyncMode.parse('yes'), ProviderSyncMode.off);
  });

  test('the Riyadh day turns at 21:00 UTC', () {
    expect(
      isoDay(riyadhDayOf(DateTime.utc(2026, 9, 16, 20, 59))),
      '2026-09-16',
    );
    expect(isoDay(riyadhDayOf(DateTime.utc(2026, 9, 16, 21))), '2026-09-17');
  });
}
