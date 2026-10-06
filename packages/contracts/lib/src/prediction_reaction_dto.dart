/// The kinds a reaction to a prediction may be (migration 0094), in the
/// order the app offers them. The same closed set as group reactions.
const List<String> predictionReactionKinds = <String>[
  'like',
  'fire',
  'clap',
  'laugh',
  'sad',
  'shock',
];

/// The reactions one prediction received, as the viewer sees them.
final class PredictionReactionTallyDto {
  /// Creates the tally of [participantId]'s prediction.
  const PredictionReactionTallyDto({
    required this.participantId,
    required this.counts,
    this.mine,
  });

  /// Deserializes from a JSON map, tolerating missing keys; a count that is
  /// not an integer is left out.
  factory PredictionReactionTallyDto.fromJson(Map<String, Object?> json) {
    final Object? raw = json['counts'];
    return PredictionReactionTallyDto(
      participantId: (json['participant_id'] as String?) ?? '',
      counts: <String, int>{
        if (raw is Map<String, Object?>)
          for (final MapEntry<String, Object?> e in raw.entries)
            if (e.value is int) e.key: e.value as int,
      },
      mine: json['mine'] as String?,
    );
  }

  /// The participant whose prediction it is.
  final String participantId;

  /// Reaction kind to how many players gave it.
  final Map<String, int> counts;

  /// The kind the viewer gave, or null.
  final String? mine;

  /// Every reaction the prediction received.
  int get total => counts.values.fold(0, (int a, int b) => a + b);

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'participant_id': participantId,
    'counts': counts,
    if (mine != null) 'mine': mine,
  };
}

/// Body of `GET /seasons/{id}/fixtures/{fixtureId}/reactions`: one tally per
/// prediction that received any reaction.
final class PredictionReactionsDto {
  /// Creates the answer.
  const PredictionReactionsDto({
    required this.reactions,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory PredictionReactionsDto.fromJson(Map<String, Object?> json) {
    final Object? raw = json['reactions'];
    return PredictionReactionsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      reactions: <PredictionReactionTallyDto>[
        if (raw is List<Object?>)
          for (final Object? item in raw)
            if (item is Map<String, Object?>)
              PredictionReactionTallyDto.fromJson(item),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// One tally per reacted-to prediction.
  final List<PredictionReactionTallyDto> reactions;

  /// The schema version of this payload.
  final int schemaVersion;

  /// The tally of [participantId]'s prediction, or null when it has none.
  PredictionReactionTallyDto? of(String participantId) {
    for (final PredictionReactionTallyDto t in reactions) {
      if (t.participantId == participantId) return t;
    }
    return null;
  }

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'reactions': [for (final t in reactions) t.toJson()],
  };
}
