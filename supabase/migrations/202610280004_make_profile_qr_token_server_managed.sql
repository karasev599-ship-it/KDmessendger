begin;

-- QR tokens are generated with the profile row and must not be client-chosen.
revoke insert (qr_token) on table public.kd_profile_private from public, anon, authenticated;
revoke update (qr_token) on table public.kd_profile_private from public, anon, authenticated;

commit;