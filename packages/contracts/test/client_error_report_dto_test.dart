import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('a report round-trips and omits what is absent', () {
    const report = ClientErrorReportDto(
      source: 'web',
      errorType: 'TypeError',
      message: 'Null check operator used on a null value',
      build: 'abc1234',
      route: 'GET /seasons/:id',
      requestId: '0123456789abcdef',
    );

    final json = report.toJson();
    expect(json.containsKey('stack'), isFalse);
    expect(json.containsKey('fatal'), isFalse);
    expect(ClientErrorReportDto.fields, containsAll(json.keys));

    final back = ClientErrorReportDto.fromJson(json);
    expect(back.source, 'web');
    expect(back.route, 'GET /seasons/:id');
    expect(back.requestId, '0123456789abcdef');
    expect(back.fatal, isFalse);
  });

  test('every field a full report carries is accepted', () {
    const report = ClientErrorReportDto(
      source: 'android',
      errorType: 'StateError',
      message: 'x',
      build: 'abc1234',
      errorCode: 'api_client.timeout',
      stack: '#0 main',
      route: 'building FixtureCard',
      device: 'samsung SM-A105F',
      os: 'Android 11',
      browser: 'chrome',
      requestId: '0123456789abcdef',
      installId: 'install',
      fatal: true,
    );

    expect(ClientErrorReportDto.fields, containsAll(report.toJson().keys));
  });

  test('the acknowledgement carries the problem code', () {
    final ack = ClientErrorReportAckDto.fromJson(
      const ClientErrorReportAckDto(problemCode: 'K7Q2').toJson(),
    );

    expect(ack.problemCode, 'K7Q2');
  });

  test('the error envelope carries a problem code only when there is one', () {
    const plain = ErrorResponseDto(code: 'a.b', message: 'm');
    const logged = ErrorResponseDto(
      code: 'db.timeout',
      message: 'm',
      problemCode: 'S7L9',
    );

    expect(plain.toJson().containsKey('problem_code'), isFalse);
    expect(ErrorResponseDto.fromJson(logged.toJson()).problemCode, 'S7L9');
  });
}
