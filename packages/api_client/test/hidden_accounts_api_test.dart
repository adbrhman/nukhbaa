import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// Script 259: the owner admin reads his hidden accounts, hides one and
/// shows it again.
void main() {
  const String player = '11111111-1111-4111-8111-111111111111';

  test('hiddenAccounts reads the list', () async {
    final dto = HiddenAccountsDto(
      accounts: [
        HiddenAccountDto(
          user: const UserSummaryDto(
            id: player,
            email: 'r@t.io',
            displayName: 'مراجع التطبيق',
            status: 'active',
          ),
          hiddenAt: DateTime.utc(2026, 11, 11, 20),
        ),
      ],
    );
    final ctx = buildTransport((request) async => okJson(dto.toJson()));

    final result = await AdminApi(ctx.transport).hiddenAccounts();

    expect(result, Result<HiddenAccountsDto>.ok(dto));
    expect(ctx.captured.single.method, 'GET');
    expect(ctx.captured.single.url.path, '/admin/hidden-accounts');
  });

  test('setAccountHidden posts to hide and deletes to show', () async {
    var hidden = true;
    final ctx = buildTransport(
      (request) async => okJson(<String, Object?>{'hidden': hidden}),
    );
    final AdminApi api = AdminApi(ctx.transport);

    final Result<bool> hide = await api.setAccountHidden(player, hidden: true);
    hidden = false;
    final Result<bool> show = await api.setAccountHidden(player, hidden: false);

    expect(hide, const Result<bool>.ok(true));
    expect(show, const Result<bool>.ok(false));
    expect(ctx.captured.first.method, 'POST');
    expect(ctx.captured.last.method, 'DELETE');
    expect(ctx.captured.last.url.path, '/admin/hidden-accounts/$player');
  });
}
