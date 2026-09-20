/// Environment variable that switches the in-process schedulers off.
const String schedulersEnvKey = 'NUKHBA_SCHEDULERS';

/// Whether the in-process schedulers (prediction reminders, monthly seasons,
/// provider sync, match-day settlement, weekly-league closure) should
/// start.
///
/// They are ON unless [schedulersEnvKey] is explicitly `off`, so a deployed
/// server that never sets it behaves exactly as before. The opt-out exists for
/// a local server pointed at a shared database: a second process running the
/// sweeps would race the deployed one (a no-op push sender still marks
/// reminders as sent), so a local run switches them off.
bool schedulersEnabled(Map<String, String> env) =>
    (env[schedulersEnvKey] ?? '').trim().toLowerCase() != 'off';
