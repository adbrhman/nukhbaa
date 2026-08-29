#!/usr/bin/env bash
set -euo pipefail
cd /home/dev/nukhbaa-backup-1787537565

python3 << 'PYEOF'
import sys

def replace_once(path, old, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    count = content.count(old)
    if count != 1:
        print(f"FAIL [{label}] في {path}: توقعت تطابقًا واحدًا، وجدت {count}", file=sys.stderr)
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK [{label}] -> {path}")

TRANSPORT = "packages/api_client/lib/src/api_transport.dart"

replace_once(
    TRANSPORT,
    "    return _send<T>(\n"
    "      method: 'GET',\n"
    "      path: path,\n"
    "      query: query,\n"
    "      decode: (body) => _decodeObject(body, parse),\n"
    "    );\n"
    "  }\n"
    "\n"
    "  /// Performs `GET [path]` (with optional [query]) and decodes a JSON **array**",
    "    return _send<T>(\n"
    "      method: 'GET',\n"
    "      path: path,\n"
    "      query: query,\n"
    "      decode: (body) => _decodeObject(body, parse),\n"
    "    );\n"
    "  }\n"
    "\n"
    "  /// Performs `GET [path]` (with optional [query]) and decodes a JSON body\n"
    "  /// that is either an **object** (via [parse]) or a literal JSON `null` —\n"
    "  /// for reads with no existence oracle where \"nothing yet\" is a legitimate\n"
    "  /// `Ok(null)` rather than a `404` (e.g.\n"
    "  /// `GET /competitions/{id}/seasons/current`, which returns `null` when no\n"
    "  /// season currently covers \"now\" — the same philosophy as [getList]\n"
    "  /// returning `[]`, not the \"owned resource\" philosophy of a `404`).\n"
    "  Future<Result<T?>> getNullableObject<T>(\n"
    "    String path, {\n"
    "    Map<String, String>? query,\n"
    "    required T Function(Map<String, Object?> json) parse,\n"
    "  }) {\n"
    "    return _send<T?>(\n"
    "      method: 'GET',\n"
    "      path: path,\n"
    "      query: query,\n"
    "      decode: (body) => _decodeNullableObject(body, parse),\n"
    "    );\n"
    "  }\n"
    "\n"
    "  /// Performs `GET [path]` (with optional [query]) and decodes a JSON **array**",
    "getNullableObject method",
)

replace_once(
    TRANSPORT,
    "      return Result.ok(parse(decoded.cast<String, Object?>()));\n"
    "    } on Object catch (cause) {\n"
    "      return Result.err(malformedResponse(cause));\n"
    "    }\n"
    "  }\n"
    "\n"
    "  static Result<List<T>> _decodeList<T>(",
    "      return Result.ok(parse(decoded.cast<String, Object?>()));\n"
    "    } on Object catch (cause) {\n"
    "      return Result.err(malformedResponse(cause));\n"
    "    }\n"
    "  }\n"
    "\n"
    "  static Result<T?> _decodeNullableObject<T>(\n"
    "    String body,\n"
    "    T Function(Map<String, Object?> json) parse,\n"
    "  ) {\n"
    "    try {\n"
    "      final decoded = jsonDecode(body);\n"
    "      if (decoded == null) return const Result.ok(null);\n"
    "      if (decoded is! Map) {\n"
    "        return Result.err(\n"
    "          malformedResponse(\n"
    "            'expected a JSON object or null, got ${decoded.runtimeType}',\n"
    "          ),\n"
    "        );\n"
    "      }\n"
    "      return Result.ok(parse(decoded.cast<String, Object?>()));\n"
    "    } on Object catch (cause) {\n"
    "      return Result.err(malformedResponse(cause));\n"
    "    }\n"
    "  }\n"
    "\n"
    "  static Result<List<T>> _decodeList<T>(",
    "_decodeNullableObject helper",
)

TEST = "packages/api_client/test/api_transport_test.dart"

replace_once(
    TEST,
    "    }, timeout: const Timeout(Duration(seconds: 5)));\n"
    "  });\n"
    "}\n",
    "    }, timeout: const Timeout(Duration(seconds: 5)));\n"
    "  });\n"
    "\n"
    "  group('getNullableObject', () {\n"
    "    test('decodes a JSON object body as Ok(value)', () async {\n"
    "      const dto = CompetitionDto(\n"
    "        id: 'c',\n"
    "        name: 'N',\n"
    "        format: 'football_scoreline',\n"
    "        visibility: 'public',\n"
    "      );\n"
    "      final ctx = buildTransport((_) async => okJson(dto.toJson()));\n"
    "\n"
    "      final result = await ctx.transport.getNullableObject<CompetitionDto>(\n"
    "        '/competitions/c',\n"
    "        parse: CompetitionDto.fromJson,\n"
    "      );\n"
    "\n"
    "      expect((result as Ok<CompetitionDto?>).value, dto);\n"
    "    });\n"
    "\n"
    "    test('decodes a literal JSON null body as Ok(null)', () async {\n"
    "      final ctx = buildTransport(\n"
    "        (_) async => http.Response(\n"
    "          'null',\n"
    "          200,\n"
    "          headers: const {'content-type': 'application/json'},\n"
    "        ),\n"
    "      );\n"
    "\n"
    "      final result = await ctx.transport.getNullableObject<CompetitionDto>(\n"
    "        '/competitions/c',\n"
    "        parse: CompetitionDto.fromJson,\n"
    "      );\n"
    "\n"
    "      expect((result as Ok<CompetitionDto?>).value, isNull);\n"
    "    });\n"
    "\n"
    "    test(\n"
    "      'a non-object, non-null body is a malformed-response error',\n"
    "      () async {\n"
    "        final ctx = buildTransport((_) async => okJson(<Object?>[1, 2]));\n"
    "\n"
    "        final result = await ctx.transport\n"
    "            .getNullableObject<CompetitionDto>(\n"
    "              '/competitions/c',\n"
    "              parse: CompetitionDto.fromJson,\n"
    "            );\n"
    "\n"
    "        final err = (result as Err<CompetitionDto?>).error;\n"
    "        expect(err.code, apiErrorMalformedResponse);\n"
    "      },\n"
    "    );\n"
    "  });\n"
    "}\n",
    "getNullableObject test group",
)

print("ALL PATCHES APPLIED")
PYEOF

echo "== flutter analyze packages/api_client =="
ANALYZE_OK=1
flutter analyze packages/api_client || ANALYZE_OK=0

echo "== flutter test packages/api_client =="
TEST_OK=1
flutter test packages/api_client || TEST_OK=0

if [ "$ANALYZE_OK" -eq 1 ] && [ "$TEST_OK" -eq 1 ]; then
  STATUS="نجح"
else
  STATUS="فشل"
fi

cat >> docs/checkpoints/session-log.md << EOF
- [$(date +%H:%M)] إصلاح: ApiTransport.getNullableObject<T> (يدعم استجابة GET بجسم JSON null حرفي، تمهيداً لعميل GetCurrentSeason) | ملف: packages/api_client/lib/src/api_transport.dart | اختبار: ${STATUS}
EOF

if [ "$ANALYZE_OK" -eq 1 ] && [ "$TEST_OK" -eq 1 ]; then
  git add -A
  git commit -m "fix: add ApiTransport.getNullableObject<T>"
  git log --oneline -1
else
  echo "!! توقف: analyze أو test فشل. راجع المخرجات أعلاه قبل أي commit — لم يُنفَّذ commit."
  exit 1
fi
