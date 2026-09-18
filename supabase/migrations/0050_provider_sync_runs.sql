-- 0050: remember when a provider-sync job last completed.
--
-- The fixtures sync runs three minutes after every boot. A run of redeploys
-- therefore spent the whole Highlightly daily quota (100 requests) on
-- schedules, and the last rule in the list -- the Roshan League -- began
-- failing with football_data.provider_quota before any match was read.
--
-- One row per job, rewritten in place. Additive and safe to re-run.

create table if not exists football_data.sync_runs (
  job              text primary key,
  last_success_at  timestamptz not null,
  updated_at       timestamptz not null default now(),
  constraint sync_runs_job_not_blank check (btrim(job) <> '')
);

comment on table football_data.sync_runs is
  'When each provider-sync job last completed successfully. Read at boot so '
  'a redeploy does not repeat a sync that just ran, which protects the '
  'provider daily quota.';

alter table football_data.sync_runs enable row level security;
