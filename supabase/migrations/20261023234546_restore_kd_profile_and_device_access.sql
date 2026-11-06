-- Restore the minimum client privileges required by the authenticated Messenger UI.
-- Row-level security policies continue to constrain which profile rows can be read or changed.
grant select, insert, update on table public.kd_profiles to authenticated;

-- The client calls this SECURITY DEFINER helper to register the current device.
grant execute on function public.kd_ensure_device(text, text, text) to authenticated;
