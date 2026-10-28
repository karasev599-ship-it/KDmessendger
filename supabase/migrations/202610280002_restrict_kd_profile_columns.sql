begin;

-- Remove broad table-level access first. Column grants below expose only
-- fields intended to be public/searchable to signed-in users.
revoke all privileges on table public.kd_profiles from public, anon, authenticated;

revoke select (id, username, display_name, avatar_url, bio, is_online, last_seen,
  created_at, updated_at, phone, phone_visible, qr_token, tag,
  secret_chats_enabled, suspended_at, suspension_reason, status)
  on table public.kd_profiles from public, anon, authenticated;

revoke insert (id, username, display_name, avatar_url, bio, is_online, last_seen,
  created_at, updated_at, phone, phone_visible, qr_token, tag,
  secret_chats_enabled, suspended_at, suspension_reason, status)
  on table public.kd_profiles from public, anon, authenticated;

revoke update (id, username, display_name, avatar_url, bio, is_online, last_seen,
  created_at, updated_at, phone, phone_visible, qr_token, tag,
  secret_chats_enabled, suspended_at, suspension_reason, status)
  on table public.kd_profiles from public, anon, authenticated;

-- Public-facing profile data remains readable for contact search and chat headers.
grant select (id, username, display_name, avatar_url, bio, is_online, last_seen,
  created_at, updated_at, tag)
  on table public.kd_profiles to authenticated;

-- A signed-in user can create/update only normal profile fields. Sensitive
-- contact, QR, suspension, and moderation fields are not directly writable here.
grant insert (id, username, display_name)
  on table public.kd_profiles to authenticated;

grant update (username, display_name, avatar_url, bio, is_online, last_seen,
  updated_at, tag)
  on table public.kd_profiles to authenticated;

commit;