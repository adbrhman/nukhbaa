-- ============================================================
-- Nukhba — Seed: Highlightly team identities (season 2026/27)
-- NOT a migration: production data, applied by hand like the other seeds
-- (CI's `supabase db reset --no-seed` never runs it).
--
-- Phase 1 of automatic fixtures/results (Premier League, Champions League,
-- Bundesliga, La Liga, Serie A, Roshan League, Europa League, and League Cup
-- ties between Premier League clubs). Every club the sync can meet is mapped
-- through football_data.external_identity_map with
-- external_source = 'highlightly' and external_id = the provider team id, so
-- the adapter resolves teams by id, never by name. Team ids come from the
-- provider's 2026 league tables (checked 2026-09-16).
--
-- 1. 121 existing catalog clubs are mapped. Neom is listed by the provider
--    under its former name "Al Suqoor".
-- 2. 20 clubs the catalog did not have (8 Champions League, 12 Europa League)
--    are created with Arabic names, crest null (the app shows initials), and
--    attached to the competition they were drawn for.
--
-- Additive and idempotent: existing rows are never changed; a re-run creates
-- nothing twice. The whole file rolls back if a mapped catalog id does not
-- exist or is already mapped to a different provider team.
--
-- Verification (expects 141):
--   select count(*) from football_data.external_identity_map
--    where external_source = 'highlightly' and canonical_table = 'team';
-- ============================================================

begin;

do $$
declare
  existing_map jsonb := '[
    ["36526","5884f1c8-cbd8-4909-bc96-0e4261a8a317"],
    ["56950","8972ad74-9345-4839-a154-994bcb9d16da"],
    ["30569","c9904a74-5a09-4015-b6aa-8b1c0dccea4f"],
    ["47589","f23ef620-b26b-46c0-869b-ce69eb9fc141"],
    ["44185","6f1b6ef1-8d6a-4d16-b5f8-6515b53e63a5"],
    ["42483","da47e915-9535-4737-af5c-21db390f4c2f"],
    ["1146230","4652cd18-5bd6-4809-a3af-88b5676d0d22"],
    ["45036","b10252ac-6726-4a04-a626-9cec0d180457"],
    ["39079","f7c1e97a-d3dc-4d81-b254-b110b6e7c4fe"],
    ["31420","ecc97649-e439-446d-bb6e-ca2ddb8ce333"],
    ["55248","004b84f6-709c-4053-ace9-c167b7ceebfe"],
    ["49291","c227d604-e0c6-4c86-a342-8685d1a7ef6f"],
    ["54397","f695e294-5caa-498e-bfd1-688154e63874"],
    ["34824","0b76e9e6-ca39-40f2-a3dd-9cbdc285dfb2"],
    ["43334","6af8332d-8845-4379-9fd6-b4889413b366"],
    ["28867","8a1e6ed6-32d6-4b92-a64e-a0a734a31849"],
    ["29718","1a6eea94-38be-4154-91f4-81df86e13ae7"],
    ["56099","11077309-b95e-4f73-bc01-3483bbaafa91"],
    ["635630","3b91d72e-5aa7-44bd-89f8-7b35895c7d07"],
    ["40781","baab75b9-fb68-4ec9-963d-5f1dd2d141fb"],
    ["142901","0aa9ad75-c407-4c23-9596-4ef283008e8c"],
    ["143752","e4dc3eea-99f5-4cca-b196-9fb88f9f4f38"],
    ["134391","9b6288b0-22d6-4c58-956e-fdabf8b2c1dc"],
    ["141199","d21c4796-b024-4d4f-884b-77f446c4e298"],
    ["139497","fb0100e9-3ee7-4106-b4b2-564c20077ce6"],
    ["144603","261265c5-7c63-4a1c-9bf5-17b54b7bc17f"],
    ["145454","2f32db94-b303-49ce-addb-8a5dbe57ee2e"],
    ["164176","45c084e2-32ac-4cb5-899c-b398f5e1bae1"],
    ["148858","e32f5ac7-ad4f-4380-bdf7-3996360f2c1a"],
    ["140348","868bdbbe-2328-495a-9063-304c560a13d2"],
    ["149709","30f2b747-5ad8-4cad-879a-3fc3ef256251"],
    ["148007","d02c2790-ae9a-4e3b-bc8c-0108da43444e"],
    ["136944","c4ebdb2d-7aba-4350-bd94-61f47c21d00a"],
    ["158219","83e0fbbe-8c10-4660-a16b-672e8bbc509f"],
    ["1413444","195c33c1-1fb0-4c12-9f4b-7053064799eb"],
    ["155666","76f4f0d6-8e9e-4340-a3cf-4c32f11673cc"],
    ["147156","2e24d869-9bf0-416b-ab37-7ba10cbb99aa"],
    ["138646","dc7850e9-9a0c-4bd5-8772-3fed05e6fd82"],
    ["462026","0f594504-f508-4a5f-9812-2b46db7ab8a9"],
    ["452665","735fb45d-45d9-4eb5-8b4e-7d0817ebaa44"],
    ["451814","e779275a-7ffc-47e7-937b-0bdec4020244"],
    ["450963","dd2d0363-e48a-4956-822e-cb6a0e73eede"],
    ["458622","3ea90068-55d6-49b8-9f62-bad3e7844cf0"],
    ["463728","86b220cd-8381-4b43-bd0a-905d7854fb9c"],
    ["679031","3f9839d8-dc33-4236-be29-cf07986baab7"],
    ["460324","0ff7fd21-63e4-42a7-8278-e7eb53daf506"],
    ["465430","0ef04bec-d041-4699-aaba-033ef1a53110"],
    ["459473","ce068bf4-4eb9-4cda-a317-70f6f9165371"],
    ["456069","0742bd4b-181e-4c6e-8d15-95563a525635"],
    ["619461","ed21b1b6-266d-4579-a4fa-9f5e26eb7e66"],
    ["3970699","d0465850-3820-4e01-a742-7c240c86510a"],
    ["620312","36f86a41-0572-4fba-8127-87ed1f88f229"],
    ["462877","dcdc310a-07fb-47c5-b3e9-489526c7432e"],
    ["461175","13cac3e8-d066-44d6-9990-a673afce675d"],
    ["467132","eaaded95-63ee-495c-8bf6-1a1f50048580"],
    ["456920","9b225262-d515-49e8-8f62-13679ef6cf1a"],
    ["453516","921abb80-473d-4cc4-b31c-632f1911e663"],
    ["454367","4d69f7c0-c253-475a-b7c4-99addb16f62c"],
    ["416923","28eb8979-79fd-4afe-9aa9-dd9fba5c7eea"],
    ["423731","63b93b6d-342b-40f6-b803-c52b1b4874bc"],
    ["425433","8005dd0f-b7a7-4309-82ba-70796d51abf9"],
    ["426284","ced1558b-6145-40a7-81bc-26f1d454e556"],
    ["417774","f11c2a60-4c98-4d43-8a8e-449ac0bda1e8"],
    ["762429","24e26598-a9af-4f9a-8d26-c043410f6600"],
    ["427986","7d66b79f-df3c-4935-81f7-d1e563db44e9"],
    ["436496","effe147a-c88c-4ec5-a878-3c0fbd25d3aa"],
    ["422029","d5ebc0ef-5544-40c3-b926-c1458cfc8cd3"],
    ["430539","bac11431-bf24-4471-8403-52528c4def2a"],
    ["422880","360348e5-3811-456b-9d75-3b740a574112"],
    ["415221","125ea161-7a36-43df-9f63-be1269285c26"],
    ["738601","a363cd91-615a-4209-a43b-d52c4e0598b7"],
    ["1344513","6127d5ea-7a63-40be-a059-5c2b7ff7721a"],
    ["419476","b96ec2b3-142f-48d9-bcd0-e06604a5575c"],
    ["445857","c7a41d04-e2b7-4a45-bb56-763d86cd80cc"],
    ["416072","d95f9b93-c8c9-4d83-bd4e-3af40b271e48"],
    ["428837","3fa73d98-5e9c-4479-aefd-e79b641eabb3"],
    ["421178","8647fd14-7f42-4aeb-bddc-9b64088ce5bd"],
    ["440751","6aec989c-b291-4257-99de-0f4ce3ad4d11"],
    ["2512085","cfc8e9a8-d3ca-446c-bc6c-810eee5bfbcb"],
    ["22754822","1db63a9f-a83e-4ecc-ad59-2d9e8705e2f8"],
    ["2492512","68a4d863-1ff3-48ad-9d6d-6f05ad185830"],
    ["8943943","b0f5120c-bf92-4414-be90-00c0e13dc6d4"],
    ["8945645","b835acfe-fd95-49d1-8305-a626b9dfe61b"],
    ["2502724","5cbe7871-5806-49c4-9bdf-d6209c2004d6"],
    ["8947347","0b66526c-6660-4e0a-bdfb-c763b52daa39"],
    ["2499320","2c968537-17b9-4c07-b961-adacc6fd8932"],
    ["2493363","2a278f14-34d4-47a4-8ff0-1038aa82b40d"],
    ["2497618","f3b95871-8604-41ef-a6a3-d590673e5bd3"],
    ["2494214","9fc7ab91-9700-4286-a276-8b7b3dbee99a"],
    ["2495065","c9bb6d80-fe54-488e-846b-215c097dbc6e"],
    ["2506128","05780657-1ff2-4ab4-ae1c-1673f79809cc"],
    ["2506979","dc47d0e5-217f-46f7-9c9e-3b2f3f3582b6"],
    ["2495916","11f02b64-2f61-4810-a63c-6a74c6929c72"],
    ["2501022","0dda8537-086d-4a40-87ab-b060291c84e5"],
    ["2501873","3fe1ba2b-f99c-4541-a5e0-50708517ba58"],
    ["2496767","aff758ef-c00f-4018-b35a-1e41b78e6606"],
    ["485003","d3bf72a4-f13c-47ac-9042-fb4db882f9ff"],
    ["181196","272fe4f5-0492-42f1-8707-c7b8d94242fb"],
    ["178643","94858f81-940c-4b80-89b8-8ae5ac94859d"],
    ["549679","fbb890de-63e0-41ef-b717-cd0320781389"],
    ["99500","a3f6a24f-5d53-4bf7-b212-96a75af872c2"],
    ["168431","400a6e68-7e08-4eba-a353-dcc9ffff22ad"],
    ["73119","f8d7fd61-d971-470d-921a-5bba16f1b5f9"],
    ["468834","811ddef1-d267-4cb8-8af9-1e174a746590"],
    ["477344","a79db322-4b4a-44db-a8ec-19e7197a59d2"],
    ["194812","2588ebf9-b287-4701-81f4-89f0dcaa19a4"],
    ["171835","3777229b-35a2-4c63-b6cf-dd0f203ac795"],
    ["3711144","dfa3938c-5825-46ff-8b3f-5fde84d71a99"],
    ["210981","9e83b3bf-84ea-447c-abfe-26d591d5861d"],
    ["528404","9b6f7bda-89aa-4f30-93d0-74418ed0cba0"],
    ["479897","5afd4187-91bc-4256-b467-5b8e7a33a421"],
    ["550530","221426ea-aca0-45ba-b979-4dec48d53d4c"],
    ["68864","60b0884b-edb4-409c-98fe-2f62b76fe161"],
    ["69715","42d87eae-1099-456c-b16a-bca885fb9a9d"],
    ["352247","6b99ec74-6516-4f4b-b624-bdf04d5604f5"],
    ["471387","946dec8f-170e-47dc-9388-2b99d6e932bf"],
    ["80778","6be7abb5-a6be-4d83-a78e-3dc4fd042eaa"],
    ["535212","060f0948-1b5b-4d85-87f2-1b53c9e50543"],
    ["542871","ef7a6f60-ce26-46a5-b353-aafe7d3cf55d"],
    ["4084733","5d0bb766-e445-4fc2-8973-062539a3aafc"],
    ["1186227","3c07da4e-b521-42ca-95bc-cad1fe72353f"]
  ]'::jsonb;
  new_teams jsonb := '[
    {"ext":"490109","ar":"أيك أثينا","short":"AEK","league":"دوري أبطال أوروبا"},
    {"ext":"279061","ar":"بودو غليمت","short":"BOD","league":"دوري أبطال أوروبا"},
    {"ext":"520745","ar":"فنربخشة","short":"FEN","league":"دوري أبطال أوروبا"},
    {"ext":"873910","ar":"لاسك لينز","short":"LAS","league":"دوري أبطال أوروبا"},
    {"ext":"68013","ar":"ليل","short":"LIL","league":"دوري أبطال أوروبا"},
    {"ext":"11894360","ar":"صباح","short":"SAB","league":"دوري أبطال أوروبا"},
    {"ext":"559040","ar":"سلوفان براتيسلافا","short":"SLO","league":"دوري أبطال أوروبا"},
    {"ext":"646693","ar":"فايكنغ","short":"VIK","league":"دوري أبطال أوروبا"},
    {"ext":"472238","ar":"أندرلخت","short":"AND","league":"الدوري الأوروبي"},
    {"ext":"3135017","ar":"أرارات أرمينيا","short":"ARA","league":"الدوري الأوروبي"},
    {"ext":"180345","ar":"بنفيكا","short":"BEN","league":"الدوري الأوروبي"},
    {"ext":"467983","ar":"بشكتاش","short":"BES","league":"الدوري الأوروبي"},
    {"ext":"554785","ar":"فيرينكفاروس","short":"FTC","league":"الدوري الأوروبي"},
    {"ext":"286720","ar":"ياغيلونيا","short":"JAG","league":"الدوري الأوروبي"},
    {"ext":"296081","ar":"ليخ بوزنان","short":"LPO","league":"الدوري الأوروبي"},
    {"ext":"273955","ar":"ليليستروم","short":"LSK","league":"الدوري الأوروبي"},
    {"ext":"957308","ar":"أوفي كريت","short":"OFI","league":"الدوري الأوروبي"},
    {"ext":"2895886","ar":"أومونيا نيقوسيا","short":"OMO","league":"الدوري الأوروبي"},
    {"ext":"483301","ar":"فيكتوريا بلزن","short":"PLZ","league":"الدوري الأوروبي"},
    {"ext":"486705","ar":"ريد بول سالزبورغ","short":"SAL","league":"الدوري الأوروبي"}
  ]'::jsonb;
  r jsonb;
  v_team_id uuid;
  v_league_id uuid;
  v_mapped uuid;
  v_total integer;
begin
  -- 1. Existing clubs.
  for r in select * from jsonb_array_elements(existing_map)
  loop
    v_team_id := (r->>1)::uuid;
    if not exists (select 1 from football_data.teams where id = v_team_id) then
      raise exception 'highlightly map: catalog team % (provider %) does not exist',
        v_team_id, r->>0;
    end if;

    select canonical_id into v_mapped
    from football_data.external_identity_map
    where external_source = 'highlightly'
      and external_id = r->>0
      and canonical_table = 'team';

    if v_mapped is null then
      insert into football_data.external_identity_map
        (external_source, external_id, canonical_table, canonical_id)
      values ('highlightly', r->>0, 'team', v_team_id);
    elsif v_mapped <> v_team_id then
      raise exception 'highlightly map: provider team % already maps to %, not %',
        r->>0, v_mapped, v_team_id;
    end if;
  end loop;

  -- 2. Clubs new to the catalog.
  for r in select * from jsonb_array_elements(new_teams)
  loop
    select canonical_id into v_mapped
    from football_data.external_identity_map
    where external_source = 'highlightly'
      and external_id = r->>'ext'
      and canonical_table = 'team';

    if v_mapped is null then
      select id into v_league_id
      from football_data.leagues
      where btrim(name) = r->>'league';
      if v_league_id is null then
        raise exception 'highlightly map: league "%" not found', r->>'league';
      end if;

      v_team_id := gen_random_uuid();
      insert into football_data.teams (id, name, short_name, crest_url, league_id)
      values (v_team_id, r->>'ar', r->>'short', null, v_league_id);
      insert into football_data.external_identity_map
        (external_source, external_id, canonical_table, canonical_id)
      values ('highlightly', r->>'ext', 'team', v_team_id);
    end if;
  end loop;

  select count(*) into v_total
  from football_data.external_identity_map
  where external_source = 'highlightly' and canonical_table = 'team';
  if v_total < 141 then
    raise exception 'highlightly map: expected at least 141 mapped teams, found %', v_total;
  end if;
end
$$;

commit;
