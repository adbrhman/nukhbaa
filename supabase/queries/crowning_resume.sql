-- Turn the month's crowning back on (script 286, 0218) -- one row changed.
--
-- Undoes crowning_pause.sql. A month that waited is crowned by itself on
-- the server's next run (within two minutes), as if it had just ended, as
-- long as it is within three days of its end; past that, crown it by hand
-- from the admin page. Safe to run twice; the reason is required, change
-- it to the real one.
update ops.owner_switches
   set is_on = true,
       reason = 'تم التحقق من نقاط الشهر',
       changed_by = null,
       changed_at = now()
 where switch_key = 'crowning'
returning switch_key, is_on, reason, changed_at;
