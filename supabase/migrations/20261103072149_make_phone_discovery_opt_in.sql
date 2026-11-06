begin;

-- Phone discovery must be opt-in. Keep explicit legacy choices when creating
-- missing privacy rows, then default new users to not discoverable.
insert into public.kd_user_privacy (user_id, discover_by_phone)
select pp.user_id, coalesce(pp.phone_visible, false)
from public.kd_profile_private pp
left join public.kd_user_privacy up on up.user_id = pp.user_id
where up.user_id is null
on conflict (user_id) do nothing;

alter table public.kd_user_privacy
  alter column discover_by_phone set default false;

create or replace function public.kd_find_profiles_by_phone(p_phones text[])
returns table (id uuid, display_name text, username text, matched_phone text)
language plpgsql
security definer
set search_path = pg_catalog, public
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

  if not public.check_api_rate_limit('phone_lookup', md5(v_user::text), 60, 10) then
    raise exception 'Too many phone lookup requests; try again later' using errcode = 'P0001';
  end if;

  return query
  select p.id, p.display_name, p.username, pp.phone
  from public.kd_profile_private pp
  join public.kd_profiles p on p.id = pp.user_id
  left join public.kd_user_privacy up on up.user_id = pp.user_id
  where coalesce(up.discover_by_phone, false) = true
    and pp.phone = any(p_phones)
    and p.id <> v_user
  limit 200;
end;
$function$;

revoke all on function public.kd_find_profiles_by_phone(text[]) from public, anon, authenticated;
grant execute on function public.kd_find_profiles_by_phone(text[]) to authenticated;

commit;
