-- Restrict the group audit-event logger to trusted database functions.
-- Authenticated clients do not call this RPC directly; group invite/join
-- SECURITY DEFINER routines can continue to invoke it as the function owner.
begin;

revoke execute on function public.kd_group_log_event(uuid, text, uuid, text, text)
  from public, anon, authenticated;

commit;
