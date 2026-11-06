begin;

create or replace function public.kd_close_group_poll(p_poll_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := auth.uid();
  v_conversation_id uuid;
  v_created_by uuid;
  v_role text;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select p.conversation_id, p.created_by
    into v_conversation_id, v_created_by
  from public.kd_group_polls p
  where p.id = p_poll_id;

  if v_conversation_id is null then
    raise exception 'Poll not found' using errcode = 'P0002';
  end if;

  select m.role into v_role
  from public.kd_conversation_members m
  where m.conversation_id = v_conversation_id
    and m.user_id = v_user;

  if v_role is null then
    raise exception 'Not a conversation member' using errcode = '42501';
  end if;

  if v_role not in ('owner', 'admin') and v_created_by is distinct from v_user then
    raise exception 'Not allowed to close this poll' using errcode = '42501';
  end if;

  update public.kd_group_polls
     set closed = true
   where id = p_poll_id
     and conversation_id = v_conversation_id;

  return found;
end;
$function$;

revoke all on function public.kd_close_group_poll(uuid) from public, anon, authenticated;
grant execute on function public.kd_close_group_poll(uuid) to authenticated;

commit;