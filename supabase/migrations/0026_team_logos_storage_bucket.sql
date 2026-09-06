-- ============================================================================
-- Migration 0026: team_logos_storage_bucket
--
-- Adds the `team-logos` Supabase Storage bucket that `football_data.teams`
-- .crest_url values will point at (that column has existed since migration
-- 0013 — no schema change needed there). Public-read: crests are shown to
-- every viewer of a fixture card, authenticated or not, the same way any
-- other public CDN asset would be — so the bucket itself is created
-- `public = true` (Supabase serves public-bucket objects over the
-- `/object/public/...` path with no auth check at all) and RLS policies
-- below are defense-in-depth for the `/object/authenticated/...` path plus
-- an explicit, everyone-denied policy for writes: uploads happen only via
-- the service-role key (server-side/admin tooling), which bypasses RLS
-- entirely, so no INSERT/UPDATE/DELETE policy needs to exist at all for
-- that to keep working — the deny-all policy below just documents that no
-- client, including an authenticated one, may write here directly.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('team-logos', 'team-logos', true)
on conflict (id) do update
  set public = excluded.public;

-- Everything below needs OWNERSHIP of storage.objects, which belongs to
-- supabase_storage_admin. The hosted project's `postgres` role reaches it;
-- the `postgres` of a local stack does not, and a clean-database rebuild
-- (`supabase db reset`, the CI migration gate) died here with SQLSTATE 42501
-- -- "must be owner of table objects".
--
-- Skipping in that case is safe and changes nothing observable: Supabase
-- enables RLS on storage.objects itself in both environments, `team-logos`
-- is a public bucket served over /object/public/... with no auth check, and
-- uploads use the service-role key, which bypasses RLS entirely. The two
-- policies are defense-in-depth for the /object/authenticated/... path and
-- already exist on the production database.
do $$
begin
  execute 'alter table storage.objects enable row level security';

  execute 'drop policy if exists team_logos_select_all on storage.objects';
  execute $p$
    create policy team_logos_select_all
      on storage.objects
      for select
      to anon, authenticated
      using (bucket_id = 'team-logos')
  $p$;

  execute 'drop policy if exists team_logos_no_client_writes on storage.objects';
  execute $p$
    create policy team_logos_no_client_writes
      on storage.objects
      for insert
      to anon, authenticated
      with check (bucket_id = 'team-logos' and false)
  $p$;
exception
  when insufficient_privilege then
    raise notice
      'storage.objects RLS/policies skipped: current role does not own the table';
end;
$$;
