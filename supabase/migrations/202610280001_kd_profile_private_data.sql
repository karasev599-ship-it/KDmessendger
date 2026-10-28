begin;

-- Move contact lookup data out of the broadly searchable profile table.
create table if not exists public.kd_profile_private (
  user_id uuid primary key references auth.users(id) on delete cascade,
  phone text,
  phone_visible boolean not null default false,
  qr_token uuid,
  updated_at timestamptz not null default now()
);

insert into public.kd_profile_private (user_id, phone, phone_visible, qr_token, updated_at)
select id, phone, phone_visible, qr_token, coalesce(updated_at, now())
from public.kd_profiles
on conflict (user_id) do update
set phone = excluded.phone,
    phone_visible = excluded.phone_visible,
    qr_token = excluded.qr_token,
    updated_at = excluded.updated_at;

alter table public.kd_profile_private enable row level security;
drop policy if exists kd_profile_private_select_own on public.kd_profile_private;
drop policy if exists kd_profile_private_insert_own on public.kd_profile_private;
drop policy if exists kd_profile_private_update_own on public.kd_profile_private;
create policy kd_profile_private_select_own on public.kd_profile_private
  for select to authenticated using (user_id = auth.uid());
create policy kd_profile_private_insert_own on public.kd_profile_private
  for insert to authenticated with check (user_id = auth.uid());
create policy kd_profile_private_update_own on public.kd_profile_private
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all privileges on table public.kd_profile_private from public, anon, authenticated;
grant select on table public.kd_profile_private to authenticated;
grant insert (user_id, phone, phone_visible, qr_token, updated_at)
  on table public.kd_profile_private to authenticated;
grant update (phone, phone_visible, qr_token, updated_at)
  on table public.kd_profile_private to authenticated;

create index if not exists kd_profile_private_visible_phone_idx
  on public.kd_profile_private (phone) where phone_visible = true;

create or replace function public.kd_find_profiles_by_phone(p_phones text[])
returns table (id uuid, display_name text, username text, matched_phone text)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if p_phones is null or cardinality(p_phones) < 1 or cardinality(p_phones) > 500 then
    raise exception 'Invalid phone list' using errcode = '22023';
  end if;

  return query
  select p.id, p.display_name, p.username, pp.phone
  from public.kd_profile_private pp
  join public.kd_profiles p on p.id = pp.user_id
  where pp.phone_visible = true
    and pp.phone = any(p_phones)
    and p.id <> v_user
  limit 200;
end;
$function$;

create or replace function public.kd_resolve_profile_qr(p_token text)
returns table (id uuid, display_name text, username text, tag text)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if p_token is null or length(p_token) > 36
     or p_token !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return;
  end if;

  return query
  select p.id, p.display_name, p.username, p.tag
  from public.kd_profile_private pp
  join public.kd_profiles p on p.id = pp.user_id
  where pp.qr_token = p_token::uuid
  limit 1;
end;
$function$;

create or replace function public.kd_get_my_suspension_status()
returns table (suspended_at timestamptz, suspension_reason text)
language sql
security definer
set search_path = public
as $function$
  select p.suspended_at, p.suspension_reason
  from public.kd_profiles p
  where p.id = auth.uid()
  limit 1;
$function$;

revoke all on function public.kd_find_profiles_by_phone(text[]) from public, anon, authenticated;
revoke all on function public.kd_resolve_profile_qr(text) from public, anon, authenticated;
revoke all on function public.kd_get_my_suspension_status() from public, anon, authenticated;
grant execute on function public.kd_find_profiles_by_phone(text[]) to authenticated;
grant execute on function public.kd_resolve_profile_qr(text) to authenticated;
grant execute on function public.kd_get_my_suspension_status() to authenticated;

commit;