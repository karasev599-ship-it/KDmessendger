begin;

create or replace function public.kd_find_profiles_by_phone(p_phones text[])
returns table (id uuid, display_name text, username text, matched_phone text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := auth.uid();
  v_slots integer;
  v_i integer;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if p_phones is null or cardinality(p_phones) < 1 or cardinality(p_phones) > 500 then
    raise exception 'Invalid phone list' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(p_phones) as item(phone)
    where item.phone is null
       or length(item.phone) > 16
       or item.phone !~ '^\\+?[0-9]{7,15}$'
  ) then
    raise exception 'Invalid phone number format' using errcode = '22023';
  end if;

  -- Charge one rate-limit unit per 100 phone candidates.
  -- This preserves compatibility with older clients that send up to 500 at once.
  v_slots := ceil(cardinality(p_phones)::numeric / 100)::integer;
  for v_i in 1..v_slots loop
    if not public.check_api_rate_limit('phone_lookup', md5(v_user::text), 60, 20) then
      raise exception 'Too many phone lookup requests; try again later' using errcode = 'P0001';
    end if;
  end loop;

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