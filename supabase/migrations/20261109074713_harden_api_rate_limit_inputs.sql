-- Harden the internal rate limiter against malformed keys and unsafe name resolution.
-- Only service_role may invoke this function directly; SECURITY DEFINER callers
-- continue to work as the function owner.
begin;

create or replace function public.check_api_rate_limit(
  p_bucket text,
  p_subject_hash text,
  p_window_seconds integer,
  p_max_hits integer
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_window timestamptz;
  v_hits integer;
begin
  if p_bucket is null or p_bucket !~ '^[a-z0-9_]{1,48}$' then
    return false;
  end if;

  if p_subject_hash is null or p_subject_hash !~ '^[0-9a-f]{32,64}$' then
    return false;
  end if;

  if p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 86400
     or p_max_hits is null or p_max_hits < 1 or p_max_hits > 10000 then
    return false;
  end if;

  v_window := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.api_rate_limits(bucket, subject_hash, window_start, hits, updated_at)
  values (p_bucket, p_subject_hash, v_window, 1, now())
  on conflict (bucket, subject_hash, window_start)
  do update set hits = public.api_rate_limits.hits + 1, updated_at = now()
  returning hits into v_hits;

  return v_hits <= p_max_hits;
end;
$function$;

revoke all on function public.check_api_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.check_api_rate_limit(text, text, integer, integer)
  to service_role;

commit;
