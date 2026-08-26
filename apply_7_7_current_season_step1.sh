#!/usr/bin/env bash
# 7.7 (ترقيم جديد) — "current monthly season": الخطوة 1+2 فقط (Domain + Application read)
# لا DB migration، لا server route، لا mobile — هذه دفعة واحدة قابلة للتحقق والrollback.
# القرار المعتمد: عند عدم وجود Season يغطي "الآن" → current = null (لا موسم نشط).
#
# شغّله من جذر الريبو (نفس مستوى pubspec.yaml / apps / packages).
set -euo pipefail

if [ ! -d "packages/domain" ] || [ ! -d "packages/application" ]; then
  echo "خطأ: شغّل السكربت من جذر الريبو (لا يوجد packages/domain أو packages/application هنا)." >&2
  exit 1
fi

BACKUP_DIR=".step-7-7-current-season-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

FILES_TO_EDIT=(
  "packages/domain/lib/src/competition/competition_season.dart"
  "packages/domain/test/competition/competition_season_test.dart"
  "packages/application/lib/src/competition/ports/competition_repository.dart"
  "packages/application/lib/application.dart"
  "packages/application/test/competition/fake_competition_repository.dart"
  "packages/infrastructure/lib/src/competition/postgres_competition_repository.dart"
  "packages/infrastructure/test/competition/postgres_competition_repository_test.dart"
)

for f in "${FILES_TO_EDIT[@]}"; do
  if [ ! -f "$f" ]; then
    echo "خطأ: الملف غير موجود: $f — الحالة على الجهاز مختلفة عمّا فُحص. توقف بلا أي تعديل." >&2
    exit 1
  fi
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done

echo "== نسخة احتياطية في: $BACKUP_DIR =="

python3 - "$BACKUP_DIR" <<'PYEOF'
import sys, pathlib

def apply(path, old, new, label):
    p = pathlib.Path(path)
    text = p.read_text(encoding="utf-8")
    if text.count(old) != 1:
        print(f"فشل: '{label}' في {path} — المطابقة ليست فريدة (found={text.count(old)}). توقف.", file=sys.stderr)
        sys.exit(1)
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"تم: {label} -> {path}")

# --- 1) Domain: CompetitionSeason.isCurrentAt --------------------------------
apply(
    "packages/domain/lib/src/competition/competition_season.dart",
    """  static const int _maxLabelLength = 60;

  final SeasonId id;
  final CompetitionId competitionId;
  final String label;
  final DateTime startAt;
  final DateTime endAt;

  @override
  bool operator ==(Object other) =>""",
    """  static const int _maxLabelLength = 60;

  final SeasonId id;
  final CompetitionId competitionId;
  final String label;
  final DateTime startAt;
  final DateTime endAt;

  /// Whether [nowUtc] falls inside this season's window — [startAt]
  /// inclusive, [endAt] exclusive.
  ///
  /// Computed, never stored (the same "no lifecycle field" principle as
  /// `FixtureLock`, docs/project-context.md): the domain carries no
  /// `status`/`isActive` flag, so "the current season" is always a fresh
  /// comparison against "now", not a persisted state that can drift out of
  /// sync. Pure and total; the caller supplies an already-UTC instant (the
  /// `Clock` port's contract) -- this method does not itself validate
  /// `nowUtc.isUtc`.
  bool isCurrentAt(DateTime nowUtc) =>
      !nowUtc.isBefore(startAt) && nowUtc.isBefore(endAt);

  @override
  bool operator ==(Object other) =>""",
    "CompetitionSeason.isCurrentAt",
)

# --- 2) Domain test ------------------------------------------------------------
apply(
    "packages/domain/test/competition/competition_season_test.dart",
    """              .value;
      expect(a, isNot(b));
    });
  });
}""",
    """              .value;
      expect(a, isNot(b));
    });
  });

  group('CompetitionSeason.isCurrentAt', () {
    CompetitionSeason season() =>
        (CompetitionSeason.create(
                  id: const SeasonId(_seasonId),
                  competitionId: const CompetitionId(_competitionId),
                  label: 'x',
                  startAt: _start,
                  endAt: _end,
                )
                as Ok<CompetitionSeason>)
            .value;

    test('true exactly at the start instant (inclusive)', () {
      expect(season().isCurrentAt(_start), isTrue);
    });

    test('true strictly between start and end', () {
      expect(season().isCurrentAt(_start.add(const Duration(days: 1))), isTrue);
    });

    test('false exactly at the end instant (exclusive)', () {
      expect(season().isCurrentAt(_end), isFalse);
    });

    test('false before the start instant', () {
      expect(
        season().isCurrentAt(_start.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('false after the end instant', () {
      expect(season().isCurrentAt(_end.add(const Duration(days: 1))), isFalse);
    });
  });
}""",
    "competition_season_test.dart: isCurrentAt group",
)

# --- 3) Application port: CompetitionRepository.findCurrentSeason -------------
apply(
    "packages/application/lib/src/competition/ports/competition_repository.dart",
    """  Future<Result<List<CompetitionSeason>>> listCompetitionSeasons(
    CompetitionId competitionId,
  );

  /// Lists the rounds of a season, ordered by their 1-based [Round.sequence].""",
    """  Future<Result<List<CompetitionSeason>>> listCompetitionSeasons(
    CompetitionId competitionId,
  );

  /// Finds the single-current-season resolution: the season of
  /// [competitionId] whose window contains [nowUtc] ([CompetitionSeason.
  /// isCurrentAt]), or `Ok(null)` when no season currently covers it (e.g. a
  /// new month has begun and the admin has not yet created its season -- a
  /// legitimate operational gap, not an error).
  ///
  /// There is currently no database constraint preventing two seasons of the
  /// same competition from overlapping (a known gap -- a candidate exclusion
  /// constraint has not been added yet). If more than one season matches,
  /// implementations MUST resolve the tie deterministically by the earliest
  /// [CompetitionSeason.startAt] (then id), so behaviour is stable in the
  /// interim rather than implementation-order-dependent.
  Future<Result<CompetitionSeason?>> findCurrentSeason({
    required CompetitionId competitionId,
    required DateTime nowUtc,
  });

  /// Lists the rounds of a season, ordered by their 1-based [Round.sequence].""",
    "CompetitionRepository.findCurrentSeason (port)",
)

# --- 4) application.dart export -------------------------------------------------
apply(
    "packages/application/lib/application.dart",
    """export 'src/competition/get_competition.dart';
export 'src/competition/get_round.dart';""",
    """export 'src/competition/get_competition.dart';
export 'src/competition/get_current_season.dart';
export 'src/competition/get_round.dart';""",
    "application.dart export",
)

# --- 5) FakeCompetitionRepository.findCurrentSeason ------------------------------
apply(
    "packages/application/test/competition/fake_competition_repository.dart",
    """  @override
  Future<Result<List<Round>>> listSeasonRounds(SeasonId seasonId) async {""",
    """  @override
  Future<Result<CompetitionSeason?>> findCurrentSeason({
    required CompetitionId competitionId,
    required DateTime nowUtc,
  }) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    // Every season of this competition whose window covers `nowUtc`
    // (mirrors the adapter's `start_at <= now AND end_at > now`), tie-broken
    // deterministically by earliest `startAt` then id -- matches the port's
    // documented tie-break for the (currently unconstrained) overlap gap.
    final matches =
        [
          for (final s in _seasons.values)
            if (s.competitionId.value == competitionId.value &&
                s.isCurrentAt(nowUtc))
              s,
        ]..sort((a, b) {
          final byStart = a.startAt.compareTo(b.startAt);
          return byStart != 0 ? byStart : a.id.value.compareTo(b.id.value);
        });
    return Result.ok(matches.isEmpty ? null : matches.first);
  }

  @override
  Future<Result<List<Round>>> listSeasonRounds(SeasonId seasonId) async {""",
    "FakeCompetitionRepository.findCurrentSeason",
)

# --- 6) PostgresCompetitionRepository.findCurrentSeason --------------------------
apply(
    "packages/infrastructure/lib/src/competition/postgres_competition_repository.dart",
    """  Result<CompetitionSeason> _mapSeason(Map<String, dynamic> row) {""",
    """  // Single-current-season resolution (docs/project-context.md, "computed,
  // never stored" -- the same principle as `FixtureLock`): the season whose
  // `[start_at, end_at)` window covers `@now`. No `status`/`isActive` column
  // exists or is needed. There is currently no exclusion constraint
  // preventing two seasons of the same competition from overlapping (a known
  // gap); until it lands, `ORDER BY start_at ASC, id ASC LIMIT 1` resolves any
  // overlap deterministically, matching the port's documented tie-break. A
  // month with no season yet -- the query simply returns no row -- is
  // `Ok(null)`, never `not_found` (mirrors `findParticipant`'s legitimate-
  // absence read).
  static const String _findCurrentSeasonSql = \'\'\'
SELECT id, competition_id, label, start_at, end_at
FROM competition.seasons
WHERE competition_id = @competition_id
  AND start_at <= @now
  AND end_at > @now
ORDER BY start_at ASC, id ASC
LIMIT 1
\'\'\';

  @override
  Future<Result<CompetitionSeason?>> findCurrentSeason({
    required CompetitionId competitionId,
    required DateTime nowUtc,
  }) async {
    final result = await _connection.query(
      _findCurrentSeasonSql,
      parameters: {'competition_id': competitionId.value, 'now': nowUtc},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapSeason(value.first),
    };
  }

  Result<CompetitionSeason> _mapSeason(Map<String, dynamic> row) {""",
    "PostgresCompetitionRepository.findCurrentSeason",
)

# --- 7) Postgres repository unit test -------------------------------------------
apply(
    "packages/infrastructure/test/competition/postgres_competition_repository_test.dart",
    """      final err = (await repo.findSeason(_sId) as Err<CompetitionSeason>).error;
      expect(err.kind, ErrorKind.invariant);
      expect(err.code, 'competition.season_not_found');
    });
  });

  group('findRound', () {""",
    """      final err = (await repo.findSeason(_sId) as Err<CompetitionSeason>).error;
      expect(err.kind, ErrorKind.invariant);
      expect(err.code, 'competition.season_not_found');
    });
  });

  group('findCurrentSeason', () {
    test('maps the matching row and binds competition_id + now', () async {
      final connection = _rows([
        {
          'id': _seasonId,
          'competition_id': _competitionId,
          'label': '08/2026',
          'start_at': DateTime.utc(2026, 8, 1),
          'end_at': DateTime.utc(2026, 9, 1),
        },
      ]);
      final repo = PostgresCompetitionRepository(connection);
      final now = DateTime.utc(2026, 8, 15);

      final season =
          (await repo.findCurrentSeason(competitionId: _cId, nowUtc: now)
                  as Ok<CompetitionSeason?>)
              .value;

      expect(season?.id.value, _seasonId);
      expect(connection.lastParameters, {
        'competition_id': _competitionId,
        'now': now,
      });
    });

    test(
      'an empty result is a legitimate Ok(null) -- no active season now',
      () async {
        final repo = PostgresCompetitionRepository(_rows(const []));

        final result = await repo.findCurrentSeason(
          competitionId: _cId,
          nowUtc: DateTime.utc(2026, 8, 15),
        );

        expect(result, isA<Ok<CompetitionSeason?>>());
        expect((result as Ok<CompetitionSeason?>).value, isNull);
      },
    );

    test('a transient query failure is propagated unchanged', () async {
      final repo = PostgresCompetitionRepository(_fails());

      final err =
          (await repo.findCurrentSeason(
                competitionId: _cId,
                nowUtc: DateTime.utc(2026, 8, 15),
              )
                  as Err<CompetitionSeason?>)
              .error;

      expect(err.kind, ErrorKind.transient);
    });
  });

  group('findRound', () {""",
    "postgres_competition_repository_test.dart: findCurrentSeason group",
)

print("== كل الاستبدالات (7) نجحت ==")
PYEOF

# --- 8) ملفان جديدان (creation، لا استبدال) --------------------------------------
cat > "packages/application/lib/src/competition/get_current_season.dart" <<'DARTEOF'
import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: resolve the single "current" monthly season of a
/// competition (Application ADR, Section 2: query separated from command).
///
/// The domain carries no `status`/`isActive` field on [CompetitionSeason] --
/// "current" is always computed fresh against "now" via [Clock] and
/// [CompetitionSeason.isCurrentAt], the same "computed, never stored"
/// principle `FixtureLock` already establishes for fixture locking
/// (docs/project-context.md). There is no persisted "current season" state
/// to drift out of sync.
///
/// A month with no season yet created by the admin -- an operational gap
/// between months -- is a legitimate `Ok(null)`, never an error: the caller
/// (e.g. the client's home screen) is expected to render an explicit empty
/// state for "no active season right now", not treat it as a fault.
///
/// The caller must be an authenticated user (`PlatformRole.user`, matching
/// every other client-facing read).
///
/// Never throws; returns a typed [Result].
final class GetCurrentSeason {
  /// Creates the use-case over its collaborators.
  const GetCurrentSeason({
    required CompetitionRepository repository,
    required Clock clock,
  }) : _competition = repository,
       _clock = clock;

  final CompetitionRepository _competition;
  final Clock _clock;

  /// Resolves the current season of [competitionId], visible to [principal].
  Future<Result<CompetitionSeason?>> call({
    required AuthenticatedUser principal,
    required String competitionId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final idResult = CompetitionId.tryParse(competitionId);
    if (idResult is Err<CompetitionId>) {
      return Result.err(idResult.error);
    }

    return _competition.findCurrentSeason(
      competitionId: (idResult as Ok<CompetitionId>).value,
      nowUtc: _clock.nowUtc(),
    );
  }
}
DARTEOF
echo "تم إنشاء: packages/application/lib/src/competition/get_current_season.dart"

cat > "packages/application/test/competition/get_current_season_test.dart" <<'DARTEOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _competition = '22222222-2222-2222-2222-222222222222';
const _otherCompetition = '99999999-9999-9999-9999-999999999999';
const _seasonAug = '55555555-5555-5555-5555-555555555555';
const _seasonSep = '66666666-6666-6666-6666-666666666666';

final _now = DateTime.utc(2026, 8, 15);

CompetitionSeason _season({
  required String id,
  required String competitionId,
  required DateTime startAt,
  required DateTime endAt,
}) => CompetitionSeason.fromStored(
  id: SeasonId(id),
  competitionId: CompetitionId(competitionId),
  label: 'x',
  startAt: startAt,
  endAt: endAt,
);

void main() {
  late FakeCompetitionRepository repo;
  late GetCurrentSeason useCase;

  setUp(() {
    repo = FakeCompetitionRepository();
    useCase = GetCurrentSeason(repository: repo, clock: FixedClock(_now));
  });

  test('resolves the season whose window covers "now"', () async {
    repo.seedSeason(
      _season(
        id: _seasonAug,
        competitionId: _competition,
        startAt: DateTime.utc(2026, 8),
        endAt: DateTime.utc(2026, 9),
      ),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      competitionId: _competition,
    );

    final season = (r as Ok<CompetitionSeason?>).value;
    expect(season?.id.value, _seasonAug);
  });

  test(
    'a month with no season yet is a legitimate Ok(null), not an error',
    () async {
      // Only a future season exists; "now" falls in the gap before it.
      repo.seedSeason(
        _season(
          id: _seasonSep,
          competitionId: _competition,
          startAt: DateTime.utc(2026, 9),
          endAt: DateTime.utc(2026, 10),
        ),
      );

      final r = await useCase.call(
        principal: userPrincipal(_user),
        competitionId: _competition,
      );

      expect(r, isA<Ok<CompetitionSeason?>>());
      expect((r as Ok<CompetitionSeason?>).value, isNull);
    },
  );

  test('only the requested competition\'s seasons are considered', () async {
    repo.seedSeason(
      _season(
        id: _seasonAug,
        competitionId: _otherCompetition,
        startAt: DateTime.utc(2026, 8),
        endAt: DateTime.utc(2026, 9),
      ),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      competitionId: _competition,
    );

    expect((r as Ok<CompetitionSeason?>).value, isNull);
  });

  test('an overlap between two seasons resolves to the earliest startAt', () {
    // Documents the port's tie-break for the known (unconstrained) overlap
    // gap -- exercised directly against the fake to pin the contract.
    repo.seedSeason(
      _season(
        id: _seasonSep,
        competitionId: _competition,
        startAt: DateTime.utc(2026, 8, 10),
        endAt: DateTime.utc(2026, 9, 10),
      ),
    );
    repo.seedSeason(
      _season(
        id: _seasonAug,
        competitionId: _competition,
        startAt: DateTime.utc(2026, 8),
        endAt: DateTime.utc(2026, 9),
      ),
    );

    expect(
      repo
          .findCurrentSeason(
            competitionId: const CompetitionId(_competition),
            nowUtc: _now,
          )
          .then((r) => (r as Ok<CompetitionSeason?>).value?.id.value),
      completion(_seasonAug),
    );
  });

  test('a malformed competition id is a validation error', () async {
    final r = await useCase.call(
      principal: userPrincipal(_user),
      competitionId: 'not-a-uuid',
    );

    expect((r as Err<CompetitionSeason?>).error.kind, ErrorKind.validation);
  });

  test('a transient repository failure is propagated unchanged', () async {
    repo.failNextWith(
      const AppError.transient('db.unavailable', 'connection reset'),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      competitionId: _competition,
    );

    final err = (r as Err<CompetitionSeason?>).error;
    expect(err.kind, ErrorKind.transient);
    expect(err.code, 'db.unavailable');
  });
}
DARTEOF
echo "تم إنشاء: packages/application/test/competition/get_current_season_test.dart"

echo ""
echo "== التنسيق (الملفات المعدَّلة/الجديدة فقط) =="
dart format \
  packages/domain/lib/src/competition/competition_season.dart \
  packages/domain/test/competition/competition_season_test.dart \
  packages/application/lib/src/competition/ports/competition_repository.dart \
  packages/application/lib/src/competition/get_current_season.dart \
  packages/application/lib/application.dart \
  packages/application/test/competition/fake_competition_repository.dart \
  packages/application/test/competition/get_current_season_test.dart \
  packages/infrastructure/lib/src/competition/postgres_competition_repository.dart \
  packages/infrastructure/test/competition/postgres_competition_repository_test.dart

echo ""
echo "== dart analyze (workspace كامل، كما في CI) =="
dart analyze --fatal-warnings .

echo ""
echo "== الاختبارات (dart test — الحزم غير Flutter، كما في melos.scripts.test) =="
( cd packages/domain && dart test )
( cd packages/application && dart test )
# ملف الوحدة فقط، وليس المجلد كاملاً — لتفادي postgres_competition_repository_integration_test.dart
# (موسومة @Tags(['integration'])، تتطلب قاعدة بيانات حية ولا تُشغَّل هنا).
( cd packages/infrastructure && dart test test/competition/postgres_competition_repository_test.dart )

echo ""
echo "== git diff --stat =="
git diff --stat

echo ""
echo "تم بنجاح. لا commit تلقائي — راجع git diff ثم نفّذ الـcommit يدويًا إذا كانت النتائج نظيفة."
echo "نسخة احتياطية محفوظة في: $BACKUP_DIR (احذفها يدويًا متى شئت)."
