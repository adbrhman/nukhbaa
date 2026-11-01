import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of the players' names on every board
/// ([ParticipantReader.findDisplayNames]), held per participant until a
/// rename drops it.
///
/// Every board, the predictions table and the live line asked the database
/// for the names of everyone on it, each time it was opened: 10114 reads of
/// about 111 names each between 25 October and 1 November 2026, with no
/// cache at all, while the Supabase egress quota was exceeded (script 192).
/// A name changes only through this server -- `UpdateDisplayName`,
/// `AdminRenameUser` and the account deletion all go through
/// `CachedUserDirectory`, which calls [forgetNames] -- so each name is read
/// once and held; [ttl] only bounds an edit made outside this server (the
/// SQL Editor). A participant without a name (a deleted account) is held
/// too, as absent. A batch reads only the participants not held; concurrent
/// reads of the same batch share one query ([ReadCoalescer]). Failures are
/// never cached.
///
/// [findParticipantById] and [findAvatarRefs] pass straight through.
final class CachedParticipantReader implements ParticipantReader {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedParticipantReader(
    this._inner, {
    Duration ttl = const Duration(hours: 6),
    int maxEntries = 8192,
    DateTime Function() now = DateTime.now,
  }) : _names = TtlCache<String, _Name>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final ParticipantReader _inner;

  /// One entry per participant id, in lower case (the database's form).
  final TtlCache<String, _Name> _names;
  final ReadCoalescer<String, Result<Map<String, String>>> _loads =
      ReadCoalescer<String, Result<Map<String, String>>>();

  /// Drops every held name: a player was renamed or deleted.
  void forgetNames() => _names.clear();

  @override
  Future<Result<Map<String, String>>> findDisplayNames(
    List<ParticipantId> ids,
  ) async {
    if (ids.isEmpty) {
      return _inner.findDisplayNames(ids);
    }
    final Map<String, String> found = <String, String>{};
    final Map<String, ParticipantId> missing = <String, ParticipantId>{};
    for (final ParticipantId id in ids) {
      final String key = id.value.toLowerCase();
      if (missing.containsKey(key)) {
        continue;
      }
      final _Name? held = _names.read(key);
      if (held == null) {
        missing[key] = id;
      } else if (held.name case final String name) {
        found[key] = name;
      }
    }
    if (missing.isNotEmpty) {
      final List<String> keys = missing.keys.toList()..sort();
      final int startedAt = _names.generation;
      final Result<Map<String, String>> loaded = await _loads.run(
        '$startedAt|${keys.join(',')}',
        () async {
          final Result<Map<String, String>> read = await _inner
              .findDisplayNames(<ParticipantId>[
                for (final String key in keys) missing[key]!,
              ]);
          if (read case Ok<Map<String, String>>(:final value)) {
            final Map<String, String> byKey = <String, String>{
              for (final MapEntry<String, String> entry in value.entries)
                entry.key.toLowerCase(): entry.value,
            };
            for (final String key in keys) {
              _names.write(key, _Name(byKey[key]), startedAt: startedAt);
            }
          }
          return read;
        },
      );
      if (loaded case Err<Map<String, String>>(:final error)) {
        return Result.err(error);
      }
      for (final MapEntry<String, String> entry
          in (loaded as Ok<Map<String, String>>).value.entries) {
        found[entry.key.toLowerCase()] = entry.value;
      }
    }
    return Result.ok(found);
  }

  @override
  Future<Result<Participant?>> findParticipantById(ParticipantId id) =>
      _inner.findParticipantById(id);

  @override
  Future<Result<Map<String, ParticipantAvatarRef>>> findAvatarRefs(
    List<ParticipantId> ids,
  ) => _inner.findAvatarRefs(ids);
}

/// A held name, so "no name" (`null`, a deleted account) is held as well.
final class _Name {
  const _Name(this.name);

  final String? name;
}
