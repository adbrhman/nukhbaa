import 'dart:convert';

import 'package:api_client/src/api_error.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  test('a 429 from the rate limit is a transient, retryable error', () {
    final error = decodeError(
      429,
      jsonEncode({
        'schema_version': 1,
        'code': 'request.rate_limited',
        'message': 'later',
      }),
    );

    expect(kindForStatus(429), ErrorKind.transient);
    expect(error.kind, ErrorKind.transient);
    expect(error.code, 'request.rate_limited');
  });
}
