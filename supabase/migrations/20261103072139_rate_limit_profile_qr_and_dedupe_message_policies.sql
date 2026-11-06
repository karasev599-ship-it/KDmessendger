begin;

-- QR lookup is an authenticated discovery endpoint. Apply a per-user limit
-- before validating the token so malformed guesses are counted as well.
create or replace function public.kd_resolve_profile_qr(p_token text)
returns table (id uuid, display_name text, username text, tag text)
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

  if not public.check_api_rate_limit('profile_qr_lookup', md5(v_user::text), 60, 30) then
    raise exception 'Too many QR lookup requests; try again later' using errcode = 'P0001';
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

revoke all on function public.kd_resolve_profile_qr(text) from public, anon, authenticated;
grant execute on function public.kd_resolve_profile_qr(text) to authenticated;

-- Both UPDATE policies had identical USING and WITH CHECK expressions.
-- Keep the general owner-update policy; remove the duplicate.
drop policy if exists kd_messages_sender_delete on public.kd_messages;

-- The two indexes have identical btree definitions and neither backs a constraint.
drop index if exists public.kd_messages_conversation_created_idx;

commit;
