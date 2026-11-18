-- The group chat's moderation (migration 0216, script 281). A player's report
-- of a message reaches the owner in his support chat (script 225) with the
-- sender's name and id, the message id and its text. Run each statement in
-- the Supabase SQL Editor; none of them runs by itself.

-- 1. The latest messages of a player, with their ids (use the sender id the
--    report carries).
select m.id as message_id, m.created_at, m.league_id, m.body,
       m.hidden_at is not null as hidden
from chat.h2h_messages m
where m.sender_id = '00000000-0000-0000-0000-000000000000'
order by m.id desc
limit 50;

-- 2. The latest messages of a group, to read a report in its context.
-- select m.id as message_id, m.created_at, u.display_name, m.body,
--        m.hidden_at is not null as hidden
-- from chat.h2h_messages m
-- join identity.users u on u.id = m.sender_id
-- where m.league_id = (select league_id from chat.h2h_messages
--                       where id = 123)
-- order by m.id desc
-- limit 50;

-- 3. Hide a message (it stays as evidence, nobody sees it any more). Replace
--    123 with the message id and the uuid with your own account's id.
-- update chat.h2h_messages
--    set hidden_at = now(), hidden_by = '00000000-0000-0000-0000-000000000000'
--  where id = 123;

-- 4. Bar a player from writing, and let him write again.
-- insert into chat.muted_users (user_id, muted_by, reason)
-- values ('00000000-0000-0000-0000-000000000000',
--         '00000000-0000-0000-0000-000000000000', 'abuse')
-- on conflict (user_id) do nothing;
-- delete from chat.muted_users
--  where user_id = '00000000-0000-0000-0000-000000000000';
