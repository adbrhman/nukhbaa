-- Back to normal (script 292, 0222) -- one row changed.
--
-- The way back if the owners' page cannot be reached while the app is
-- read only or closed. The server reads the mode at most ten seconds
-- late. Safe to run twice; the reason is required, change it to the real
-- one.
update ops.app_mode
   set mode = 'normal',
       reason = 'عودة إلى الوضع العادي من محرر SQL',
       changed_by = null,
       changed_at = now()
 where id
returning mode, reason, changed_at;
