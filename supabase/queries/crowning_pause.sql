-- Stop the month's crowning (script 286, 0218) -- one row changed.
--
-- The owners' switch, until the owner's page has its button. From this
-- statement on, no month is crowned by itself (the server reads the switch
-- every two minutes) and no admin crowns one by hand: he is told that the
-- crowning is paused. An owner may still crown by hand from the admin
-- page. The owners are told once per month that waits. Nothing is deleted:
-- a crowning already done stays. Undone by crowning_resume.sql. Safe to
-- run twice; the reason is required, change it to the real one.
update ops.owner_switches
   set is_on = false,
       reason = 'إيقاف احترازي قبل التحقق من نقاط الشهر',
       changed_by = null,
       changed_at = now()
 where switch_key = 'crowning'
returning switch_key, is_on, reason, changed_at;
