/// One event of a match on its details page (`GET /fixtures/{id}/details`,
/// script 118).
final class MatchEventDto {
  /// Creates the event.
  const MatchEventDto({
    required this.minute,
    required this.kind,
    required this.home,
    this.player,
    this.assist,
  });

  /// Deserializes from a JSON map.
  factory MatchEventDto.fromJson(Map<String, Object?> json) {
    return MatchEventDto(
      minute: json['minute'] as String? ?? '',
      kind: json['kind'] as String? ?? 'other',
      home: json['home'] == true,
      player: json['player'] as String?,
      assist: json['assist'] as String?,
    );
  }

  /// The clock as the provider writes it: `"14"`, `"45+4"`.
  final String minute;

  /// `goal`, `penalty_goal`, `own_goal`, `missed_penalty`, `yellow_card`,
  /// `second_yellow`, `red_card`, `var_goal_cancelled`, `substitution` or
  /// `other`; a client shows only the kinds it knows.
  final String kind;

  /// Whether it belongs to the home side.
  final bool home;

  /// The player it is about, when named.
  final String? player;

  /// The assisting player of a goal, when named.
  final String? assist;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'minute': minute,
    'kind': kind,
    'home': home,
    'player': player,
    'assist': assist,
  };
}

/// The story of a finished match for its details page
/// (`GET /fixtures/{id}/details`, script 118): its events with their
/// minutes, the half-time score and the ground. [available] is false while
/// it has not been read, or when the provider has no such match.
final class MatchDetailsDto {
  /// Creates the details.
  const MatchDetailsDto({
    required this.fixtureId,
    required this.available,
    this.events = const <MatchEventDto>[],
    this.halfTimeHome,
    this.halfTimeAway,
    this.venue,
    this.round,
    this.referee,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory MatchDetailsDto.fromJson(Map<String, Object?> json) {
    final Object? rawEvents = json['events'];
    return MatchDetailsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id']! as String,
      available: json['available'] == true,
      events: <MatchEventDto>[
        if (rawEvents is List<Object?>)
          for (final Object? raw in rawEvents)
            if (raw is Map<String, Object?>) MatchEventDto.fromJson(raw),
      ],
      halfTimeHome: json['half_time_home'] as int?,
      halfTimeAway: json['half_time_away'] as int?,
      venue: json['venue'] as String?,
      round: json['round'] as String?,
      referee: json['referee'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture.
  final String fixtureId;

  /// Whether there is anything to show.
  final bool available;

  /// The events, in the provider's order.
  final List<MatchEventDto> events;

  /// Home goals at half time, when known.
  final int? halfTimeHome;

  /// Away goals at half time, when known.
  final int? halfTimeAway;

  /// The ground.
  final String? venue;

  /// The round, as the provider names it.
  final String? round;

  /// The referee.
  final String? referee;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'available': available,
    'events': [for (final MatchEventDto event in events) event.toJson()],
    'half_time_home': halfTimeHome,
    'half_time_away': halfTimeAway,
    'venue': venue,
    'round': round,
    'referee': referee,
  };
}
