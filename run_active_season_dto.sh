#!/usr/bin/env bash
set -uo pipefail
cd /home/dev/nukhbaa-backup-1787537565

# 1) إضافة ActiveSeasonDto إلى competition_dto.dart (نظير MatchFeedItemDto)
python3 - << 'PYEOF'
import sys
p = "packages/contracts/lib/src/competition_dto.dart"
s = open(p, encoding="utf-8").read()

if "class ActiveSeasonDto" in s:
    print("ActiveSeasonDto موجود مسبقًا — لا تعديل.")
    sys.exit(0)

anchor = (
    "      other.fixtureId == fixtureId &&\n"
    "      other.displayOrder == displayOrder &&\n"
    "      other.schemaVersion == schemaVersion;\n"
    "\n"
    "  @override\n"
    "  int get hashCode => Object.hash(fixtureId, displayOrder, schemaVersion);\n"
    "}\n"
)
if anchor not in s:
    print("خطأ: لم أجد نهاية LinkFixtureToRoundRequestDto كما هو متوقع", file=sys.stderr)
    sys.exit(1)

new_class = '''
/// One season the caller is an **active** participant in, right now, joined
/// with its owning competition's display facts (the wire shape of
/// `ParticipantSeasonFeedEntry` — `GET /me/active-seasons`). The client fans
/// out to the existing `SeasonFixtureDto`-backed `GET /seasons/{id}/fixtures`
/// read per season this returns; it never carries fixtures itself.
final class ActiveSeasonDto {
  /// Creates an active-season feed entry DTO.
  const ActiveSeasonDto({
    required this.competitionId,
    required this.competitionName,
    required this.seasonId,
    required this.seasonLabel,
    required this.startAt,
    required this.endAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads.
  factory ActiveSeasonDto.fromJson(Map<String, Object?> json) {
    return ActiveSeasonDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      competitionId: json['competition_id']! as String,
      competitionName: json['competition_name']! as String,
      seasonId: json['season_id']! as String,
      seasonLabel: json['season_label']! as String,
      startAt: json['start_at']! as String,
      endAt: json['end_at']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owning competition's id (UUID string).
  final String competitionId;

  /// The owning competition's display name.
  final String competitionName;

  /// The season's id (UUID string) -- the key the client uses to fetch its
  /// fixtures via `GET /seasons/{id}/fixtures`.
  final String seasonId;

  /// The season's display label.
  final String seasonLabel;

  /// The season's calendar window opening instant, as an ISO-8601 UTC string
  /// (inclusive).
  final String startAt;

  /// The season's calendar window closing instant, as an ISO-8601 UTC string
  /// (exclusive).
  final String endAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'competition_id': competitionId,
    'competition_name': competitionName,
    'season_id': seasonId,
    'season_label': seasonLabel,
    'start_at': startAt,
    'end_at': endAt,
  };

  @override
  bool operator ==(Object other) =>
      other is ActiveSeasonDto &&
      other.competitionId == competitionId &&
      other.competitionName == competitionName &&
      other.seasonId == seasonId &&
      other.seasonLabel == seasonLabel &&
      other.startAt == startAt &&
      other.endAt == endAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    competitionId,
    competitionName,
    seasonId,
    seasonLabel,
    startAt,
    endAt,
    schemaVersion,
  );
}
'''

s2 = s.replace(anchor, anchor + new_class, 1)
open(p, "w", encoding="utf-8").write(s2)
print("تمت إضافة ActiveSeasonDto.")
PYEOF
DTO_STATUS=$?

# 2) اختبار round-trip لـActiveSeasonDto في competition_dto_test.dart
python3 - << 'PYEOF'
import sys
p = "packages/contracts/test/competition_dto_test.dart"
s = open(p, encoding="utf-8").read()

if "group('ActiveSeasonDto'" in s:
    print("اختبار ActiveSeasonDto موجود مسبقًا — لا تعديل.")
    sys.exit(0)

anchor = (
    "        seasonId: '22222222-2222-2222-2222-222222222222',\n"
    "        fixtureId: '66666666-6666-6666-6666-666666666666',\n"
    "        displayOrder: 0,\n"
    "      );\n"
    "      final decoded = SeasonFixtureDto.fromJson(dto.toJson());\n"
    "      expect(decoded, dto);\n"
    "      expect(decoded.hashCode, dto.hashCode);\n"
    "    });\n"
    "  });\n"
    "}\n"
)
if anchor not in s:
    print("خطأ: لم أجد نهاية group('SeasonFixtureDto') كما هو متوقع", file=sys.stderr)
    sys.exit(1)

new_group = '''
  group('ActiveSeasonDto', () {
    test('round-trips through JSON', () {
      const dto = ActiveSeasonDto(
        competitionId: '11111111-1111-1111-1111-111111111111',
        competitionName: 'Premier Predictions',
        seasonId: '22222222-2222-2222-2222-222222222222',
        seasonLabel: 'August 2026',
        startAt: '2026-08-01T00:00:00.000Z',
        endAt: '2026-09-01T00:00:00.000Z',
      );
      final decoded = ActiveSeasonDto.fromJson(dto.toJson());
      expect(decoded, dto);
      expect(decoded.hashCode, dto.hashCode);
      expect(decoded.schemaVersion, ActiveSeasonDto.currentSchemaVersion);
    });

    test('defaults schema_version to 1 when absent (back-compat)', () {
      final decoded = ActiveSeasonDto.fromJson(const {
        'competition_id': 'c',
        'competition_name': 'n',
        'season_id': 's',
        'season_label': 'l',
        'start_at': '2026-08-01T00:00:00.000Z',
        'end_at': '2026-09-01T00:00:00.000Z',
      });
      expect(decoded.schemaVersion, 1);
    });

    test('toJson uses snake_case wire keys', () {
      const dto = ActiveSeasonDto(
        competitionId: 'c',
        competitionName: 'n',
        seasonId: 's',
        seasonLabel: 'l',
        startAt: '2026-08-01T00:00:00.000Z',
        endAt: '2026-09-01T00:00:00.000Z',
      );
      final json = dto.toJson();
      expect(
        json.keys,
        containsAll(const [
          'schema_version',
          'competition_id',
          'competition_name',
          'season_id',
          'season_label',
          'start_at',
          'end_at',
        ]),
      );
    });
  });
}
'''

s2 = s.replace(anchor, anchor[:-2] + new_group, 1)
open(p, "w", encoding="utf-8").write(s2)
print("تمت إضافة اختبار ActiveSeasonDto.")
PYEOF
TEST_FILE_STATUS=$?

# 3) بوابة تحقق: لا commit إلا بعد نجاح analyze وtest معًا
echo "== flutter analyze packages/contracts =="
flutter analyze packages/contracts
ANALYZE_STATUS=$?

echo "== flutter test packages/contracts =="
flutter test packages/contracts
TEST_STATUS=$?

if [ $DTO_STATUS -ne 0 ] || [ $TEST_FILE_STATUS -ne 0 ] || [ $ANALYZE_STATUS -ne 0 ] || [ $TEST_STATUS -ne 0 ]; then
  echo "فشل التحقق — لن يُنفَّذ أي commit. راجع المخرجات أعلاه."
  exit 1
fi

TS=$(date +%H:%M)
cat >> docs/checkpoints/session-log.md << EOF
- [$TS] إصلاح: ActiveSeasonDto + اختبارات (طبقة contracts) | ملف: packages/contracts/lib/src/competition_dto.dart | اختبار: نجح
EOF
git add -A
git commit -m "fix: add ActiveSeasonDto (contracts layer)"
git log --oneline -1
