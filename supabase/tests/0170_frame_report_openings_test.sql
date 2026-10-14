-- Migration 0170: a frame report may say when its frozen frames happened
-- (the first 5 s after opening, after a return), both counts or neither,
-- never more than the frozen frames. Rolled back at the end.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8170-0000000000a1', 'a170@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0000-4000-8170-0000000000a1', 'a170@t.io', 'A170');

-- A report with both counts, and one from an app older than 0170.
insert into ops.frame_reports
  (user_id, build, platform, refresh_rate_hz, frames, slow_frames, frozen_frames, worst_frame_ms, frozen_at_start, frozen_at_resume)
values
  ('00000000-0000-4000-8170-0000000000a1', 'b170', 'web', 60, 1000, 40, 3, 1200, 2, 1),
  ('00000000-0000-4000-8170-0000000000a1', 'b170', 'web', 60, 1000, 40, 3, 1200, null, null);

do $$
declare
  refused int := 0;
begin
  if (select count(*) from ops.frame_reports
       where user_id = '00000000-0000-4000-8170-0000000000a1') <> 2 then
    raise exception 'FAILED: both sound reports must be kept';
  end if;
  raise notice 'ok - a report with both counts and one with neither are kept';

  begin
    insert into ops.frame_reports
      (user_id, build, platform, refresh_rate_hz, frames, slow_frames, frozen_frames, worst_frame_ms, frozen_at_start, frozen_at_resume)
    values ('00000000-0000-4000-8170-0000000000a1', 'b170', 'web', 60, 1000, 40, 3, 1200, 1, null);
  exception when check_violation then refused := refused + 1;
  end;
  begin
    insert into ops.frame_reports
      (user_id, build, platform, refresh_rate_hz, frames, slow_frames, frozen_frames, worst_frame_ms, frozen_at_start, frozen_at_resume)
    values ('00000000-0000-4000-8170-0000000000a1', 'b170', 'web', 60, 1000, 40, 3, 1200, 2, 2);
  exception when check_violation then refused := refused + 1;
  end;
  begin
    insert into ops.frame_reports
      (user_id, build, platform, refresh_rate_hz, frames, slow_frames, frozen_frames, worst_frame_ms, frozen_at_start, frozen_at_resume)
    values ('00000000-0000-4000-8170-0000000000a1', 'b170', 'web', 60, 1000, 40, 3, 1200, -1, 0);
  exception when check_violation then refused := refused + 1;
  end;
  if refused <> 3 then
    raise exception 'FAILED: % of 3 impossible reports refused', refused;
  end if;
  raise notice 'ok - one count without the other, more than the frozen frames, and a negative count are refused';

  if not exists (select 1 from ops.applied_migrations where version = '0170_frame_report_openings') then
    raise exception 'FAILED: 0170 must record itself in ops.applied_migrations';
  end if;
  raise notice 'ok - 0170 is recorded in ops.applied_migrations';
end $$;

rollback;
