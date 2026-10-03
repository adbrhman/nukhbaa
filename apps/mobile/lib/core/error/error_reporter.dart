/// Sends the app's unexpected errors to the error log (migration 0087).
///
/// Every uncaught Flutter or Dart error, and every API call the server could
/// not answer properly ([ErrorPresenter.isReportable]), becomes one report to
/// `POST /errors/report`. A report that cannot leave the device now is kept
/// (at most [ClientErrorReporter.maxPending]) and sent on the next start or
/// the next report. The player never sees a stack: only the Arabic message
/// and the problem code, which this file computes exactly as the server
/// does, so the code shown is the code the admin searches for.
library;

import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared/shared.dart';

import '../design/app_typography.dart';
import 'error_presenter.dart';

/// Where reports waiting to be sent are kept between runs.
abstract interface class PendingErrorStore {
  /// The reports waiting, oldest first, as JSON objects.
  Future<List<String>> read();

  /// Replaces the reports waiting.
  Future<void> write(List<String> reports);
}

/// [PendingErrorStore] in the platform's secure storage.
final class SecurePendingErrorStore implements PendingErrorStore {
  /// Creates the store.
  const SecurePendingErrorStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  /// The storage key.
  static const String key = 'nukhba.pending_error_reports';

  @override
  Future<List<String>> read() async {
    try {
      final String? raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return const <String>[];
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return [
        for (final Object? item in decoded)
          if (item is String) item,
      ];
    } on Object {
      return const <String>[];
    }
  }

  @override
  Future<void> write(List<String> reports) async {
    try {
      await _storage.write(key: key, value: jsonEncode(reports));
    } on Object {
      // Losing a waiting report is better than failing the app over it.
    }
  }
}

/// [PendingErrorStore] in memory, for tests.
final class MemoryPendingErrorStore implements PendingErrorStore {
  /// The reports waiting.
  List<String> reports = <String>[];

  @override
  Future<List<String>> read() async => List<String>.of(reports);

  @override
  Future<void> write(List<String> reports) async {
    this.reports = List<String>.of(reports);
  }
}

/// The device and system a report names, read once per run.
final class DeviceSummary {
  /// Creates the summary.
  const DeviceSummary({this.device, this.os, this.browser});

  /// The maker and model.
  final String? device;

  /// The operating system and version.
  final String? os;

  /// The browser, on the web.
  final String? browser;
}

/// Turns caught errors into reports and delivers them.
final class ClientErrorReporter {
  /// Creates the reporter.
  ClientErrorReporter({
    required Future<Result<ClientErrorReportAckDto>> Function(
      ClientErrorReportDto report,
    )
    send,
    required this.build,
    required PendingErrorStore store,
    Future<String?> Function()? installId,
    Future<DeviceSummary> Function()? deviceSummary,
    String? source,
  }) : _send = send,
       _store = store,
       _installId = installId ?? _noInstallId,
       _deviceSummary = deviceSummary ?? _readDeviceSummary,
       source = source ?? ErrorPresenter.errorSource;

  /// The reporter the app installed ([installErrorReporting]); null until
  /// then, and in tests.
  static ClientErrorReporter? instance;

  /// Reports kept for later at most; the oldest go first.
  static const int maxPending = 20;

  /// Reports of one error per run at most: a loop must not fill the log.
  static const int maxPerError = 3;

  /// Reports per run at most.
  static const int maxPerRun = 30;

  /// The longest stack sent, in characters.
  static const int maxStack = 16000;

  /// The build's short commit sha (`NUKHBA_BUILD_SHA`).
  final String build;

  /// `android`, `ios` or `web`.
  final String source;

  final Future<Result<ClientErrorReportAckDto>> Function(
    ClientErrorReportDto report,
  )
  _send;
  final PendingErrorStore _store;
  final Future<String?> Function() _installId;
  final Future<DeviceSummary> Function() _deviceSummary;

  final Map<String, int> _sentPerError = <String, int>{};
  int _sentThisRun = 0;
  DeviceSummary? _device;
  final Set<Future<void>> _pending = <Future<void>>{};
  Future<void> _lock = Future<void>.value();

  // Every read-modify-write of the store runs one after another, so two
  // reports caught together never overwrite each other.
  Future<T> _serial<T>(Future<T> Function() action) {
    final Future<T> next = _lock.then<T>((_) => action());
    _lock = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _track(Future<void> work) {
    _pending.add(work);
    unawaited(work.whenComplete(() => _pending.remove(work)));
  }

  /// Waits until every report caught so far is stored, then sends what is
  /// waiting.
  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_pending));
    }
    await flush();
  }

  /// The problem code of an exception, as the server will compute it.
  String codeFor(Object error, StackTrace? stack) => ErrorFingerprint.of(
    source: source,
    errorType: error.runtimeType.toString(),
    stack: _cap(stack?.toString(), maxStack),
  ).problemCode;

  /// Reports an uncaught exception; returns its problem code.
  ///
  /// [where] says what was going on (`building FixtureCard`); [fatal]
  /// whether it broke what the player saw.
  String reportException(
    Object error,
    StackTrace? stack, {
    String? where,
    bool fatal = false,
  }) {
    final String code = codeFor(error, stack);
    final String message = error.toString();
    _track(
      _report(
        code,
        ClientErrorReportDto(
          source: source,
          errorType: error.runtimeType.toString(),
          message: message.isEmpty ? error.runtimeType.toString() : message,
          build: build,
          stack: _cap(stack?.toString(), maxStack),
          route: where,
          fatal: fatal,
        ),
      ),
    );
    return code;
  }

  /// Hears every failed API call and reports those the server could not
  /// answer properly ([ErrorPresenter.isReportable]).
  void reportApiFailure(ApiFailure failure) {
    final AppError error = failure.error;
    final String? code = ErrorPresenter.problemCode(error);
    if (code == null || !ErrorPresenter.isReportable(error)) return;
    final int? status = failure.statusCode;
    _track(
      _report(
        code,
        ClientErrorReportDto(
          source: source,
          errorType: 'AppError',
          errorCode: error.code,
          message: status == null
              ? error.message
              : '${error.message} (HTTP $status)',
          build: build,
          route:
              '${failure.method} '
              '${ErrorFingerprint.normalizeVariable(failure.path)}',
          requestId: failure.requestId,
        ),
      ),
    );
  }

  Future<void> _report(String code, ClientErrorReportDto report) async {
    final int already = _sentPerError[code] ?? 0;
    if (already >= maxPerError || _sentThisRun >= maxPerRun) return;
    _sentPerError[code] = already + 1;
    _sentThisRun++;
    try {
      final DeviceSummary device = _device ??= await _deviceSummary();
      final String? install = await _installId();
      final ClientErrorReportDto full = ClientErrorReportDto(
        source: report.source,
        errorType: report.errorType,
        errorCode: report.errorCode,
        message: report.message,
        build: report.build,
        stack: report.stack,
        route: report.route,
        device: device.device,
        os: device.os,
        browser: device.browser,
        requestId: report.requestId,
        installId: install,
        fatal: report.fatal,
      );
      final String raw = jsonEncode(full.toJson());
      await _serial(() async {
        final List<String> pending = List<String>.of(await _store.read());
        pending.add(raw);
        final int extra = pending.length - maxPending;
        await _store.write(extra > 0 ? pending.sublist(extra) : pending);
      });
    } on Object {
      return;
    }
    await flush();
  }

  /// Sends every report waiting, oldest first. Stops at the first one the
  /// server could not take now (offline, rate limited) and keeps the rest;
  /// a report the server refuses outright is dropped. Flushes run one
  /// after another, never two at once.
  Future<void> flush() => _serial(_flushOnce);

  Future<void> _flushOnce() async {
    try {
      final List<String> pending = await _store.read();
      var sent = 0;
      for (final String raw in pending) {
        final ClientErrorReportDto? report = _decode(raw);
        if (report != null) {
          final Result<ClientErrorReportAckDto> result = await _send(report);
          if (result case Err<ClientErrorReportAckDto>(
            :final error,
          ) when error.isRetryable) {
            break;
          }
        }
        sent++;
      }
      if (sent > 0) {
        await _store.write(
          pending.length > sent ? pending.sublist(sent) : <String>[],
        );
      }
    } on Object {
      // Best effort: the reports stay for the next flush.
    }
  }

  static ClientErrorReportDto? _decode(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return ClientErrorReportDto.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  static String? _cap(String? text, int max) {
    if (text == null || text.trim().isEmpty) return null;
    return text.length > max ? text.substring(0, max) : text;
  }

  static Future<String?> _noInstallId() async => null;

  static Future<DeviceSummary> _readDeviceSummary() async {
    try {
      final DeviceInfoPlugin plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final WebBrowserInfo info = await plugin.webBrowserInfo;
        return DeviceSummary(os: 'web', browser: info.browserName.name);
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final IosDeviceInfo info = await plugin.iosInfo;
        return DeviceSummary(
          device: info.utsname.machine,
          os: 'iOS ${info.systemVersion}',
        );
      }
      final AndroidDeviceInfo info = await plugin.androidInfo;
      final String maker = info.manufacturer;
      final String model = info.model;
      return DeviceSummary(
        device: model.toLowerCase().startsWith(maker.toLowerCase())
            ? model
            : '$maker $model',
        os: 'Android ${info.version.release}',
      );
    } on Object {
      return const DeviceSummary();
    }
  }
}

/// Makes [reporter] the app's error sink: Flutter framework errors (each
/// previous handler, Sentry's included, still runs), uncaught asynchronous
/// errors, and, in release builds, the box shown in place of a widget that
/// failed to build -- an Arabic line with the problem code instead of a
/// grey area. Sends whatever an earlier run left waiting.
void installErrorReporting(ClientErrorReporter reporter) {
  ClientErrorReporter.instance = reporter;

  final FlutterExceptionHandler? previousFlutter = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (!details.silent) {
      reporter.reportException(
        details.exception,
        details.stack,
        where: details.context?.toDescription(),
        fatal: true,
      );
    }
    previousFlutter?.call(details);
  };

  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final previousPlatform = dispatcher.onError;
  dispatcher.onError = (Object error, StackTrace stack) {
    reporter.reportException(error, stack);
    return previousPlatform?.call(error, stack) ?? false;
  };

  if (kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) => BrokenPartNotice(
      code: reporter.codeFor(details.exception, details.stack),
    );
  }

  unawaited(reporter.flush());
}

/// What a player sees where a part of the screen failed to build (release
/// builds): no stack, the problem code to send to the admins.
class BrokenPartNotice extends StatelessWidget {
  /// Creates the notice.
  const BrokenPartNotice({super.key, required this.code});

  /// The problem code.
  final String code;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      'تعذّر عرض هذا الجزء.\n${ErrorPresenter.problemCodeLabel} $code',
      key: const Key('error.brokenPart'),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      style: const TextStyle(
        fontSize: AppFontSize.s13,
        color: Color(0xFF9E9E9E),
      ),
    ),
  );
}
