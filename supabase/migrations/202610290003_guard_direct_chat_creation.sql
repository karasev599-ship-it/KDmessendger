begin;

create or replace function public.kd_create_direct_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  me uuid := auth.uid();
  cid uuid;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if other_user_id is null or other_user_id = me then
    raise exception 'Invalid user' using errcode = '22023';
  end if;

  if not public.check_api_rate_limit('direct_chat_create', md5(me::text), 60, 30) then
    raise exception 'Too many chat creation requests; try again later' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(least(me::text, other_user_id::text) || ':' ||
                     greatest(me::text, other_user_id::text), 0)
  );

  if not exists (
    select 1 from public.kd_profiles p where p.id = other_user_id
  ) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  -- A user who has blocked the caller must not receive a new direct conversation.
  if exists (
    select 1
    from public.kd_blocked_users b
    where b.user_id = other_user_id
      and b.blocked_user_id = me
  ) then
    raise exception 'This user does not accept messages from you' using errcode = '42501';
  end if;

  select c.id into cid
  from public.kd_conversations c
  where c.kind = 'direct'
    and exists (
      select 1 from public.kd_conversation_members m
      where m.conversation_id = c.id and m.user_id = me
    )
    and exists (
      select 1 from public.kd_conversation_members m
      where m.conversation_id = c.id and m.user_id = other_user_id
    )
  limit 1;

  if cid is not null then
    return cid;
  end if;

  insert into public.kd_conversations(kind, created_by, updated_at)
  values ('direct', me, now())
  returning id into cid;

  insert into public.kd_conversation_members(conversation_id, user_id, role)
  values (cid, me, 'owner'), (cid, other_user_id, 'member');

  return cid;
end;
$function$;

revoke all on function public.kd_create_direct_conversation(uuid) from public, anon, authenticated;
grant execute on function public.kd_create_direct_conversation(uuid) to authenticated;

commit;