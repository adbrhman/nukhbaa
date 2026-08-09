#!/usr/bin/env python3
"""
تراجع كامل عن التعديل السابق (auto-retry GET في ApiTransport).

السبب: كسر عقدًا مصممًا عمدًا وموثقًا بالاختبارات — عند فشل أول طلب GET
يجب أن تظهر الشاشة رسالة خطأ مع زر "إعادة محاولة" يدوي فورًا (نمط
retry-affordance)، لا أن تُمتَص المحاولة الأولى صامتة داخل طبقة النقل.
5 اختبارات فشلت في CI بسبب هذا (competition_browse_widgets_test.dart
وما شابهها عبر شاشات أخرى تتبع نفس النمط).

يعيد packages/api_client/lib/src/api_transport.dart لحالته الأصلية
(محاولة واحدة فقط لكل طلب، بلا إعادة محاولة تلقائية).

طريقة التشغيل:
  ضعه في أي مكان داخل مستودع نُخبة ثم:
    python3 revert_api_transport_get_retry.py
  يكتشف جذر المستودع تلقائياً. idempotent.
"""

import sys
from pathlib import Path

REL_PATH = Path("packages/api_client/lib/src/api_transport.dart")

CURRENT_WITH_RETRY = """  /// Retry budget for idempotent (`GET`) requests only: up to this many
  /// *extra* attempts beyond the first, spaced by [_retryDelays]. `POST`/`PUT`
  /// are never retried here — an automatic retry of a non-idempotent call
  /// risks a duplicate submission, which is strictly worse than surfacing
  /// the error and letting the caller (a human, via the retry button) decide.
  static const _retryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 2),
  ];

  /// The shared request pipeline. Builds the request, applies auth headers,
  /// executes it, and dispatches the response. Never throws: a transport
  /// exception becomes a transient [Result.err]; a non-2xx becomes a decoded
  /// [Result.err]; a 2xx with an undecodable body becomes a malformed-response
  /// [Result.err].
  ///
  /// `GET` requests get up to [_retryDelays.length] automatic retries (with
  /// backoff) when the failure is a timeout or a network exception — the
  /// symptom of a free-tier host cold-starting mid-request, not a real
  /// outage. Any other failure (a decoded non-2xx, a malformed body) is
  /// returned immediately without retrying, since retrying it would not
  /// change the outcome.
  Future<Result<T>> _send<T>({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? requestBody,
    required Result<T> Function(String body) decode,
  }) async {
    final uri = _resolve(path, query);
    final attempts = method == 'GET' ? _retryDelays.length + 1 : 1;

    for (var attempt = 0; attempt < attempts; attempt++) {
      final http.Response response;
      try {
        final headers = await _headers(hasBody: requestBody != null);
        final pending = switch (method) {
          'GET' => _httpClient.get(uri, headers: headers),
          'POST' => _httpClient.post(
            uri,
            headers: headers,
            body: jsonEncode(requestBody),
          ),
          'PUT' => _httpClient.put(
            uri,
            headers: headers,
            body: jsonEncode(requestBody),
          ),
          _ => throw ArgumentError.value(method, 'method', 'unsupported'),
        };
        final timeout = _requestTimeout;
        response = timeout == null
            ? await pending
            : await pending.timeout(timeout);
      } on TimeoutException catch (cause) {
        // The request's `.timeout(_requestTimeout)` elapsed with no
        // response — distinguished from other transport failures so the UI
        // can tell the user the server didn't answer in time (vs. being
        // unreachable). Retryable for `GET` (see [_retryDelays]).
        if (attempt < attempts - 1) {
          await Future<void>.delayed(_retryDelays[attempt]);
          continue;
        }
        return Result.err(timeoutError(cause));
      } on Object catch (cause) {
        // DNS failure, socket reset, closed client, etc. — never reached
        // the server (or never got a response): a transient, retryable
        // failure. Retryable for `GET` (see [_retryDelays]).
        if (attempt < attempts - 1) {
          await Future<void>.delayed(_retryDelays[attempt]);
          continue;
        }
        return Result.err(networkError(cause));
      }

      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return decode(response.body);
      }
      if (status == 401) {
        await _onUnauthorized?.call();
      }
      // A decoded (non-2xx) response is a real answer from the server, not
      // a cold-start symptom — return it as-is rather than retrying.
      return Result.err(decodeError(status, response.body));
    }
    // Unreachable: the loop always returns on its last iteration.
    throw StateError('unreachable');
  }"""

ORIGINAL = """  /// The shared request pipeline. Builds the request, applies auth headers,
  /// executes it, and dispatches the response. Never throws: a transport
  /// exception becomes a transient [Result.err]; a non-2xx becomes a decoded
  /// [Result.err]; a 2xx with an undecodable body becomes a malformed-response
  /// [Result.err].
  Future<Result<T>> _send<T>({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? requestBody,
    required Result<T> Function(String body) decode,
  }) async {
    final uri = _resolve(path, query);

    final http.Response response;
    try {
      final headers = await _headers(hasBody: requestBody != null);
      final pending = switch (method) {
        'GET' => _httpClient.get(uri, headers: headers),
        'POST' => _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(requestBody),
        ),
        'PUT' => _httpClient.put(
          uri,
          headers: headers,
          body: jsonEncode(requestBody),
        ),
        _ => throw ArgumentError.value(method, 'method', 'unsupported'),
      };
      final timeout = _requestTimeout;
      response = timeout == null
          ? await pending
          : await pending.timeout(timeout);
    } on TimeoutException catch (cause) {
      // The request's `.timeout(_requestTimeout)` elapsed with no response —
      // distinguished from other transport failures so the UI can tell the
      // user the server didn't answer in time (vs. being unreachable).
      return Result.err(timeoutError(cause));
    } on Object catch (cause) {
      // DNS failure, socket reset, closed client, etc. — never reached the
      // server (or never got a response): a transient, retryable failure.
      return Result.err(networkError(cause));
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return decode(response.body);
    }
    if (status == 401) {
      await _onUnauthorized?.call();
    }
    return Result.err(decodeError(status, response.body));
  }"""


def find_repo_root(start: Path) -> Path | None:
    for candidate in [start, *start.parents]:
        if (candidate / "melos.yaml").exists():
            return candidate
        pubspec = candidate / "pubspec.yaml"
        if pubspec.exists() and (candidate / "apps" / "mobile").is_dir():
            try:
                content = pubspec.read_text(encoding="utf-8")
            except OSError:
                continue
            if any(
                line.rstrip() == "melos:" or line.startswith("melos:")
                for line in content.splitlines()
            ):
                return candidate
    return None


def main() -> int:
    if len(sys.argv) > 1:
        repo_root = Path(sys.argv[1]).expanduser().resolve()
    else:
        repo_root = find_repo_root(Path.cwd()) or find_repo_root(
            Path(__file__).resolve().parent
        )
        if repo_root is None:
            print("✗ تعذّر اكتشاف جذر المستودع. مرّر المسار صراحة كوسيط.")
            return 1

    target = repo_root / REL_PATH
    if not target.exists():
        print(f"✗ الملف غير موجود: {target}")
        return 1

    text = target.read_text(encoding="utf-8")

    if ORIGINAL in text and CURRENT_WITH_RETRY not in text:
        print(f"✓ الملف بالفعل على حالته الأصلية (بلا إعادة محاولة): {target}")
        return 0

    if CURRENT_WITH_RETRY not in text:
        print("✗ لم يتم العثور على كتلة إعادة المحاولة المتوقعة — الملف قد يكون تغيّر.")
        print(f"  المسار: {target}")
        return 1

    text = text.replace(CURRENT_WITH_RETRY, ORIGINAL, 1)
    target.write_text(text, encoding="utf-8")
    print(f"✓ تراجعت عن إعادة المحاولة: {target}")
    print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . و dart test packages/api_client apps/mobile")
    return 0


if __name__ == "__main__":
    sys.exit(main())
