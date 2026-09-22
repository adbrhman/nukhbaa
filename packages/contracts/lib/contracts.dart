/// Versioned API contracts (DTOs) shared between the Flutter client and the
/// backend (Application ADR, Section 3; API ADR, Section 4).
///
/// This package depends on nothing so both sides compile against identical
/// shapes. Every DTO carries a schema version to support gradual rollout and
/// archived-event replay (Database ADR, Section 12).
library;

export 'src/admin_dto.dart';
export 'src/announcement_dto.dart';
export 'src/admin_user_prediction_dto.dart';
export 'src/auth_dto.dart';
export 'src/badge_dto.dart';
export 'src/competition_dto.dart';
export 'src/daily_challenge_dto.dart';
export 'src/device_token_dto.dart';
export 'src/streak_dto.dart';
export 'src/time_zone_dto.dart';
export 'src/error_dto.dart';
export 'src/favorite_teams_dto.dart';
export 'src/insights_dto.dart';
export 'src/push_opened_dto.dart';
export 'src/fixture_ledger_dto.dart';
export 'src/fixture_prediction_dto.dart';
export 'src/fixture_schedule_dto.dart';
export 'src/fixture_social_dto.dart';
export 'src/football_data_dto.dart';
export 'src/group_dto.dart';
export 'src/health_dto.dart';
export 'src/latest_build_dto.dart';
export 'src/leaderboard_dto.dart';
export 'src/ledger_dto.dart';
export 'src/me_dto.dart';
export 'src/notification_dto.dart';
export 'src/notification_preferences_dto.dart';
export 'src/participant_fixture_score_dto.dart';
export 'src/prediction_dto.dart';
export 'src/scoring_dto.dart';
export 'src/social_dto.dart';
export 'src/weekly_league_dto.dart';
