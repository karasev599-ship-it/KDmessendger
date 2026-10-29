begin;

create or replace function public.kd_ensure_device(p_name text, p_type text, p_agent text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := auth.uid();
  v_name text;
  v_type text;
  v_agent text;
  v_device_id uuid;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  v_name := left(coalesce(nullif(btrim(p_name), ''), 'Web'), 80);
  v_type := case when p_type in ('web', 'mobile', 'desktop', 'tablet') then p_type else 'web' end;
  v_agent := left(coalesce(p_agent, ''), 500);

  if not public.check_api_rate_limit('ensure_device', md5(v_user::text), 60, 30) then
    raise exception 'Too many device registration requests; try again later' using errcode = 'P0001';
  end if;

  -- Serialize concurrent registration calls for the same user/browser signature.
  perform pg_advisory_xact_lock(
    hashtextextended(v_user::text || ':' || v_type || ':' || md5(v_agent), 0)
  );

  select d.id
    into v_device_id
  from public.kd_devices d
  where d.user_id = v_user
    and d.device_type = v_type
    and coalesce(d.user_agent, '') = v_agent
  order by d.last_active_at desc
  limit 1
  for update;

  if v_device_id is not null then
    update public.kd_devices
       set device_name = v_name,
           user_agent = nullif(v_agent, ''),
           last_active_at = now()
     where id = v_device_id
       and user_id = v_user;
    return v_device_id;
  end if;

  insert into public.kd_devices(user_id, device_name, device_type, user_agent, last_active_at)
  values (v_user, v_name, v_type, nullif(v_agent, ''), now())
  returning id into v_device_id;

  return v_device_id;
end;
$function$;

revoke all on function public.kd_ensure_device(text, text, text) from public, anon, authenticated;
grant execute on function public.kd_ensure_device(text, text, text) to authenticated;

commit;